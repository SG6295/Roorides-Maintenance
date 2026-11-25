import { useState } from 'react'
import { Link } from 'react-router-dom'
import { XMarkIcon, CalendarDaysIcon } from '@heroicons/react/24/outline'
import { formatAs, formatDateTime } from '../../utils/datetime'
import { useUpdateIssue } from '../../hooks/useIssues'
import { useAddIssuePart, useDeleteIssuePart, useCreatePart, useAddOpeningStockPrice } from '../../hooks/useParts'
import { usePartUnits } from '../../hooks/useInventory'
import { useAddIssueLabour, useUpdateIssueLabour, useDeleteIssueLabour } from '../../hooks/useIssueLabour'
import { ScrapRPCError } from '../../hooks/useScrap'
import { logAuditEvent } from '../../utils/auditLogger'
import { issueLabourHours, formatHours, initials } from '../../utils/labour'
import { ROLE_LABELS } from '../../constants/userRoles'
import { findSameNamePart, isDuplicatePartNameError, duplicatePartMessage } from '../../utils/partName'
import SearchableSelect from '../shared/SearchableSelect'
import DuplicatePartNotice from '../inventory/DuplicatePartNotice'
import CustomSelect from '../shared/CustomSelect'
import SLAStatusBadge from '../shared/SLAStatusBadge'
import { useToast, useConfirm } from '../../hooks/useFeedback'
import { canSeeCosts, needsPriceError, transferQuoteError, rupees } from '../../utils/jobCardValue'
import { companyLabel, companyShortLabel } from '../../constants/vehicleCompanies'
import PartPriceModal from './PartPriceModal'
import TransferSpareModal from './TransferSpareModal'

/**
 * IssueWorkCard - displays a single issue within a Job Card with labour, parts, and status controls
 *
 * Props:
 *   issue        - the issue object (with issue_parts, issue_labour and ticket nested)
 *   jobCardId    - string, used for cache invalidation
 *   jobCardStatus - string, e.g. 'In Progress' | 'Completed'
 *   isMechanic   - bool
 *   parts        - array of parts from useParts()
 *   technicians  - active mechanics and electricians, from useTechnicians()
 *   userProfile  - current user profile object
 */
const CREATE_PART_SENTINEL = '__create_part__'

// <input type="datetime-local"> works in the viewer's zone, to the minute.
const LOCAL_MINUTE = "yyyy-MM-dd'T'HH:mm"

const statusBadge = (status) => {
    if (status === 'Done') return 'bg-green-100 text-green-800'
    if (status === 'Blocked') return 'bg-orange-100 text-orange-800'
    return 'bg-gray-100 text-gray-600'
}

// Hours must be over 0 and at most 24 — the same rule as issue_labour_hours_check.
const parseHours = (value) => {
    const h = parseFloat(value)
    return h > 0 && h <= 24 ? h : null
}

