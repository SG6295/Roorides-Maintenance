import { Fragment, useState, useMemo } from 'react'
import { formatDate } from '../../../utils/datetime'
import {
    ExclamationTriangleIcon,
    ChevronDownIcon,
    ChevronUpIcon,
    PlusIcon,
    TrashIcon,
} from '@heroicons/react/24/outline'
import CustomSelect from '../../shared/CustomSelect'
import {
    AUDIT_REASONS,
    useStockAuditMovements,
    useSetStockAuditReasons,
    useCompleteStockAudit,
} from '../../../hooks/useStockAudits'
import {
    initialAuditLines,
    unallocatedQty,
    lineNeedsNote,
    isMismatchExplained,
    savableAuditLines,
} from '../../../utils/auditReasons'

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

    // What the row shows: local edits if there are any, otherwise what is saved.
    const linesFor = item => edits[item.part_id] ?? initialAuditLines(item)

    function setLines(item, lines) {
        setError(null)
        setEdits(prev => ({ ...prev, [item.part_id]: lines }))
    }

    function setLineField(item, index, field, value) {
        setLines(item, linesFor(item).map((l, i) => (i === index ? { ...l, [field]: value } : l)))
    }

    // A new line starts with whatever is left, so the common case needs no typing.
    function addLine(item) {
        const lines = linesFor(item)
        const left = Math.max(unallocatedQty(item.variance, lines), 0)
        setLines(item, [...lines, { quantity: left > 0 ? String(left) : '', reason: '', notes: '' }])
    }

    function removeLine(item, index) {
        setLines(item, linesFor(item).filter((_, i) => i !== index))
    }

    const dirty = Object.keys(edits).length > 0

    const unexplained = mismatches.filter(i => !isMismatchExplained(i.variance, linesFor(i)))

    const pendingItems = () =>
        Object.entries(edits).map(([part_id, lines]) => ({
            part_id,
            lines: savableAuditLines(lines),
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
                            {unexplained.length} still need reasons
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
                                    <th colSpan={2} className="px-4 py-3 text-left min-w-[28rem]">Qty, reason and comment</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-50">
                                {rows.map(item => {
                                    const moved = movements[item.part_id] || []
                                    const netMoved = moved.reduce((s, m) => s + m.quantity, 0)
                                    const isOpen = expanded === item.part_id
                                    const lines = linesFor(item)
                                    const left = unallocatedQty(item.variance, lines)

                                    return (
                                        <Fragment key={item.part_id}>
                                            <tr className={`align-top ${
                                                item.variance !== 0 && !isMismatchExplained(item.variance, lines)
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
                                                <td colSpan={2} className="px-4 py-3">
                                                    {item.variance === 0 ? (
                                                        <span className="text-xs text-gray-400">Matched</span>
                                                    ) : (
                                                        <div className="space-y-2">
                                                            {lines.map((line, i) => (
                                                                <div key={i}>
                                                                    <div className="grid grid-cols-[4.5rem_10rem_minmax(0,1fr)_1.25rem] gap-2 items-center">
                                                                        <input
                                                                            type="number"
                                                                            min="0"
                                                                            step="any"
                                                                            aria-label="Quantity"
                                                                            value={line.quantity}
                                                                            onChange={e => setLineField(item, i, 'quantity', e.target.value)}
                                                                            className="w-full border rounded-lg px-2 py-1.5 text-sm text-right focus:ring-2 focus:ring-blue-500"
                                                                        />
                                                                        <CustomSelect
                                                                            value={line.reason}
                                                                            onChange={v => setLineField(item, i, 'reason', v)}
                                                                            options={reasonsFor(item.variance)}
                                                                            placeholder="Choose a reason…"
                                                                            compact
                                                                        />
                                                                        <input
                                                                            type="text"
                                                                            aria-label="Comment"
                                                                            value={line.notes}
                                                                            onChange={e => setLineField(item, i, 'notes', e.target.value)}
                                                                            placeholder={line.reason === 'other' ? 'Required' : 'Optional'}
                                                                            className={`w-full border rounded-lg px-2 py-1.5 text-sm focus:ring-2 focus:ring-blue-500 ${
                                                                                lineNeedsNote(line) ? 'border-yellow-400 bg-yellow-50' : ''
                                                                            }`}
                                                                        />
                                                                        {lines.length > 1 ? (
                                                                            <button
                                                                                type="button"
                                                                                onClick={() => removeLine(item, i)}
                                                                                aria-label="Remove line"
                                                                                className="text-gray-400 hover:text-red-500"
                                                                            >
                                                                                <TrashIcon className="w-4 h-4" />
                                                                            </button>
                                                                        ) : <span />}
                                                                    </div>
                                                                    {line.reason === 'damaged' && (
                                                                        <p className="text-xs text-gray-400 mt-1">
                                                                            {item.part?.default_exclude_from_scrap
                                                                                ? 'Will not go to scrap — this part is set to skip it.'
                                                                                : 'Will go to scrap when the audit completes.'}
                                                                        </p>
                                                                    )}
                                                                </div>
                                                            ))}
                                                            <div className="flex items-center justify-between">
                                                                <button
                                                                    type="button"
                                                                    onClick={() => addLine(item)}
                                                                    className="flex items-center gap-1 text-xs text-blue-600 hover:text-blue-800"
                                                                >
                                                                    <PlusIcon className="w-3 h-3" />
                                                                    Add another reason
                                                                </button>
                                                                {left !== 0 && (
                                                                    <span className={`text-xs ${left < 0 ? 'text-red-600' : 'text-yellow-700'}`}>
                                                                        {left > 0
                                                                            ? `${fmt(left)} still to explain`
                                                                            : `${fmt(-left)} more than the difference`}
                                                                    </span>
                                                                )}
                                                            </div>
                                                        </div>
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
