import { Fragment, useState, useMemo } from 'react'
import { formatDate } from '../../../utils/datetime'
import {
    ExclamationTriangleIcon,
    ChevronDownIcon,
    ChevronUpIcon,
} from '@heroicons/react/24/outline'
import CustomSelect from '../../shared/CustomSelect'
import {
    AUDIT_REASONS,
    useStockAuditMovements,
    useSetStockAuditReasons,
    useCompleteStockAudit,
} from '../../../hooks/useStockAudits'

const SOURCE_LABELS = {
    consumption: 'Used on job card',
    purchase: 'Purchase inwarded',
    transfer_in: 'Transferred in from',
    transfer_out: 'Transferred out to',
}

// A shortfall and a surplus are not explained by the same words.
function reasonsFor(variance) {
    if (variance > 0) return AUDIT_REASONS.filter(r => r.value === 'found' || r.value === 'other')
    return AUDIT_REASONS.filter(r => r.value !== 'found')
}

function fmt(n) {
    const v = Number(n ?? 0)
    return Number.isInteger(v) ? String(v) : v.toFixed(2)
}

function signed(n) {
    const v = Number(n ?? 0)
    return v > 0 ? `+${fmt(v)}` : fmt(v)
}

/**
 * The mismatches an uploaded count produced, and what to do about them.
 *
 * The "moved during audit" column is the point of this screen. A part whose final figure
 * will not equal the counted figure is not a bug — a job card consumed some while the
 * count was underway — but it looks exactly like one unless the movement is shown next
 * to it.
 */