export default function IssueWorkCard({ issue, jobCardId, jobCardStatus, isMechanic, parts, technicians = [], userProfile, jobCardType, blocked = false }) {
    const toast = useToast()
    const confirm = useConfirm()
    const updateIssue = useUpdateIssue()
    const addIssuePart = useAddIssuePart(jobCardId)
    const deleteIssuePart = useDeleteIssuePart(jobCardId)
    const createPart = useCreatePart()
    const addOpeningPrice = useAddOpeningStockPrice()
    // MAIN-158: a spare refused because its stock has no price — the exec is asked for one.
    const [priceNeeded, setPriceNeeded] = useState(null)
    const [transferNeeded, setTransferNeeded] = useState(null)
    const showCosts = canSeeCosts(userProfile?.role)
    const { data: partUnits = [] } = usePartUnits()

    const isOutsource = jobCardType === 'Outsource'
    // MAIN-155: `blocked` = the vehicle is Unknown, so nothing here can change.
    const isExec = ['maintenance_exec', 'super_admin'].includes(userProfile?.role) && !blocked

    const [form, setForm] = useState({
        showAddPart: false,
        selectedPartId: '',
        partQty: '',
    })
    const [deleteError, setDeleteError] = useState(null)
    const [showCreateForm, setShowCreateForm] = useState(false)
    const [newPartName, setNewPartName] = useState('')
    const [newPartUnit, setNewPartUnit] = useState('')
    const [newPartNumber, setNewPartNumber] = useState('')
    const [editingDate, setEditingDate] = useState(false)
    // Form checks, shown next to their fields (MAIN-144).
    const [addPartError, setAddPartError] = useState(null)
    const [newPartError, setNewPartError] = useState(null)
    const [dateError, setDateError] = useState(null)

    const isPending = updateIssue.isPending || addIssuePart.isPending || deleteIssuePart.isPending

    const handleDeletePart = async (issuePart) => {
        const issuePartId = issuePart.id
        const t = issuePart.transfer
        if (t && !(await confirm({
            title: 'Remove transferred spare?',
            message: `${issuePart.part?.name ?? 'This spare'} came partly or wholly from the stock of ${companyLabel(t.from_company)}. `
                + `Removing it returns the stock to the company it came from and reverses the transfer`
                + `${t.amount != null ? ` of ${rupees(t.amount)}` : ''} in both company ledgers.`,
            confirmLabel: 'Remove and reverse',
        }))) return
        setDeleteError(null)
        try {
            const result = await deleteIssuePart.mutateAsync(issuePartId)
            for (const scrapId of result?.reversed_scrap_ids || []) {
                await logAuditEvent(scrapId, 'scrap_inventory', 'UPDATE', userProfile?.id, {
                    oldData:       { status: 'in_storage' },
                    newData:       { status: 'reversed' },
                    changedFields: ['status', 'updated_at', 'updated_by'],
                })
            }
        } catch (e) {
            if (e instanceof ScrapRPCError && e.errorCode === 'SCRAP_BLOCKING_DELETE') {
                setDeleteError({ partId: issuePartId, message: e.message })
            } else {
                toast.error('Failed to remove part: ' + e.message)
            }
        }
    }

    const handleAddPart = async () => {
        if (!form.selectedPartId) {
            setAddPartError('Please select a part.')
            return
        }
        const qty = parseFloat(form.partQty)
        if (!qty || qty <= 0) {
            setAddPartError('Please enter a valid quantity greater than 0.')
            return
        }
        setAddPartError(null)
        const spare = {
            issue_id: issue.id,
            part_id: form.selectedPartId,
            quantity_used: qty,
        }
        try {
            await addIssuePart.mutateAsync(spare)
            setForm(prev => ({ ...prev, showAddPart: false, selectedPartId: '', partQty: '' }))
        } catch (e) {
            // Part of it is only in the other company's stock: ask to confirm a transfer.
            const quote = transferQuoteError(e)
            if (quote) {
                setTransferNeeded({ quote, spare })
                return
            }
            const missing = needsPriceError(e)
            if (missing) {
                if (['maintenance_exec', 'super_admin'].includes(userProfile?.role)) {
                    addOpeningPrice.reset()
                    setPriceNeeded({ ...missing, spare })
                } else {
                    toast.error(`${e.message} Ask a maintenance exec to add this spare — they will be asked for its price.`)
                }
                return
            }
            // The database refuses to issue more than this workshop holds, and its
            // message already names the part, the quantity and the workshop.
            toast.error(e.message)
        }
    }

    const handlePriceConfirm = async ({ unitPrice, gstRate }) => {
        try {
            await addOpeningPrice.mutateAsync({ partId: priceNeeded.partId ?? priceNeeded.spare.part_id, unitPrice, gstRate })
        } catch {
            return // shown in the popup
        }
        const { spare } = priceNeeded
        setPriceNeeded(null)
        try {
            await addIssuePart.mutateAsync(spare)
            setForm(prev => ({ ...prev, showAddPart: false, selectedPartId: '', partQty: '' }))
            toast.success('Price saved and spare added.')
        } catch (e) {
            const quote = transferQuoteError(e)
            if (quote) {
                setTransferNeeded({ quote, spare })
                return
            }
            toast.error(`Price saved, but the spare was not added: ${e.message}`)
        }
    }

    const handleTransferConfirm = async () => {
        const { quote, spare } = transferNeeded
        try {
            const result = await addIssuePart.mutateAsync({ ...spare, confirmTransfer: { amount: quote.amount } })
            setTransferNeeded(null)
            setForm(prev => ({ ...prev, showAddPart: false, selectedPartId: '', partQty: '' }))
            toast.success(result?.transfer
                ? `Spare added. ${rupees(result.transfer.amount)} transferred from ${companyLabel(result.transfer.from_company)}.`
                : "Spare added from the vehicle's own company's stock — no transfer was needed after all.")
        } catch (e) {
            // The cost moved since it was shown: show the new figures to confirm again.
            const fresh = transferQuoteError(e)
            if (fresh) {
                setTransferNeeded({ quote: fresh, spare })
                return
            }
            setTransferNeeded(null)
            toast.error(e.message)
        }
    }

    const handlePartSelect = (val) => {
        if (val === CREATE_PART_SENTINEL) {
            setShowCreateForm(true)
            return
        }
        setAddPartError(null)
        setForm(prev => ({ ...prev, selectedPartId: val }))
    }

    // A name already in the catalog, ignoring capitals and extra spaces (MAIN-148).
    const sameNamePart = showCreateForm ? findSameNamePart(parts, newPartName) : null

    const closeCreateForm = () => {
        setShowCreateForm(false)
        setNewPartName('')
        setNewPartUnit('')
        setNewPartNumber('')
        setNewPartError(null)
    }

    const pickExistingPart = (part) => {
        setForm(prev => ({ ...prev, selectedPartId: part.id }))
        closeCreateForm()
    }

    const handleCreatePart = async () => {
        if (!newPartName.trim()) { setNewPartError('Part name is required.'); return }
        if (!newPartUnit) { setNewPartError('Unit is required.'); return }
        if (sameNamePart) return
        setNewPartError(null)
        try {
            const created = await createPart.mutateAsync({
                name: newPartName,
                unit: newPartUnit,
                part_number: newPartNumber || null,
            })
            pickExistingPart(created)
        } catch (e) {
            // Someone added the same name since the catalog loaded.
            if (isDuplicatePartNameError(e)) setNewPartError(duplicatePartMessage(null))
            else toast.error('Failed to create part: ' + e.message)
        }
    }

    const handleStatusChange = async (newStatus) => {
        try {
            await updateIssue.mutateAsync({
                id: issue.id,
                updates: { status: newStatus },
                userId: userProfile?.id,
                oldData: issue,
            })
        } catch (e) {
            toast.error('Failed to update status: ' + e.message)
        }
    }

    // The database stamps completed_at when the work item reaches Done; this is the exec's
    // correction. The database refuses a future time and logs the change (MAIN-135).
    const handleCompletedAtChange = async (value) => {
        setEditingDate(false)
        if (!value || value === formatAs(issue.completed_at, LOCAL_MINUTE, '')) return
        // A date-time string with no zone is read as the viewer's local time.
        const picked = new Date(value)
        if (isNaN(picked) || picked.getFullYear() < 2020 || picked > new Date()) {
            setDateError('Please pick a time between 2020 and now.')
            return
        }
        try {
            await updateIssue.mutateAsync({
                id: issue.id,
                updates: { completed_at: picked.toISOString() },
                userId: userProfile?.id,
                oldData: issue,
            })
        } catch (e) {
            toast.error('Failed to change the activity complete time: ' + e.message)
        }
    }

    // A rated issue can't leave Done (MAIN-135); the database refuses it too.
    const isRated = issue.status === 'Done' && !!issue.rating

    const canEdit = isMechanic && jobCardStatus === 'Open' && !blocked
    // Labour is written by execs only (RLS: "Execs manage issue labour").
    const canEditLabour = isExec && jobCardStatus === 'Open'

    return (
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
            {/* Header: number, title, category, SLA, status, completion date */}
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-4 py-3 border-b border-gray-100">
                <Link
                    to={`/tickets/${issue.ticket?.ticket_number}`}
                    className="text-xs font-medium text-blue-600 hover:underline"
                >
                    {issue.issue_number}
                </Link>
                <span className="font-semibold text-gray-900 text-sm">{issue.description}</span>
                <span className="text-xs px-2 py-0.5 bg-gray-100 rounded-md text-gray-600">
                    {issue.category}
                </span>
                {issue.sla_end_date && (
                    <span className="text-xs text-gray-500">
                        SLA: {formatAs(issue.sla_end_date, 'MMM d')}
                    </span>
                )}
                <SLAStatusBadge status={issue.sla_status} deadline={issue.sla_end_date} />
                <span className="ml-auto flex items-center gap-2">
                    <span className={`shrink-0 px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge(issue.status)}`}>
                        {issue.status}
                    </span>
                    {issue.status === 'Done' && (
                        editingDate ? (
                            // Saved on Enter or leaving the box, not on change: typing a year digit
                            // by digit passes through dates like 0002-10-29 on the way.
                            <input
                                type="datetime-local"
                                aria-label="Activity complete time"
                                defaultValue={formatAs(issue.completed_at, LOCAL_MINUTE, '')}
                                max={formatAs(new Date(), LOCAL_MINUTE)}
                                autoFocus
                                onBlur={e => handleCompletedAtChange(e.target.dataset.cancelled ? null : e.target.value)}
                                onKeyDown={e => {
                                    if (e.key === 'Escape') e.currentTarget.dataset.cancelled = 'true'
                                    if (e.key === 'Enter' || e.key === 'Escape') e.currentTarget.blur()
                                }}
                                className="text-xs border border-gray-300 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                        ) : isExec ? (
                            <button
                                type="button"
                                onClick={() => { setDateError(null); setEditingDate(true) }}
                                title="Change the activity complete time"
                                className="inline-flex items-center gap-1 text-xs text-gray-700 border border-gray-200 rounded-md px-2 py-1 hover:border-blue-300 hover:text-blue-700 transition-colors"
                            >
                                <CalendarDaysIcon className="w-3.5 h-3.5" />
                                Completed {formatDateTime(issue.completed_at, 'time not set')}
                            </button>
                        ) : (
                            <span className="inline-flex items-center gap-1 text-xs text-gray-600">
                                <CalendarDaysIcon className="w-3.5 h-3.5" />
                                Completed {formatDateTime(issue.completed_at, 'time not set')}
                            </span>
                        )
                    )}
                    {dateError && <span className="text-xs text-red-600">{dateError}</span>}
                </span>
            </div>

            {/* Body: labour beside parts (in-house); parts alone (outsource) */}
            <div className={`grid grid-cols-1 ${isOutsource ? '' : 'sm:grid-cols-2'}`}>
                {!isOutsource && (
                    <LabourSection
                        issue={issue}
                        jobCardId={jobCardId}
                        canEdit={canEditLabour}
                        technicians={technicians}
                    />
                )}

                {/* Parts Used section */}
                <div className="px-4 py-3">
                    <div className="flex items-center justify-between mb-2">
                        <p className="text-xs font-medium text-gray-600 uppercase">Parts Used</p>
                        {canEdit && (
                            <button
                                onClick={() => setForm(prev => ({ ...prev, showAddPart: !prev.showAddPart }))}
                                className="text-xs text-blue-600 hover:text-blue-800 transition-colors"
                            >
                                + Add Part
                            </button>
                        )}
                    </div>

                    {/* Existing parts list */}
                    {issue.issue_parts && issue.issue_parts.length > 0 ? (
                        <>
                            <div className="flex flex-wrap gap-1.5 mb-2">
                                {issue.issue_parts.map(ip => (
                                    <span key={ip.id} className="inline-flex items-center gap-1.5 text-sm text-gray-700 bg-gray-50 border border-gray-300 rounded-lg px-2 py-1">
                                        {ip.part?.name} &times; {ip.quantity_used} {ip.part?.unit}
                                        {ip.transfer && (
                                            <span
                                                className="text-[11px] font-medium text-amber-800 bg-amber-100 rounded-full px-1.5 py-0.5"
                                                title={`${ip.transfer.quantity} ${ip.part?.unit ?? ''} transferred from ${companyLabel(ip.transfer.from_company)}`}
                                            >
                                                Transferred from {companyShortLabel(ip.transfer.from_company)}
                                            </span>
                                        )}
                                        {showCosts && !isOutsource && (
                                            <span className="text-xs text-gray-500" title="First-in-first-out cost, incl. GST">
                                                · {ip.cost !== null && ip.cost !== undefined ? rupees(ip.cost) : 'no price'}
                                            </span>
                                        )}
                                        {canEdit && (
                                            <button
                                                onClick={() => handleDeletePart(ip)}
                                                disabled={isPending}
                                                className="text-gray-500 hover:text-red-500 transition-colors disabled:opacity-50 leading-none"
                                                title="Remove part"
                                            >
                                                &times;
                                            </button>
                                        )}
                                    </span>
                                ))}
                            </div>
                            {deleteError && (
                                <p className="text-xs text-red-600 mt-1">
                                    {deleteError.message}{' '}
                                    <Link to="/scrap" className="underline">View scrap</Link>
                                </p>
                            )}
                        </>
                    ) : (
                        !form.showAddPart && (
                            <p className="text-xs text-gray-500 italic">No parts added</p>
                        )
                    )}

                    {/* Add part form */}
                    {form.showAddPart && (
                        <div className="flex flex-col gap-2 mt-2">
                            <SearchableSelect
                                value={form.selectedPartId}
                                onChange={handlePartSelect}
                                options={parts.map(p => ({
                                    value: p.id,
                                    label: isOutsource
                                        ? `${p.name}${p.part_number ? ` (${p.part_number})` : ''}`
                                        : `${p.name}${p.part_number ? ` (${p.part_number})` : ''} — ${p.quantity_here ?? 0} ${p.unit} here`,
                                }))}
                                pinnedOption={isOutsource ? { value: CREATE_PART_SENTINEL, label: '+ Create new part' } : null}
                                placeholder="Select a part..."
                                showAllOnFocus={true}
                            />

                            {/* Inline create-part form — outsource only */}
                            {showCreateForm && isOutsource && (
                                <div className="rounded-lg border border-blue-200 bg-blue-50 p-3 space-y-2">
                                    <p className="text-xs font-semibold text-blue-700 uppercase tracking-wide">New part</p>
                                    <input
                                        type="text"
                                        value={newPartName}
                                        onChange={e => { setNewPartName(e.target.value); setNewPartError(null) }}
                                        placeholder="Part name *"
                                        className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                    />
                                    {sameNamePart && <DuplicatePartNotice part={sameNamePart} onUse={pickExistingPart} />}
                                    <div className="flex gap-2">
                                        <div className="flex-1 min-w-0">
                                            <CustomSelect
                                                value={newPartUnit}
                                                onChange={v => { setNewPartUnit(v); setNewPartError(null) }}
                                                options={partUnits.map(u => ({ value: u.name, label: u.name }))}
                                                placeholder="Unit *"
                                            />
                                        </div>
                                        <input
                                            type="text"
                                            value={newPartNumber}
                                            onChange={e => setNewPartNumber(e.target.value)}
                                            placeholder="Part no. (optional)"
                                            className="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                        />
                                    </div>
                                    {newPartError && <p className="text-xs text-red-600">{newPartError}</p>}
                                    <div className="flex gap-2">
                                        <button
                                            onClick={handleCreatePart}
                                            disabled={createPart.isPending || !!sameNamePart}
                                            className="text-sm px-3 py-1.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
                                        >
                                            {createPart.isPending ? 'Creating…' : 'Create & select'}
                                        </button>
                                        <button
                                            onClick={closeCreateForm}
                                            className="text-sm px-3 py-1.5 bg-white border border-gray-300 text-gray-600 rounded-lg hover:bg-gray-50 transition-colors"
                                        >
                                            Cancel
                                        </button>
                                    </div>
                                </div>
                            )}

                            <div className="flex items-center gap-2">
                                <input
                                    type="number"
                                    min="0.01"
                                    step="0.01"
                                    value={form.partQty}
                                    onChange={e => { setForm(prev => ({ ...prev, partQty: e.target.value })); setAddPartError(null) }}
                                    placeholder="Qty"
                                    className="w-20 text-sm border border-gray-300 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                />
                                <button
                                    onClick={handleAddPart}
                                    disabled={isPending}
                                    className="text-sm px-3 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
                                >
                                    {addIssuePart.isPending ? 'Adding...' : 'Add'}
                                </button>
                            </div>
                            {addPartError && <p className="text-xs text-red-600">{addPartError}</p>}
                        </div>
                    )}
                </div>
            </div>

            {/* Status Actions */}
            {canEdit && (
                <div className="flex flex-wrap gap-2 px-4 py-2 border-t border-gray-100 bg-gray-50">
                    {isRated && (
                        <span className="text-xs text-gray-500 self-center">
                            Rated by the supervisor, so it can't be reopened.
                        </span>
                    )}
                    {issue.status !== 'Open' && !isRated && (
                        <button
                            onClick={() => handleStatusChange('Open')}
                            disabled={isPending}
                            className="text-xs px-3 py-1.5 bg-white border border-gray-200 text-gray-700 rounded-md hover:bg-gray-100 disabled:opacity-50 transition-colors"
                        >
                            Revert to Open
                        </button>
                    )}
                    {issue.status !== 'Blocked' && !isRated && (
                        <button
                            onClick={() => handleStatusChange('Blocked')}
                            disabled={isPending}
                            className="text-xs px-3 py-1.5 bg-orange-50 border border-orange-200 text-orange-800 rounded-md hover:bg-orange-100 disabled:opacity-50 transition-colors"
                        >
                            Mark Blocked
                        </button>
                    )}
                    {issue.status !== 'Done' && (
                        <button
                            onClick={() => handleStatusChange('Done')}
                            disabled={isPending}
                            className="text-xs px-3 py-1.5 bg-green-600 text-white rounded-md hover:bg-green-700 disabled:opacity-50 transition-colors"
                        >
                            Mark Done
                        </button>
                    )}
                </div>
            )}

            {transferNeeded && (
                <TransferSpareModal
                    quote={transferNeeded.quote}
                    onConfirm={handleTransferConfirm}
                    onCancel={() => setTransferNeeded(null)}
                    isSaving={addIssuePart.isPending}
                />
            )}

            {priceNeeded && (
                <PartPriceModal
                    part={priceNeeded}
                    onConfirm={handlePriceConfirm}
                    onCancel={() => setPriceNeeded(null)}
                    isSaving={addOpeningPrice.isPending || addIssuePart.isPending}
                    error={addOpeningPrice.error}
                />
            )}
        </div>
    )
}

