import { useState } from 'react'
import { Link } from 'react-router-dom'
import { XMarkIcon, CalendarDaysIcon } from '@heroicons/react/24/outline'
import { formatAs, formatDate, todayLocal } from '../../utils/datetime'
import { useUpdateIssue } from '../../hooks/useIssues'
import { useAddIssuePart, useDeleteIssuePart, useCreatePart } from '../../hooks/useParts'
import { usePartUnits } from '../../hooks/useInventory'
import { useAddIssueLabour, useUpdateIssueLabour, useDeleteIssueLabour } from '../../hooks/useIssueLabour'
import { ScrapRPCError } from '../../hooks/useScrap'
import { logAuditEvent } from '../../utils/auditLogger'
import { issueLabourHours, formatHours, initials } from '../../utils/labour'
import { ROLE_LABELS } from '../../constants/userRoles'
import SearchableSelect from '../shared/SearchableSelect'

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

export default function IssueWorkCard({ issue, jobCardId, jobCardStatus, isMechanic, parts, technicians = [], userProfile, jobCardType }) {
    const updateIssue = useUpdateIssue()
    const addIssuePart = useAddIssuePart(jobCardId)
    const deleteIssuePart = useDeleteIssuePart(jobCardId)
    const createPart = useCreatePart()
    const { data: partUnits = [] } = usePartUnits()

    const isOutsource = jobCardType === 'Outsource'
    const isExec = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)

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

    const isPending = updateIssue.isPending || addIssuePart.isPending || deleteIssuePart.isPending

    const handleDeletePart = async (issuePartId) => {
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
                alert('Failed to remove part: ' + e.message)
            }
        }
    }

    const handleAddPart = async () => {
        if (!form.selectedPartId) {
            alert('Please select a part.')
            return
        }
        const qty = parseFloat(form.partQty)
        if (!qty || qty <= 0) {
            alert('Please enter a valid quantity greater than 0.')
            return
        }
        try {
            await addIssuePart.mutateAsync({
                issue_id: issue.id,
                part_id: form.selectedPartId,
                quantity_used: qty,
                added_by: userProfile?.id,
            })
            setForm(prev => ({ ...prev, showAddPart: false, selectedPartId: '', partQty: '' }))
        } catch (e) {
            // The database refuses to issue more than this workshop holds, and its
            // message already names the part, the quantity and the workshop.
            alert(e.message)
        }
    }

    const handlePartSelect = (val) => {
        if (val === CREATE_PART_SENTINEL) {
            setShowCreateForm(true)
            return
        }
        setForm(prev => ({ ...prev, selectedPartId: val }))
    }

    const handleCreatePart = async () => {
        if (!newPartName.trim()) { alert('Part name is required.'); return }
        if (!newPartUnit) { alert('Unit is required.'); return }
        const duplicate = parts.find(
            p => p.name.trim().toLowerCase() === newPartName.trim().toLowerCase()
        )
        if (duplicate) {
            alert('This part already exists — please select it from the dropdown.')
            return
        }
        try {
            const created = await createPart.mutateAsync({
                name: newPartName,
                unit: newPartUnit,
                part_number: newPartNumber || null,
            })
            setForm(prev => ({ ...prev, selectedPartId: created.id }))
            setShowCreateForm(false)
            setNewPartName('')
            setNewPartUnit('')
            setNewPartNumber('')
        } catch (e) {
            alert('Failed to create part: ' + e.message)
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
            alert('Failed to update status: ' + e.message)
        }
    }

    // The database stamps completed_on when the item reaches Done; this is the exec's correction.
    const handleCompletedOnChange = async (value) => {
        setEditingDate(false)
        if (!value || value === issue.completed_on) return
        if (value < '2020-01-01' || value > todayLocal()) {
            alert('Please pick a date between 2020 and today.')
            return
        }
        try {
            await updateIssue.mutateAsync({
                id: issue.id,
                updates: { completed_on: value },
                userId: userProfile?.id,
                oldData: issue,
            })
        } catch (e) {
            alert('Failed to change the completion date: ' + e.message)
        }
    }

    const canEdit = isMechanic && jobCardStatus === 'Open'
    // Labour is written by execs only (RLS: "Execs manage issue labour").
    const canEditLabour = isExec && jobCardStatus === 'Open'

    return (
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
            {/* Header: number, title, category, SLA, status, completion date */}
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1 px-4 py-3 border-b border-gray-100">
                <Link
                    to={`/tickets/${issue.ticket_id}`}
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
                <span className="ml-auto flex items-center gap-2">
                    <span className={`shrink-0 px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge(issue.status)}`}>
                        {issue.status}
                    </span>
                    {issue.status === 'Done' && (
                        editingDate ? (
                            // Saved on Enter or leaving the box, not on change: typing a year digit
                            // by digit passes through dates like 0002-10-29 on the way.
                            <input
                                type="date"
                                aria-label="Activity complete date"
                                defaultValue={issue.completed_on || ''}
                                max={todayLocal()}
                                autoFocus
                                onBlur={e => handleCompletedOnChange(e.target.dataset.cancelled ? null : e.target.value)}
                                onKeyDown={e => {
                                    if (e.key === 'Escape') e.currentTarget.dataset.cancelled = 'true'
                                    if (e.key === 'Enter' || e.key === 'Escape') e.currentTarget.blur()
                                }}
                                className="text-xs border border-gray-300 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                        ) : isExec ? (
                            <button
                                type="button"
                                onClick={() => setEditingDate(true)}
                                title="Change the activity complete date"
                                className="inline-flex items-center gap-1 text-xs text-gray-700 border border-gray-200 rounded-md px-2 py-1 hover:border-blue-300 hover:text-blue-700 transition-colors"
                            >
                                <CalendarDaysIcon className="w-3.5 h-3.5" />
                                Completed {formatDate(issue.completed_on, 'date not set')}
                            </button>
                        ) : (
                            <span className="inline-flex items-center gap-1 text-xs text-gray-600">
                                <CalendarDaysIcon className="w-3.5 h-3.5" />
                                Completed {formatDate(issue.completed_on, 'date not set')}
                            </span>
                        )
                    )}
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
                                        {canEdit && (
                                            <button
                                                onClick={() => handleDeletePart(ip.id)}
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
                                        onChange={e => setNewPartName(e.target.value)}
                                        placeholder="Part name *"
                                        className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                    />
                                    <div className="flex gap-2">
                                        <select
                                            value={newPartUnit}
                                            onChange={e => setNewPartUnit(e.target.value)}
                                            className="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 bg-white"
                                        >
                                            <option value="">Unit *</option>
                                            {partUnits.map(u => (
                                                <option key={u.id} value={u.name}>{u.name}</option>
                                            ))}
                                        </select>
                                        <input
                                            type="text"
                                            value={newPartNumber}
                                            onChange={e => setNewPartNumber(e.target.value)}
                                            placeholder="Part no. (optional)"
                                            className="flex-1 text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                        />
                                    </div>
                                    <div className="flex gap-2">
                                        <button
                                            onClick={handleCreatePart}
                                            disabled={createPart.isPending}
                                            className="text-sm px-3 py-1.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
                                        >
                                            {createPart.isPending ? 'Creating…' : 'Create & select'}
                                        </button>
                                        <button
                                            onClick={() => { setShowCreateForm(false); setNewPartName(''); setNewPartUnit(''); setNewPartNumber('') }}
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
                                    onChange={e => setForm(prev => ({ ...prev, partQty: e.target.value }))}
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
                        </div>
                    )}
                </div>
            </div>

            {/* Status Actions */}
            {canEdit && (
                <div className="flex flex-wrap gap-2 px-4 py-2 border-t border-gray-100 bg-gray-50">
                    {issue.status !== 'Open' && (
                        <button
                            onClick={() => handleStatusChange('Open')}
                            disabled={isPending}
                            className="text-xs px-3 py-1.5 bg-white border border-gray-200 text-gray-700 rounded-md hover:bg-gray-100 disabled:opacity-50 transition-colors"
                        >
                            Revert to Open
                        </button>
                    )}
                    {issue.status !== 'Blocked' && (
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
    const addLabour = useAddIssueLabour(jobCardId)
    const updateLabour = useUpdateIssueLabour(jobCardId)
    const deleteLabour = useDeleteIssueLabour(jobCardId)

    const [technicianId, setTechnicianId] = useState('')
    const [newHours, setNewHours] = useState('')

    const rows = issue.issue_labour || []
    const { hours: total, unattributed } = issueLabourHours(issue)
    const busy = addLabour.isPending || updateLabour.isPending || deleteLabour.isPending

    const available = technicians.filter(t => !rows.some(r => r.technician?.id === t.id))

    const handleAdd = async () => {
        if (!technicianId) { alert('Please pick a technician.'); return }
        const hours = parseHours(newHours)
        if (hours == null) { alert('Hours must be more than 0 and at most 24.'); return }
        try {
            await addLabour.mutateAsync({ issue_id: issue.id, technician_id: technicianId, hours })
            setTechnicianId('')
            setNewHours('')
        } catch (e) {
            alert('Failed to add labour: ' + e.message)
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
                                onChange={setTechnicianId}
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
                            onChange={e => setNewHours(e.target.value)}
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
            </div>
        </div>
    )
}

function LabourRow({ row, canEdit, busy, onSave, onRemove }) {
    const saved = formatHours(parseFloat(row.hours))
    const [value, setValue] = useState(saved)
    const [prevSaved, setPrevSaved] = useState(saved)

    // Follow the saved value when it changes underneath us (refetch after a save).
    if (saved !== prevSaved) {
        setPrevSaved(saved)
        setValue(saved)
    }

    const commit = async () => {
        if (value === saved) return
        const hours = parseHours(value)
        if (hours == null) {
            alert('Hours must be more than 0 and at most 24.')
            setValue(saved)
            return
        }
        try {
            await onSave(hours)
        } catch (e) {
            alert('Failed to save hours: ' + e.message)
            setValue(saved)
        }
    }

    const remove = async () => {
        try {
            await onRemove()
        } catch (e) {
            alert('Failed to remove labour: ' + e.message)
        }
    }

    const name = row.technician?.name || 'Unknown'
    const role = row.technician?.role

    return (
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
                        onChange={e => setValue(e.target.value)}
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
    )
}
