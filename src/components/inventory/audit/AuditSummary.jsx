import { formatDate } from '../../../utils/datetime'
import * as XLSX from 'xlsx'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'
import { AUDIT_REASON_LABELS, auditRef, useStockAuditItems } from '../../../hooks/useStockAudits'
import { TicketListSkeleton } from '../../shared/LoadingSkeleton'

const rupees = n =>
    `₹${Math.abs(Number(n ?? 0)).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

const fmt = n => {
    const v = Number(n ?? 0)
    return Number.isInteger(v) ? String(v) : v.toFixed(2)
}

const signed = n => (Number(n ?? 0) > 0 ? `+${fmt(n)}` : fmt(n))

function Stat({ label, value, hint, tone = 'text-gray-900' }) {
    return (
        <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="text-xs text-gray-500">{label}</div>
            <div className={`text-xl font-semibold mt-1 ${tone}`}>{value}</div>
            {hint && <div className="text-xs text-gray-400 mt-0.5">{hint}</div>}
        </div>
    )
}

/**
 * What a completed audit found. Read-only by definition — the audit is closed and the
 * stock correction has already been posted.
 */
export default function AuditSummary({ audit }) {
    const { data: items = [], isLoading } = useStockAuditItems(audit.id)

    const variances = items.filter(i => Number(i.variance) !== 0)
    const shortfalls = variances.filter(i => Number(i.variance) < 0)
    const surpluses = variances.filter(i => Number(i.variance) > 0)

    function handleExport() {
        if (items.length === 0) return
        const rows = items.map(i => ({
            'Part Name': i.part_name_snapshot,
            'Part Number': i.part_number_snapshot ?? '',
            'Unit': i.unit_snapshot ?? '',
            'On Sheet': Number(i.system_qty),
            'Counted': Number(i.counted_qty ?? 0),
            'Difference': Number(i.variance ?? 0),
            'Moved During Audit': Number(i.moved_during_audit ?? 0),
            'Stock After': Number(i.final_qty ?? 0),
            'Reason': i.reason ? AUDIT_REASON_LABELS[i.reason] ?? i.reason : '',
            'Note': i.reason_notes ?? '',
            'Unit Value': i.unit_value_snapshot === null ? '' : Number(i.unit_value_snapshot),
            'Value': i.variance_value === null ? '' : Number(i.variance_value),
            'Found On Shelf': i.was_found_row ? 'Yes' : '',
        }))
        const ws = XLSX.utils.json_to_sheet(rows)
        const wb = XLSX.utils.book_new()
        XLSX.utils.book_append_sheet(wb, ws, 'Stock Audit')
        const slug = (audit.location?.name || 'workshop').toLowerCase().replace(/[^a-z0-9]+/g, '_')
        const date = audit.completed_at ? audit.completed_at.slice(0, 10) : audit.started_at.slice(0, 10)
        XLSX.writeFile(wb, `${auditRef(audit)}_stock_audit_${slug}_${date}.xlsx`)
    }

    if (isLoading) return <TicketListSkeleton />

    return (
        <div className="space-y-4">
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Stat label="Parts counted" value={audit.total_parts} />
                <Stat
                    label="Mismatches"
                    value={audit.variance_parts}
                    hint={`${shortfalls.length} short · ${surpluses.length} extra`}
                />
                <Stat
                    label="Net units"
                    value={signed(audit.net_units)}
                    tone={Number(audit.net_units) < 0 ? 'text-red-600' : Number(audit.net_units) > 0 ? 'text-green-700' : 'text-gray-900'}
                />
                <Stat
                    label={Number(audit.net_value) < 0 ? 'Value written off' : 'Value adjusted'}
                    value={rupees(audit.net_value)}
                    tone={Number(audit.net_value) < 0 ? 'text-red-600' : 'text-gray-900'}
                    hint={audit.unvalued_parts > 0
                        ? `${audit.unvalued_parts} part${audit.unvalued_parts === 1 ? '' : 's'} never purchased — not valued`
                        : undefined}
                />
            </div>

            <div className="bg-white rounded-lg shadow-sm p-4 text-sm text-gray-600 flex flex-wrap gap-x-8 gap-y-1">
                <span>Started {formatDate(audit.started_at)} by {audit.started_by_name || '—'}</span>
                {audit.counts_uploaded_at && (
                    <span>Counted {formatDate(audit.counts_uploaded_at)} by {audit.counts_uploaded_by_name || '—'}</span>
                )}
                {audit.completed_at && (
                    <span>Completed {formatDate(audit.completed_at)} by {audit.completed_by_name || '—'}</span>
                )}
                {audit.notes && <span className="text-gray-500">“{audit.notes}”</span>}
            </div>

            <div className="flex justify-end">
                <button
                    onClick={handleExport}
                    disabled={items.length === 0}
                    className="flex items-center gap-2 px-3 py-1.5 text-sm border rounded-lg bg-white text-gray-700 hover:bg-gray-50 disabled:opacity-40 shadow-sm"
                >
                    <ArrowDownTrayIcon className="w-4 h-4" />
                    Export to Excel
                </button>
            </div>

            {variances.length === 0 ? (
                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                    Every counted part matched the system.
                </div>
            ) : (
                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                    <div className="overflow-x-auto">
                        <table className="min-w-full divide-y divide-gray-100 text-sm">
                            <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                <tr>
                                    <th className="px-4 py-3 text-left">Part</th>
                                    <th className="px-4 py-3 text-right">On sheet</th>
                                    <th className="px-4 py-3 text-right">Counted</th>
                                    <th className="px-4 py-3 text-right">Difference</th>
                                    <th className="px-4 py-3 text-right">Moved</th>
                                    <th className="px-4 py-3 text-right">Stock after</th>
                                    <th className="px-4 py-3 text-right">Value</th>
                                    <th className="px-4 py-3 text-left">Reason</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-50">
                                {variances.map(i => (
                                    <tr key={i.id} className="hover:bg-gray-50">
                                        <td className="px-4 py-3">
                                            <div className="font-medium text-gray-900">{i.part_name_snapshot}</div>
                                            <div className="text-xs text-gray-400">
                                                {i.part_number_snapshot && (
                                                    <span className="font-mono">{i.part_number_snapshot} · </span>
                                                )}
                                                {i.unit_snapshot}
                                                {i.was_found_row && <span className="ml-1 text-blue-600">found on shelf</span>}
                                            </div>
                                        </td>
                                        <td className="px-4 py-3 text-right text-gray-500">{fmt(i.system_qty)}</td>
                                        <td className="px-4 py-3 text-right text-gray-900">{fmt(i.counted_qty)}</td>
                                        <td className={`px-4 py-3 text-right font-semibold ${
                                            i.variance < 0 ? 'text-red-600' : 'text-green-700'
                                        }`}>
                                            {signed(i.variance)}
                                        </td>
                                        <td className="px-4 py-3 text-right text-gray-500">
                                            {Number(i.moved_during_audit ?? 0) === 0 ? '—' : signed(i.moved_during_audit)}
                                        </td>
                                        <td className="px-4 py-3 text-right text-gray-900">{fmt(i.final_qty)}</td>
                                        <td className="px-4 py-3 text-right text-gray-600">
                                            {i.variance_value === null ? (
                                                <span className="text-xs text-gray-400">not valued</span>
                                            ) : (
                                                <span className={Number(i.variance_value) < 0 ? 'text-red-600' : ''}>
                                                    {rupees(i.variance_value)}
                                                </span>
                                            )}
                                        </td>
                                        <td className="px-4 py-3">
                                            <div className="text-gray-700">
                                                {i.reason ? AUDIT_REASON_LABELS[i.reason] ?? i.reason : '—'}
                                            </div>
                                            {i.reason_notes && (
                                                <div className="text-xs text-gray-400">{i.reason_notes}</div>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                        {variances.length} mismatch{variances.length === 1 ? '' : 'es'} of {items.length} counted
                    </div>
                </div>
            )}
        </div>
    )
}
