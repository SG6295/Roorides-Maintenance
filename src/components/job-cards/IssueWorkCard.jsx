import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { format } from 'date-fns'
import { useUpdateIssue } from '../../hooks/useIssues'
import { useAddIssuePart, useDeleteIssuePart } from '../../hooks/useParts'

/**
 * IssueWorkCard - displays a single issue within a Job Card with labour, parts, and status controls
 *
 * Props:
 *   issue        - the issue object (with issue_parts and ticket nested)
 *   jobCardId    - string, used for cache invalidation
 *   jobCardStatus - string, e.g. 'In Progress' | 'Completed'
 *   isMechanic   - bool
 *   parts        - array of parts from useParts()
 *   userProfile  - current user profile object
 */
export default function IssueWorkCard({ issue, jobCardId, jobCardStatus, isMechanic, parts, userProfile }) {
    const updateIssue = useUpdateIssue()
    const addIssuePart = useAddIssuePart(jobCardId)
    const deleteIssuePart = useDeleteIssuePart(jobCardId)

    const [form, setForm] = useState({
        labourHours: issue.labour_hours != null ? String(issue.labour_hours) : '',
        showAddPart: false,
        selectedPartId: '',
        partQty: '',
    })
    const [labourSaved, setLabourSaved] = useState(false)

    // Re-sync labourHours when issue prop changes (e.g. after refetch)
    useEffect(() => {
        setForm(prev => ({
            ...prev,
            labourHours: issue.labour_hours != null ? String(issue.labour_hours) : '',
        }))
    }, [issue.labour_hours])

    const isPending = updateIssue.isPending || addIssuePart.isPending || deleteIssuePart.isPending

    const statusBadge = (status) => {
        if (status === 'Done') return 'bg-green-100 text-green-800'
        if (status === 'Blocked') return 'bg-orange-100 text-orange-800'
        return 'bg-gray-100 text-gray-600'
    }

    const handleSaveLabour = async () => {
        try {
            await updateIssue.mutateAsync({
                id: issue.id,
                updates: { labour_hours: parseFloat(form.labourHours) || null },
                userId: userProfile?.id,
                oldData: issue,
            })
            setLabourSaved(true)
            setTimeout(() => setLabourSaved(false), 2000)
        } catch (e) {
            alert('Failed to save labour hours: ' + e.message)
        }
    }

    const handleDeletePart = async (issuePartId) => {
        try {
            await deleteIssuePart.mutateAsync(issuePartId)
        } catch (e) {
            alert('Failed to remove part: ' + e.message)
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
            alert('Failed to add part: ' + e.message)
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

    const canEdit = isMechanic && jobCardStatus !== 'Completed'

    return (
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
            {/* Top row: ticket link + status badge */}
            <div className="flex items-start justify-between gap-2 mb-1">
                <Link
                    to={`/tickets/${issue.ticket_id}`}
                    className="text-xs font-medium text-blue-600 hover:underline"
                >
                    {issue.issue_number}
                </Link>
                <span className={`shrink-0 px-2 py-0.5 rounded-full text-xs font-medium ${statusBadge(issue.status)}`}>
                    {issue.status}
                </span>
            </div>

            {/* Description */}
            <p className="font-medium text-gray-900 text-sm mb-2">{issue.description}</p>

            {/* Meta row: category + SLA */}
            <div className="flex items-center gap-2 mb-3">
                <span className="text-xs px-2 py-0.5 bg-gray-100 rounded-full text-gray-600">
                    {issue.category}
                </span>
                {issue.sla_end_date && (
                    <span className="text-xs text-gray-500">
                        SLA: {format(new Date(issue.sla_end_date), 'MMM d')}
                    </span>
                )}
            </div>

            {/* Labour section */}
            <hr className="border-gray-200 mb-3" />
            <div className="mb-3">
                <p className="text-xs font-medium text-gray-600 uppercase mb-2">Labour Hours</p>
                {canEdit ? (
                    <div className="flex items-center gap-2">
                        <input
                            type="number"
                            min="0"
                            step="0.25"
                            value={form.labourHours}
                            onChange={e => setForm(prev => ({ ...prev, labourHours: e.target.value }))}
                            className="w-24 border rounded-lg px-3 py-2 text-sm border-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500"
                            placeholder="0"
                        />
                        <span className="text-sm text-gray-600">hrs</span>
                        <button
                            onClick={handleSaveLabour}
                            disabled={isPending}
                            className={`text-xs px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50 ${labourSaved ? 'bg-green-500 text-white' : 'bg-blue-600 text-white hover:bg-blue-700'}`}
                        >
                            {labourSaved ? 'Saved ✓' : 'Save'}
                        </button>
                    </div>
                ) : (
                    <p className="text-sm text-gray-900">
                        {issue.labour_hours != null ? `${issue.labour_hours} hrs` : <span className="text-gray-500 italic">Not recorded</span>}
                    </p>
                )}
            </div>

            {/* Parts Used section */}
            <hr className="border-gray-200 mb-3" />
            <div className="mb-3">
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
                ) : (
                    !form.showAddPart && (
                        <p className="text-xs text-gray-500 italic">No parts added</p>
                    )
                )}

                {/* Add part form */}
                {form.showAddPart && (
                    <div className="flex flex-col gap-2 mt-2">
                        <select
                            value={form.selectedPartId}
                            onChange={e => setForm(prev => ({ ...prev, selectedPartId: e.target.value }))}
                            className="w-full text-sm border border-gray-300 rounded-lg px-2 py-2 bg-white text-gray-900 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        >
                            <option value="">Select a part...</option>
                            {parts.map(part => (
                                <option key={part.id} value={part.id}>
                                    {part.name}{part.part_number ? ` (${part.part_number})` : ''} — {part.quantity_in_stock} {part.unit} in stock
                                </option>
                            ))}
                        </select>
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

            {/* Status Actions */}
            {canEdit && (
                <>
                    <hr className="border-gray-200 mb-3" />
                    <div className="flex flex-wrap gap-2">
                        {issue.status !== 'Open' && (
                            <button
                                onClick={() => handleStatusChange('Open')}
                                disabled={isPending}
                                className="text-sm px-3 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 disabled:opacity-50 transition-colors"
                            >
                                Revert to Open
                            </button>
                        )}
                        {issue.status !== 'Blocked' && (
                            <button
                                onClick={() => handleStatusChange('Blocked')}
                                disabled={isPending}
                                className="text-sm px-3 py-2 bg-orange-100 text-orange-700 rounded-lg hover:bg-orange-200 disabled:opacity-50 transition-colors"
                            >
                                Mark Blocked
                            </button>
                        )}
                        {issue.status !== 'Done' && (
                            <button
                                onClick={() => handleStatusChange('Done')}
                                disabled={isPending}
                                className="text-sm px-3 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
                            >
                                Mark Done
                            </button>
                        )}
                    </div>
                </>
            )}
        </div>
    )
}
