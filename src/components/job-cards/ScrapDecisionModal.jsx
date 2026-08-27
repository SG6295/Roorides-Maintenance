import { useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { XMarkIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../../hooks/useAuth'
import {
    useCloseJobCardWithScrap,
    useExistingScrapForJobCard,
    PERMANENT_SCRAP_STATUSES,
    ScrapRPCError,
} from '../../hooks/useScrap'
import { logAuditEvent } from '../../utils/auditLogger'
import CustomSelect from '../shared/CustomSelect'

const EXCLUSION_REASON_OPTIONS = [
    { value: 'consumable',           label: 'Consumable' },
    { value: 'destroyed_on_removal', label: 'Destroyed on removal' },
    { value: 'retained_by_vendor',   label: 'Retained by vendor' },
    { value: 'other',                label: 'Other' },
]

const OUTSOURCE_DISPOSITION_OPTIONS = [
    { value: 'returned_to_nvs',                  label: 'Returned to NVS' },
    { value: 'retained_by_vendor',               label: 'Retained by vendor (no credit)' },
    { value: 'retained_by_vendor_with_credit',   label: 'Retained by vendor (with credit)' },
]

function buildInitialDecisions(jobCard) {
    const decisions = {}
    for (const issue of jobCard.issues || []) {
        for (const ip of issue.issue_parts || []) {
            decisions[ip.id] = {
                action: 'scrap',
                exclusionReason: null,
                exclusionNotes: '',
                outsourceDisposition: null,
                outsourceCreditAmount: '',
            }
        }
    }
    return decisions
}

export default function ScrapDecisionModal({ jobCard, invoicePending = false, onClose, onSuccess, onRaceError }) {
    const { userProfile } = useAuth()
    const queryClient = useQueryClient()
    const closeJobCard = useCloseJobCardWithScrap()
    const { data: existingScrapMap = {} } = useExistingScrapForJobCard(jobCard.id)

    const isOutsource = jobCard.type === 'Outsource'

    const [decisions, setDecisions] = useState(() => buildInitialDecisions(jobCard))
    const [remarks, setRemarks] = useState(jobCard.remarks || '')
    const [submitError, setSubmitError] = useState(null)

    const updateDecision = (issuePartId, field, value) => {
        setDecisions(prev => ({
            ...prev,
            [issuePartId]: { ...prev[issuePartId], [field]: value },
        }))
    }

    const isValid = Object.entries(decisions).every(([issuePartId, d]) => {
        // Group A parts are not submitted — no validation required
        if (PERMANENT_SCRAP_STATUSES.includes(existingScrapMap[issuePartId]?.status)) return true
        if (d.action === 'exclude') {
            if (d.exclusionReason === null) return false
            // "Other" carries no meaning on its own — require a note
            if (d.exclusionReason === 'other') return d.exclusionNotes.trim() !== ''
            return true
        }
        if (d.action === 'scrap' && isOutsource) {
            if (!d.outsourceDisposition) return false
            if (d.outsourceDisposition === 'retained_by_vendor_with_credit') {
                const amt = parseFloat(d.outsourceCreditAmount)
                return !isNaN(amt) && amt > 0
            }
        }
        return true
    })

    const handleSubmit = async () => {
        setSubmitError(null)

        // Group A parts (permanent scrap) are excluded from the decisions array —
        // their existing scrap entries stay untouched.
        const scrapDecisions = Object.entries(decisions)
            .filter(([issuePartId]) =>
                !PERMANENT_SCRAP_STATUSES.includes(existingScrapMap[issuePartId]?.status)
            )
            .map(([issuePartId, d]) => {
                const entry = { issue_part_id: issuePartId, action: d.action }
                if (d.action === 'exclude') {
                    entry.exclusion_reason = d.exclusionReason
                    entry.exclusion_notes  = d.exclusionNotes.trim() || null
                } else if (d.action === 'scrap' && isOutsource) {
                    entry.outsource_disposition = d.outsourceDisposition
                    if (d.outsourceDisposition === 'retained_by_vendor_with_credit') {
                        entry.outsource_credit_amount = parseFloat(d.outsourceCreditAmount)
                    }
                }
                return entry
            })

        try {
            const result = await closeJobCard.mutateAsync({
                jobCardId:      jobCard.id,
                remarks:        remarks.trim() || null,
                scrapDecisions,
                invoicePending,
            })

            const newStatus = invoicePending ? 'Completed - Invoice Pending' : 'Completed'
            // Audit: job card closure
            await logAuditEvent(jobCard.id, 'job_cards', 'UPDATE', userProfile.id, {
                oldData:       { status: 'Open', completed_at: null, remarks: jobCard.remarks },
                newData:       { status: newStatus, completed_at: new Date().toISOString(), remarks: remarks.trim() || null },
                changedFields: ['status', 'completed_at', 'remarks'],
            })

            // Audit: each scrap_inventory row created
            for (const scrapId of result.scrap_entry_ids || []) {
                await logAuditEvent(scrapId, 'scrap_inventory', 'INSERT', userProfile.id, {
                    oldData:       null,
                    newData:       { id: scrapId, source_job_card_id: jobCard.id, status: 'in_storage' },
                    changedFields: [],
                })
            }

            // Audit: each scrap_excluded_parts row created
            for (const exclusionId of result.exclusion_ids || []) {
                await logAuditEvent(exclusionId, 'scrap_excluded_parts', 'INSERT', userProfile.id, {
                    oldData:       null,
                    newData:       { id: exclusionId, source_job_card_id: jobCard.id },
                    changedFields: [],
                })
            }

            // Audit: in_storage scrap entries reversed during re-close
            for (const scrapId of result.reversed_scrap_ids || []) {
                await logAuditEvent(scrapId, 'scrap_inventory', 'UPDATE', userProfile.id, {
                    oldData:       { status: 'in_storage' },
                    newData:       { status: 'reversed' },
                    changedFields: ['status', 'updated_at', 'updated_by'],
                })
            }

            onSuccess()
        } catch (err) {
            if (err instanceof ScrapRPCError) {
                const { errorCode } = err
                if (errorCode === 'DECISIONS_MISSING_PART' || errorCode === 'DECISIONS_EXTRA_PART') {
                    // Parts changed while modal was open — stale decisions cannot be retried.
                    // Close the modal and let the parent show the error with fresh data.
                    queryClient.invalidateQueries({ queryKey: ['job_card'] })
                    onRaceError(err.message)
                } else {
                    setSubmitError(err.message)
                }
            } else {
                setSubmitError('Failed to complete job card. Please try again.')
            }
        }
    }

    const issuesWithParts = (jobCard.issues || []).filter(i => (i.issue_parts?.length ?? 0) > 0)

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-2xl flex flex-col max-h-[90vh]">

                {/* Header */}
                <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 shrink-0">
                    <div>
                        <h2 className="text-base font-semibold text-gray-900">
                            {invoicePending ? 'Close Job Card — Invoice Pending' : 'Complete Job Card'}
                        </h2>
                        <p className="text-xs text-gray-500 mt-0.5">
                            {invoicePending
                                ? 'Work is done. Set scrap disposition for each part — invoice can be added later.'
                                : 'Set scrap disposition for each part before closing.'}
                        </p>
                    </div>
                    <button
                        type="button"
                        onClick={onClose}
                        disabled={closeJobCard.isPending}
                        className="text-gray-400 hover:text-gray-600 transition-colors disabled:opacity-40"
                    >
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                {/* Body */}
                <div className="overflow-y-auto flex-1 px-6 py-5 space-y-6">

                    {submitError && (
                        <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
                            {submitError}
                        </div>
                    )}

                    {issuesWithParts.length === 0 && (
                        <p className="text-sm text-gray-500 text-center py-4">
                            No parts recorded on this job card.
                        </p>
                    )}

                    {issuesWithParts.map(issue => (
                        <div key={issue.id} className="space-y-3">
                            <h3 className="text-sm font-semibold text-gray-700 border-b border-gray-100 pb-1">
                                {issue.category}: {issue.description}
                            </h3>

                            {issue.issue_parts.map(ip => {
                                const d = decisions[ip.id]
                                if (!d) return null
                                const existingScrap = existingScrapMap[ip.id]
                                const isPermanent = PERMANENT_SCRAP_STATUSES.includes(existingScrap?.status)
                                const isInStorage = existingScrap?.status === 'in_storage'
                                return (
                                    <div key={ip.id} className="rounded-lg bg-gray-50 border border-gray-200 p-3 space-y-3">

                                        {/* Part label */}
                                        <div className="flex items-center gap-2 flex-wrap">
                                            <p className="text-sm font-medium text-gray-800">
                                                {ip.part?.name ?? 'Unknown part'} &times; {ip.quantity_used} {ip.part?.unit ?? ''}
                                            </p>
                                            {isPermanent && (
                                                <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-700">
                                                    Already {existingScrap.status.replace(/_/g, ' ')}
                                                </span>
                                            )}
                                        </div>

                                        {/* Scrap / Exclude radio */}
                                        <div className="flex items-center gap-6">
                                            <label className={`flex items-center gap-2 ${isPermanent ? 'cursor-not-allowed opacity-70' : 'cursor-pointer'}`}>
                                                <input
                                                    type="radio"
                                                    name={`action-${ip.id}`}
                                                    value="scrap"
                                                    checked={d.action === 'scrap'}
                                                    onChange={() => !isPermanent && updateDecision(ip.id, 'action', 'scrap')}
                                                    disabled={isPermanent}
                                                    className="accent-green-600"
                                                />
                                                <span className="text-sm text-gray-700">Generate scrap</span>
                                            </label>
                                            <label className={`flex items-center gap-2 ${isPermanent ? 'cursor-not-allowed opacity-40' : 'cursor-pointer'}`}>
                                                <input
                                                    type="radio"
                                                    name={`action-${ip.id}`}
                                                    value="exclude"
                                                    checked={d.action === 'exclude'}
                                                    onChange={() => !isPermanent && updateDecision(ip.id, 'action', 'exclude')}
                                                    disabled={isPermanent}
                                                    className="accent-orange-500"
                                                />
                                                <span className="text-sm text-gray-700">Exclude from scrap</span>
                                            </label>
                                        </div>

                                        {isInStorage && (
                                            <p className="text-xs text-amber-600">
                                                Previously scrapped — previous entry will be replaced on submit.
                                            </p>
                                        )}

                                        {/* Outsource disposition (only for scrap + Outsource jobs, not locked Group A parts) */}
                                        {d.action === 'scrap' && isOutsource && !isPermanent && (
                                            <div className="space-y-2">
                                                <CustomSelect
                                                    label="Outsource disposition"
                                                    value={d.outsourceDisposition ?? ''}
                                                    onChange={v => updateDecision(ip.id, 'outsourceDisposition', v)}
                                                    options={OUTSOURCE_DISPOSITION_OPTIONS}
                                                    placeholder="Select disposition…"
                                                />
                                                {d.outsourceDisposition === 'retained_by_vendor_with_credit' && (
                                                    <div>
                                                        <label className="block text-sm font-medium text-gray-700 mb-1">
                                                            Vendor credit amount (₹)
                                                        </label>
                                                        <input
                                                            type="number"
                                                            min="0.01"
                                                            step="0.01"
                                                            value={d.outsourceCreditAmount}
                                                            onChange={e => updateDecision(ip.id, 'outsourceCreditAmount', e.target.value)}
                                                            placeholder="0.00"
                                                            className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                                                        />
                                                    </div>
                                                )}
                                            </div>
                                        )}

                                        {/* Exclusion reason + notes */}
                                        {d.action === 'exclude' && !isPermanent && (
                                            <div className="space-y-2">
                                                <CustomSelect
                                                    label="Exclusion reason"
                                                    value={d.exclusionReason ?? ''}
                                                    onChange={v => updateDecision(ip.id, 'exclusionReason', v)}
                                                    options={EXCLUSION_REASON_OPTIONS}
                                                    placeholder="Select reason…"
                                                />
                                                <div>
                                                    <label className="block text-sm font-medium text-gray-700 mb-1">
                                                        {d.exclusionReason === 'other' ? 'Notes (required)' : 'Notes (optional)'}
                                                    </label>
                                                    <input
                                                        type="text"
                                                        value={d.exclusionNotes}
                                                        onChange={e => updateDecision(ip.id, 'exclusionNotes', e.target.value)}
                                                        placeholder={d.exclusionReason === 'other'
                                                            ? 'Explain why this part is excluded…'
                                                            : 'Additional details…'}
                                                        className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                                                    />
                                                </div>
                                            </div>
                                        )}
                                    </div>
                                )
                            })}
                        </div>
                    ))}

                    {/* Remarks */}
                    <div>
                        <label className="block text-sm font-medium text-gray-700 mb-1">
                            Remarks (optional)
                        </label>
                        <textarea
                            rows={2}
                            value={remarks}
                            onChange={e => setRemarks(e.target.value)}
                            placeholder="Any final notes for this job card…"
                            className="w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
                        />
                    </div>
                </div>

                {/* Footer */}
                <div className="flex justify-end gap-3 px-6 py-4 border-t border-gray-200 shrink-0">
                    <button
                        type="button"
                        onClick={onClose}
                        disabled={closeJobCard.isPending}
                        className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                    >
                        Cancel
                    </button>
                    <button
                        type="button"
                        onClick={handleSubmit}
                        disabled={!isValid || closeJobCard.isPending}
                        className="px-4 py-2 text-sm font-medium text-white bg-green-600 rounded-lg hover:bg-green-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
                    >
                        {closeJobCard.isPending
                            ? (invoicePending ? 'Closing…' : 'Completing…')
                            : (invoicePending ? 'Confirm and Close' : 'Confirm and Complete')}
                    </button>
                </div>
            </div>
        </div>
    )
}