const AVATAR_COLORS = {
    mechanic: 'bg-blue-100 text-blue-800',
    electrician: 'bg-amber-100 text-amber-800',
}

/**
 * Who worked on the item and for how long (MAIN-116). Each change saves on its own —
 * adding a person, editing hours (Enter or leaving the box), removing a person.
 */
function LabourSection({ issue, jobCardId, canEdit, technicians }) {
    const toast = useToast()
    const addLabour = useAddIssueLabour(jobCardId)
    const updateLabour = useUpdateIssueLabour(jobCardId)
    const deleteLabour = useDeleteIssueLabour(jobCardId)

    const [technicianId, setTechnicianId] = useState('')
    const [newHours, setNewHours] = useState('')
    const [addError, setAddError] = useState(null)

    const rows = issue.issue_labour || []
    const { hours: total, unattributed } = issueLabourHours(issue)
    const busy = addLabour.isPending || updateLabour.isPending || deleteLabour.isPending

    const available = technicians.filter(t => !rows.some(r => r.technician?.id === t.id))

    const handleAdd = async () => {
        if (!technicianId) { setAddError('Please pick a technician.'); return }
        const hours = parseHours(newHours)
        if (hours == null) { setAddError('Hours must be more than 0 and at most 24.'); return }
        setAddError(null)
        try {
            await addLabour.mutateAsync({ issue_id: issue.id, technician_id: technicianId, hours })
            setTechnicianId('')
            setNewHours('')
        } catch (e) {
            toast.error('Failed to add labour: ' + e.message)
        }
    }

    return (
        <div className="px-4 py-3 border-b border-gray-100 sm:border-b-0 sm:border-r">
            <div className="flex items-center justify-between mb-2">
                <p className="text-xs font-medium text-gray-600 uppercase">Labour</p>
                {total > 0 && <span className="text-xs text-gray-700">{formatHours(total)} hrs</span>}
            </div>

            <div className="space-y-2">
                {rows.map(row => (
                    <LabourRow
                        key={row.id}
                        row={row}
                        canEdit={canEdit}
                        busy={busy}
                        onSave={hours => updateLabour.mutateAsync({ id: row.id, hours })}
                        onRemove={() => deleteLabour.mutateAsync(row.id)}
                    />
                ))}

                {unattributed > 0 && (
                    <div className="flex items-center gap-2.5">
                        <span className="w-7 h-7 shrink-0 rounded-full bg-gray-100 text-gray-500 text-xs flex items-center justify-center">?</span>
                        <div className="flex-1 min-w-0">
                            <p className="text-sm text-gray-900">Unattributed</p>
                            <p className="text-xs text-gray-500">Logged before per-person tracking</p>
                        </div>
                        <span className="text-sm text-gray-900">{formatHours(unattributed)} h</span>
                    </div>
                )}

                {rows.length === 0 && unattributed === 0 && !canEdit && (
                    <p className="text-xs text-gray-500 italic">Not recorded</p>
                )}

                {canEdit && (
                    <div className="flex items-center gap-2 pt-1">
                        <div className="flex-1 min-w-0">
                            <SearchableSelect
                                value={technicianId}
                                onChange={v => { setTechnicianId(v); setAddError(null) }}
                                options={available.map(t => ({ value: t.id, label: `${t.name} · ${ROLE_LABELS[t.role] || t.role}` }))}
                                placeholder="+ Technician"
                                showAllOnFocus={true}
                            />
                        </div>
                        <input
                            type="number"
                            min="0.25"
                            max="24"
                            step="0.25"
                            value={newHours}
                            onChange={e => { setNewHours(e.target.value); setAddError(null) }}
                            onKeyDown={e => { if (e.key === 'Enter') handleAdd() }}
                            placeholder="hrs"
                            aria-label="Hours"
                            className="w-16 text-sm border border-gray-300 rounded-lg px-2 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                        <button
                            onClick={handleAdd}
                            disabled={busy}
                            className="text-sm px-3 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
                        >
                            {addLabour.isPending ? 'Adding…' : 'Add'}
                        </button>
                    </div>
                )}
                {addError && <p className="text-xs text-red-600">{addError}</p>}
            </div>
        </div>
    )
}

