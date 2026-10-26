import { useOutsourceInvoiceHistory } from '../../hooks/useOutsourceInvoices'
import { fmtMoney, fmtDate, fmtDateTime } from './format'
import { foldStatusChanges } from './historyEntries'

const FIELD_LABELS = {
    maintenance_payment_status: 'Maintenance status',
    finance_payment_status:     'Finance status',
    finance_remark:             'Finance remark',
    paid_by:                    'Paid By',
    invoice_value:              'Invoice value',
    approved_amount:            'Approved amount',
    advance_amount:             'Advance',
    payby_date:                 'Pay-by date',
}

const MONEY_FIELDS = ['invoice_value', 'approved_amount', 'advance_amount']

function fmtValue(field, value) {
    if (value == null || value === '') return '—'
    if (MONEY_FIELDS.includes(field)) return fmtMoney(value)
    if (field === 'payby_date') return fmtDate(value)
    if (field === 'finance_remark') return `"${value}"`
    return value
}

function StatusChange({ change }) {
    return (
        <p className="text-xs text-gray-600">
            Finance status {change.old_data?.finance_payment_status ?? '—'} → {change.new_data?.finance_payment_status}
        </p>
    )
}

function Entry({ entry }) {
    const who = entry.performed_by_name || 'Someone'

    if (entry.source === 'created') {
        return (
            <>
                <p className="text-sm text-gray-900">Created by {who}</p>
                <p className="text-xs text-gray-600">
                    Maintenance status {entry.new_data?.maintenance_payment_status ?? '—'}
                </p>
            </>
        )
    }

    if (entry.source === 'payment') {
        const p = entry.new_data ?? {}
        const cancelled = entry.action === 'UPDATE'
        return (
            <>
                <p className="text-sm text-gray-900">
                    {who} {cancelled ? 'cancelled the payment of' : 'recorded a payment of'} {fmtMoney(p.amount_paid)}
                    {Number(p.tds_amount) > 0 && <> + TDS {fmtMoney(p.tds_amount)}</>}
                    {Number(p.round_off) > 0 && <> + round-off {fmtMoney(p.round_off)}</>}
                </p>
                <p className="text-xs text-gray-600">
                    {cancelled ? `Reason: ${p.cancel_reason}` : `${p.ledger} · ${p.payment_method}${p.utr ? ` · UTR ${p.utr}` : ''}`}
                </p>
                {entry.statusChange && <StatusChange change={entry.statusChange} />}
            </>
        )
    }

    if (entry.action === 'INSERT') {
        const fields = Object.keys(FIELD_LABELS).filter(f => entry.new_data?.[f] != null && entry.new_data[f] !== '')
        return (
            <>
                <p className="text-sm text-gray-900">{who} saved the invoice details</p>
                {fields.map(f => (
                    <p key={f} className="text-xs text-gray-600">{FIELD_LABELS[f]}: {fmtValue(f, entry.new_data[f])}</p>
                ))}
            </>
        )
    }

    return (
        <>
            <p className="text-sm text-gray-900">{who} changed</p>
            {(entry.changed_fields ?? []).map(f => (
                <p key={f} className="text-xs text-gray-600">
                    {FIELD_LABELS[f] ?? f}: {fmtValue(f, entry.old_data?.[f])} → {fmtValue(f, entry.new_data?.[f])}
                </p>
            ))}
        </>
    )
}

/**
 * Dated "who changed what" for one outsource invoice (MAIN-96), newest first.
 */
export default function InvoiceHistory({ invoiceId }) {
    const { data: entries = [], isLoading, error } = useOutsourceInvoiceHistory(invoiceId)

    if (isLoading) return <p className="text-sm text-gray-400">Loading history…</p>
    if (error) return <p className="text-sm text-red-600">Could not load history: {error.message}</p>
    if (entries.length === 0) return <p className="text-sm text-gray-400 italic">No history yet.</p>

    return (
        <ol className="space-y-3 border-l-2 border-gray-100 pl-4">
            {foldStatusChanges(entries).map((e, i) => (
                <li key={`${e.performed_at}-${e.source}-${e.action}-${i}`}>
                    <p className="text-xs text-gray-400">{fmtDateTime(e.performed_at)}</p>
                    <Entry entry={e} />
                </li>
            ))}
        </ol>
    )
}