export default function AuditReviewTable({ audit, items }) {
    const { data: movements = {} } = useStockAuditMovements(audit.id)
    const saveReasons = useSetStockAuditReasons()
    const completeAudit = useCompleteStockAudit()

    const [showAll, setShowAll] = useState(false)
    const [expanded, setExpanded] = useState(null)
    const [edits, setEdits] = useState({})
    const [error, setError] = useState(null)

    const mismatches = useMemo(() => items.filter(i => i.variance !== 0), [items])
    const rows = showAll ? items : mismatches

    // What the row shows: a local edit if there is one, otherwise what is saved.
    const valueFor = (item, field) =>
        edits[item.part_id]?.[field] ?? (field === 'reason' ? item.reason : item.reason_notes) ?? ''

    function setField(item, field, value) {
        setError(null)
        setEdits(prev => ({
            ...prev,
            [item.part_id]: {
                reason: prev[item.part_id]?.reason ?? item.reason ?? '',
                notes: prev[item.part_id]?.notes ?? item.reason_notes ?? '',
                [field]: value,
            },
        }))
    }

    const dirty = Object.keys(edits).length > 0

    const unexplained = mismatches.filter(i => {
        const reason = valueFor(i, 'reason')
        if (!reason) return true
        return reason === 'other' && !String(valueFor(i, 'notes')).trim()
    })

    const pendingItems = () =>
        Object.entries(edits).map(([part_id, v]) => ({
            part_id,
            reason: v.reason || null,
            notes: v.notes || null,
        }))

    async function persistReasons() {
        if (!dirty) return
        await saveReasons.mutateAsync({ auditId: audit.id, items: pendingItems() })
        setEdits({})
    }

    async function handleSave() {
        setError(null)
        try {
            await persistReasons()
        } catch (err) {
            setError(err.message)
        }
    }

    async function handleComplete() {
        setError(null)
        if (!window.confirm(
            'Completing this audit corrects stock at this workshop and cannot be undone. Continue?'
        )) return
        try {
            await persistReasons()
            await completeAudit.mutateAsync({ auditId: audit.id })
        } catch (err) {
            setError(err.message)
        }
    }

    const busy = saveReasons.isPending || completeAudit.isPending

    return (
        <div className="space-y-4">
            <div className="flex items-center justify-between flex-wrap gap-3">
                <div className="flex items-center gap-3 text-sm">
                    <span className="text-gray-700">
                        <span className="font-semibold">{mismatches.length}</span> mismatch{mismatches.length === 1 ? '' : 'es'}
                        {' '}of {items.length} counted
                    </span>
                    {unexplained.length > 0 && (
                        <span className="text-xs px-2 py-1 bg-yellow-100 text-yellow-700 rounded-full">
                            {unexplained.length} still need a reason
                        </span>
                    )}
                </div>
                <label className="flex items-center gap-2 text-sm text-gray-600">
                    <input
                        type="checkbox"
                        checked={showAll}
                        onChange={e => setShowAll(e.target.checked)}
                        className="rounded border-gray-300"
                    />
                    Show parts that matched
                </label>
            </div>

            {rows.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-500 text-sm">
                    Every counted part matched the system. Complete the audit to close it off.
                </div>
            ) : (
                // No overflow wrapper here on purpose: the reason dropdown is a popup, and
                // any overflow-hidden/auto ancestor clips it. Matches ConsumptionHistory.
                <div className="bg-white rounded-lg shadow-sm">
                    <div>
                        <table className="min-w-full divide-y divide-gray-100 text-sm">
                            <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                <tr>
                                    <th className="px-4 py-3 text-left">Part</th>
                                    <th className="px-4 py-3 text-right">On sheet</th>
                                    <th className="px-4 py-3 text-right">Counted</th>
                                    <th className="px-4 py-3 text-right">Difference</th>
                                    <th className="px-4 py-3 text-left">During audit</th>
                                    <th className="px-4 py-3 text-left w-44">Reason</th>
                                    <th className="px-4 py-3 text-left w-56">Note</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-50">
                                {rows.map(item => {
                                    const moved = movements[item.part_id] || []
                                    const netMoved = moved.reduce((s, m) => s + m.quantity, 0)
                                    const isOpen = expanded === item.part_id
                                    const reason = valueFor(item, 'reason')
                                    const needsNote = reason === 'other' && !String(valueFor(item, 'notes')).trim()

                                    return (
                                        <Fragment key={item.part_id}>
                                            <tr className={`align-top ${
                                                item.variance !== 0 && (!reason || needsNote)
                                                    ? 'bg-yellow-50/50'
                                                    : 'hover:bg-gray-50'
                                            }`}>
                                                <td className="px-4 py-3">
                                                    <div className="font-medium text-gray-900">{item.part_name_snapshot}</div>
                                                    <div className="text-xs text-gray-400">
                                                        {item.part_number_snapshot && (
                                                            <span className="font-mono">{item.part_number_snapshot} · </span>
                                                        )}
                                                        {item.unit_snapshot}
                                                        {item.was_found_row && (
                                                            <span className="ml-1 text-blue-600">found on shelf</span>
                                                        )}
                                                    </div>
                                                </td>
                                                <td className="px-4 py-3 text-right text-gray-500">{fmt(item.system_qty)}</td>
                                                <td className="px-4 py-3 text-right text-gray-900">{fmt(item.counted_qty)}</td>
                                                <td className={`px-4 py-3 text-right font-semibold ${
                                                    item.variance < 0 ? 'text-red-600'
                                                        : item.variance > 0 ? 'text-green-700' : 'text-gray-400'
                                                }`}>
                                                    {signed(item.variance)}
                                                </td>
                                                <td className="px-4 py-3">
                                                    {moved.length === 0 ? (
                                                        <span className="text-xs text-gray-400">—</span>
                                                    ) : (
                                                        <button
                                                            onClick={() => setExpanded(isOpen ? null : item.part_id)}
                                                            className="flex items-center gap-1 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-full px-2 py-1 hover:bg-amber-100"
                                                        >
                                                            <ExclamationTriangleIcon className="w-3 h-3" />
                                                            {signed(netMoved)} moved
                                                            {isOpen ? <ChevronUpIcon className="w-3 h-3" /> : <ChevronDownIcon className="w-3 h-3" />}
                                                        </button>
                                                    )}
                                                </td>
                                                <td className="px-4 py-3">
                                                    {item.variance === 0 ? (
                                                        <span className="text-xs text-gray-400">Matched</span>
                                                    ) : (
                                                        <CustomSelect
                                                            value={reason}
                                                            onChange={v => setField(item, 'reason', v)}
                                                            options={reasonsFor(item.variance)}
                                                            placeholder="Choose a reason…"
                                                            compact
                                                        />
                                                    )}
                                                </td>
                                                <td className="px-4 py-3">
                                                    {item.variance !== 0 && (
                                                        <input
                                                            type="text"
                                                            value={valueFor(item, 'notes')}
                                                            onChange={e => setField(item, 'notes', e.target.value)}
                                                            placeholder={reason === 'other' ? 'Required' : 'Optional'}
                                                            className={`w-full border rounded-lg px-2 py-1.5 text-sm focus:ring-2 focus:ring-blue-500 ${
                                                                needsNote ? 'border-yellow-400 bg-yellow-50' : ''
                                                            }`}
                                                        />
                                                    )}
                                                </td>
                                            </tr>

                                            {isOpen && (
                                                <tr className="bg-amber-50/40">
                                                    <td colSpan={7} className="px-4 py-3">
                                                        <p className="text-xs text-gray-600 mb-2">
                                                            Moved at this workshop after the count sheet was generated. The audit
                                                            applies its own difference of <strong>{signed(item.variance)}</strong> on
                                                            top of this, so these stay as they are.
                                                        </p>
                                                        <table className="text-xs w-full max-w-2xl">
                                                            <tbody className="divide-y divide-amber-100">
                                                                {moved.map((m, i) => (
                                                                    <tr key={i}>
                                                                        <td className="py-1 pr-4 text-gray-500 whitespace-nowrap">
                                                                            {m.occurred_at ? formatDate(m.occurred_at) : ''}
                                                                        </td>
                                                                        <td className="py-1 pr-4 text-gray-700">
                                                                            {SOURCE_LABELS[m.source] || m.source}
                                                                        </td>
                                                                        <td className="py-1 pr-4 text-gray-900 font-medium">
                                                                            {m.reference}
                                                                            {m.vehicle_number && (
                                                                                <span className="text-gray-500 font-normal"> · {m.vehicle_number}</span>
                                                                            )}
                                                                        </td>
                                                                        <td className={`py-1 text-right font-medium ${
                                                                            m.quantity < 0 ? 'text-red-600' : 'text-green-700'
                                                                        }`}>
                                                                            {signed(m.quantity)}
                                                                        </td>
                                                                    </tr>
                                                                ))}
                                                            </tbody>
                                                        </table>
                                                    </td>
                                                </tr>
                                            )}
                                        </Fragment>
                                    )
                                })}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}

            <p className="flex items-start gap-1.5 text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
                <ExclamationTriangleIcon className="w-4 h-4 flex-shrink-0 mt-px" />
                <span>
                    Completing the audit corrects stock and cannot be undone. To fix a wrong count
                    afterwards, run another audit.
                </span>
            </p>

            {error && <p className="text-sm text-red-600 bg-red-50 px-3 py-2 rounded-lg">{error}</p>}

            <div className="flex justify-end gap-2">
                <button
                    onClick={handleSave}
                    disabled={!dirty || busy}
                    className="px-4 py-2 border text-gray-600 text-sm rounded-lg hover:bg-gray-50 disabled:opacity-40"
                >
                    {saveReasons.isPending ? 'Saving…' : 'Save progress'}
                </button>
                <button
                    onClick={handleComplete}
                    disabled={unexplained.length > 0 || busy}
                    className="px-5 py-2 bg-blue-600 text-white text-sm rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                    {completeAudit.isPending ? 'Completing…' : 'Accept losses & complete'}
                </button>
            </div>
        </div>
    )
}