function LabourRow({ row, canEdit, busy, onSave, onRemove }) {
    const toast = useToast()
    const saved = formatHours(parseFloat(row.hours))
    const [value, setValue] = useState(saved)
    const [prevSaved, setPrevSaved] = useState(saved)
    const [hoursError, setHoursError] = useState(null)

    // Follow the saved value when it changes underneath us (refetch after a save).
    if (saved !== prevSaved) {
        setPrevSaved(saved)
        setValue(saved)
    }

    const commit = async () => {
        if (value === saved) return
        const hours = parseHours(value)
        if (hours == null) {
            setHoursError('Hours must be more than 0 and at most 24.')
            setValue(saved)
            return
        }
        setHoursError(null)
        try {
            await onSave(hours)
        } catch (e) {
            toast.error('Failed to save hours: ' + e.message)
            setValue(saved)
        }
    }

    const remove = async () => {
        try {
            await onRemove()
        } catch (e) {
            toast.error('Failed to remove labour: ' + e.message)
        }
    }

    const name = row.technician?.name || 'Unknown'
    const role = row.technician?.role

    return (
        <div>
            <div className="flex items-center gap-2.5">
                <span className={`w-7 h-7 shrink-0 rounded-full text-[11px] font-semibold flex items-center justify-center ${AVATAR_COLORS[role] || 'bg-gray-100 text-gray-700'}`}>
                    {initials(name)}
                </span>
                <div className="flex-1 min-w-0">
                    <p className="text-sm text-gray-900 truncate">{name}</p>
                    <p className="text-xs text-gray-500">{ROLE_LABELS[role] || role}</p>
                </div>
                {canEdit ? (
                    <>
                        <input
                            type="number"
                            min="0.25"
                            max="24"
                            step="0.25"
                            value={value}
                            onChange={e => { setValue(e.target.value); setHoursError(null) }}
                            onBlur={commit}
                            onKeyDown={e => {
                                if (e.key === 'Enter') e.currentTarget.blur()
                                if (e.key === 'Escape') setValue(saved)
                            }}
                            aria-label={`Hours for ${name}`}
                            className="w-16 text-sm text-right border border-gray-300 rounded-lg px-2 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                        <span className="text-xs text-gray-500">h</span>
                        <button
                            type="button"
                            onClick={remove}
                            disabled={busy}
                            aria-label={`Remove ${name}`}
                            title="Remove"
                            className="p-1.5 text-gray-400 hover:text-red-500 rounded-md disabled:opacity-50 transition-colors"
                        >
                            <XMarkIcon className="w-4 h-4" />
                        </button>
                    </>
                ) : (
                    <span className="text-sm text-gray-900">{saved} h</span>
                )}
            </div>
            {hoursError && <p className="text-xs text-red-600 mt-1 text-right">{hoursError}</p>}
        </div>
    )
}
