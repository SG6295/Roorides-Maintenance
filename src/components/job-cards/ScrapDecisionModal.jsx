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
import {
    EXCLUSION_REASON_OPTIONS,
    exclusionReasonLabel,
    isDefaultEligibleReason,
} from '../../constants/scrapExclusion'
import CustomSelect from '../shared/CustomSelect'

const OUTSOURCE_DISPOSITION_OPTIONS = [
    { value: 'returned_to_nvs',                  label: 'Returned to NVS' },
    { value: 'retained_by_vendor',               label: 'Retained by vendor (no credit)' },
    { value: 'retained_by_vendor_with_credit',   label: 'Retained by vendor (with credit)' },
]

/**
 * Which part-master control, if any, this row can offer — the exec teaching the
 * system as they work, rather than making a separate trip to the Parts Catalog.
 *
 * Offers are keyed by part, not by issue_part: a part can appear on a card twice
 * and can only carry one standing default, so two rows of the same part share a
 * single tick and cannot disagree. The RPC rejects contradictory directives
 * outright, so the UI must not be able to produce them.
 */
function defaultOfferFor(ip, decision, isPermanent) {
    const part = ip.part
    // A permanently-scrapped row is locked, and a part that no longer exists has
    // no master record to teach.
    if (!part?.id || isPermanent) return null

    if (decision.action === 'exclude' && isDefaultEligibleReason(decision.exclusionReason)) {
        // Nothing to offer when the part already stores exactly this. A stored
        // default with a *different* reason still offers, so a wrong default can
        // be corrected here instead of in the catalog.
        const alreadyStored = part.default_exclude_from_scrap
            && part.default_exclusion_reason === decision.exclusionReason
        if (alreadyStored) return null
        return { partId: part.id, partName: part.name, kind: 'set', reason: decision.exclusionReason }
    }

    if (decision.action === 'scrap' && part.default_exclude_from_scrap) {
        return { partId: part.id, partName: part.name, kind: 'clear', reason: null }
    }

    return null
}

function isPicked(partDefaults, offer) {
    const picked = partDefaults[offer.partId]
    return picked?.kind === offer.kind && picked?.reason === offer.reason
}

/**
 * The ticks that are still live, in row order and one per part.
 *
 * A tick whose row no longer offers the same directive — the exec changed the
 * reason to Other, or flipped back to Generate scrap — is simply not collected,
 * so it can neither be sent nor listed in the confirmation. It is kept rather
 * than deleted so that undoing the change restores the tick, and every live one
 * is visible as a ticked box.
 */
function collectDefaultDirectives(jobCard, decisions, partDefaults, existingScrapMap) {
    const directives = []
    const seen = new Set()

    for (const issue of jobCard.issues || []) {
        for (const ip of issue.issue_parts || []) {
            const decision = decisions[ip.id]
            if (!decision) continue

            const isPermanent = PERMANENT_SCRAP_STATUSES.includes(existingScrapMap[ip.id]?.status)
            const offer = defaultOfferFor(ip, decision, isPermanent)
            if (!offer || seen.has(offer.partId)) continue
            if (!isPicked(partDefaults, offer)) continue

            seen.add(offer.partId)
            directives.push({ ...offer, issuePartId: ip.id })
        }
    }

    return directives
}

function buildInitialDecisions(jobCard) {
    const decisions = {}
    for (const issue of jobCard.issues || []) {
        for (const ip of issue.issue_parts || []) {
            // A part flagged in the part master opens pre-set to Exclude with its
            // reason filled in, so consumables need no interaction at all. The DB
            // constraint guarantees a reason travels with the flag; the reason is
            // checked anyway because a decision without one cannot be submitted.
            const fromDefault = Boolean(
                ip.part?.default_exclude_from_scrap && ip.part?.default_exclusion_reason
            )
            decisions[ip.id] = {
                action: fromDefault ? 'exclude' : 'scrap',
                exclusionReason: fromDefault ? ip.part.default_exclusion_reason : null,
                exclusionNotes: '',
                fromDefault,
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
    // Default-filled rows the exec has opened up. Expanding is not editing, so
    // this is tracked separately from the decision itself.
    const [expandedRows, setExpandedRows] = useState(() => new Set())
    // Part-master changes the exec has asked for, keyed by part id:
    // { [partId]: { kind: 'set' | 'clear', reason } }. Nothing is written until
    // the confirmation below is accepted, and then only by the closure RPC.
    const [partDefaults, setPartDefaults] = useState({})
    const [confirmingDefaults, setConfirmingDefaults] = useState(false)

    const updateDecision = (issuePartId, field, value) => {
        setDecisions(prev => ({
            ...prev,
            // Any hand edit means this row is no longer the part master's default,
            // for this job card only — nothing is written back to the part.
            [issuePartId]: { ...prev[issuePartId], [field]: value, fromDefault: false },
        }))
    }

    const expandRow = issuePartId => {
        setExpandedRows(prev => new Set(prev).add(issuePartId))
    }

    const toggleDefault = offer => {
        setPartDefaults(prev => {
            const next = { ...prev }
            if (isPicked(prev, offer)) delete next[offer.partId]
            else next[offer.partId] = { kind: offer.kind, reason: offer.reason }
            return next
        })
    }

    const defaultDirectives = collectDefaultDirectives(
        jobCard, decisions, partDefaults, existingScrapMap
    )

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
        // Any error from here on belongs on the modal behind this dialog.
        setConfirmingDefaults(false)

        const directiveByIssuePart = Object.fromEntries(
            defaultDirectives.map(directive => [directive.issuePartId, directive])
        )

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
                    entry.from_default     = d.fromDefault
                } else if (d.action === 'scrap' && isOutsource) {
                    entry.outsource_disposition = d.outsourceDisposition
                    if (d.outsourceDisposition === 'retained_by_vendor_with_credit') {
                        entry.outsource_credit_amount = parseFloat(d.outsourceCreditAmount)
                    }
                }
                // The part master change rides along with the decision it was made
                // on, so it commits inside the closure transaction — a client write
                // after the RPC returned could leave a default behind on a closure
                // that failed.
                const directive = directiveByIssuePart[issuePartId]
                if (directive?.kind === 'set')        entry.set_as_default = true
                else if (directive?.kind === 'clear') entry.clear_default  = true
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

            // Audit: part-master defaults set or cleared by this closure. The RPC
            // reports only real changes, so a directive that asked for the state
            // the part was already in leaves no row behind.
            for (const change of result.part_default_changes || []) {
                await logAuditEvent(change.part_id, 'parts', 'UPDATE', userProfile.id, {
                    oldData: {
                        default_exclude_from_scrap: change.old_exclude,
                        default_exclusion_reason:   change.old_reason,
                    },
                    newData: {
                        default_exclude_from_scrap: change.new_exclude,
                        default_exclusion_reason:   change.new_reason,
                        source_job_card_id:         jobCard.id,
                        source_job_card_number:     jobCard.job_card_number,
                    },
                    changedFields: ['default_exclude_from_scrap', 'default_exclusion_reason'],
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

    const confirmLabel = invoicePending ? 'Confirm and Close' : 'Confirm and Complete'

    return (
        <>
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

                                // A row still sitting on its part-master default collapses to one
                                // line — the point of the default is that it needs no attention.
                                // A permanently-scrapped part never collapses: its lock and the
                                // reason for it must stay visible.
                                const showAsDefault =
                                    d.fromDefault && !isPermanent && !expandedRows.has(ip.id)

                                const defaultOffer = defaultOfferFor(ip, d, isPermanent)

                                if (showAsDefault) {
                                    return (
                                        <div key={ip.id} className="rounded-lg bg-gray-50 border border-gray-200 px-3 py-2">
                                            <div className="flex items-center gap-2 flex-wrap">
                                                <p className="text-sm font-medium text-gray-800">
                                                    {ip.part?.name ?? 'Unknown part'} &times; {ip.quantity_used} {ip.part?.unit ?? ''}
                                                </p>
                                                <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-700">
                                                    Excluded — {exclusionReasonLabel(d.exclusionReason)}
                                                </span>
                                                <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-gray-200 text-gray-600">
                                                    Default
                                                </span>
                                                <button
                                                    type="button"
                                                    onClick={() => expandRow(ip.id)}
                                                    className="ml-auto text-xs font-medium text-blue-600 hover:text-blue-800"
                                                >
                                                    Change
                                                </button>
                                            </div>
                                            {isInStorage && (
                                                <p className="text-xs text-amber-600 mt-1">
                                                    Previously scrapped — previous entry will be replaced on submit.
                                                </p>
                                            )}
                                        </div>
                                    )
                                }

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

                                        {/* Teach the part master from here, rather than
                                            making a separate trip to the Parts Catalog. */}
                                        {defaultOffer && (
                                            <label className="flex items-start gap-2 cursor-pointer pt-2 border-t border-gray-200">
                                                <input
                                                    type="checkbox"
                                                    checked={isPicked(partDefaults, defaultOffer)}
                                                    onChange={() => toggleDefault(defaultOffer)}
                                                    className="mt-0.5 rounded border-gray-300 text-blue-600 focus:ring-blue-500 shrink-0"
                                                />
                                                <span className="text-sm text-gray-700">
                                                    {defaultOffer.kind === 'set'
                                                        ? <>Always exclude <span className="font-medium">{defaultOffer.partName}</span> from scrap in future</>
                                                        : <>Stop excluding <span className="font-medium">{defaultOffer.partName}</span> from scrap by default</>}
                                                </span>
                                            </label>
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
                        onClick={defaultDirectives.length > 0
                            ? () => setConfirmingDefaults(true)
                            : handleSubmit}
                        disabled={!isValid || closeJobCard.isPending}
                        className="px-4 py-2 text-sm font-medium text-white bg-green-600 rounded-lg hover:bg-green-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
                    >
                        {closeJobCard.isPending
                            ? (invoicePending ? 'Closing…' : 'Completing…')
                            : confirmLabel}
                    </button>
                </div>
            </div>
        </div>

        {/* A part default outlives this job card, so it is stated plainly and
            confirmed once for all of them. Cancelling here sends nothing and
            discards nothing — every decision and tick is still on the modal
            underneath. */}
        {confirmingDefaults && (
            <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[60] p-4">
                <div className="bg-white rounded-xl shadow-2xl w-full max-w-md flex flex-col max-h-[85vh]">
                    <div className="px-6 py-4 border-b border-gray-200 shrink-0">
                        <h2 className="text-base font-semibold text-gray-900">
                            Change part defaults?
                        </h2>
                        <p className="text-xs text-gray-500 mt-0.5">
                            This applies to all future job cards, for all users — not just this one.
                        </p>
                    </div>

                    <div className="overflow-y-auto flex-1 px-6 py-4">
                        <ul className="space-y-2">
                            {defaultDirectives.map(directive => (
                                <li key={directive.partId} className="text-sm text-gray-700">
                                    <span className="font-medium text-gray-900">{directive.partName}</span>
                                    {directive.kind === 'set'
                                        ? <> — excluded from scrap by default, reason {exclusionReasonLabel(directive.reason)}</>
                                        : <> — no longer excluded from scrap by default</>}
                                </li>
                            ))}
                        </ul>
                    </div>

                    <div className="flex justify-end gap-3 px-6 py-4 border-t border-gray-200 shrink-0">
                        <button
                            type="button"
                            onClick={() => setConfirmingDefaults(false)}
                            className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
                        >
                            Cancel
                        </button>
                        <button
                            type="button"
                            onClick={handleSubmit}
                            className="px-4 py-2 text-sm font-medium text-white bg-green-600 rounded-lg hover:bg-green-700 transition-colors"
                        >
                            {confirmLabel}
                        </button>
                    </div>
                </div>
            </div>
        )}
        </>
    )
}
