import { useState } from 'react'
import LedgerModal, { PrimaryButton, SecondaryButton } from './LedgerModal'
import { useReconcileSupplierBalance } from '../../hooks/useSupplierLedger'
import { RECONCILE_SOURCES } from '../../constants/supplierLedger'
import { balanceAsOf } from '../../utils/supplierLedger'
import { toPaise, paiseToInput } from '../../utils/settlement'
import { todayLocal, formatDate } from '../../utils/datetime'
import { fmtMoney } from '../outsource-invoices/format'

/**
 * Reconciles a supplier's balance, stock-audit style (MAIN-119): finance enters the
 * balance confirmed in Tally or the vendor's statement as of a date; the app's own
 * figure on that date is frozen and the difference posted as an adjustment line.
 * The figure shown here is from the statement; reconcile_supplier_balance recomputes
 * it when posting.
 */
export default function ReconcileModal({ supplier, lines, onClose }) {
    const today = todayLocal()
    const reconcile = useReconcileSupplierBalance()
    const [asOf, setAsOf] = useState(today)
    const [source, setSource] = useState('Vendor statement')
    const [confirmed, setConfirmed] = useState('')
    const [reason, setReason] = useState('')
    const [showErrors, setShowErrors] = useState(false)

    const system = Math.round(balanceAsOf(lines, asOf) * 100)
    // A supplier in credit is confirmed as a negative balance.
    const confirmedText = confirmed.trim()
    const negative = confirmedText.startsWith('-')
    const confirmedAbs = toPaise(negative ? confirmedText.slice(1) : confirmedText)
    const confirmedPaise = confirmedText === '' || isNaN(confirmedAbs) ? NaN : (negative ? -confirmedAbs : confirmedAbs)
    const difference = isNaN(confirmedPaise) ? null : confirmedPaise - system

    const errors = {}
    if (!asOf) errors.asOf = 'Required'
    else if (asOf > today) errors.asOf = 'Cannot be in the future'
    if (isNaN(confirmedPaise)) errors.confirmed = 'Enter an amount with at most two decimals'
    if (!reason.trim()) errors.reason = 'Required'
    const err = k => showErrors && errors[k] && <p className="text-xs text-red-600 mt-1">{errors[k]}</p>

    const submit = () => {
        if (Object.keys(errors).length > 0) {
            setShowErrors(true)
            return
        }
        reconcile.mutate({
            supplierId: supplier.id,
            asOf,
            confirmedAgainst: source,
            confirmedBalance: paiseToInput(confirmedPaise),
            reason: reason.trim(),
        }, { onSuccess: onClose })
    }

    const inputClass = 'w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500'

    return (
        <LedgerModal
            title="Reconcile balance"
            subtitle={supplier.entity_name}
            onClose={onClose}
            footer={<>
                <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
                <PrimaryButton onClick={submit} disabled={reconcile.isPending}>
                    {reconcile.isPending ? 'Saving…' : difference === 0 ? 'Record reconciliation' : 'Post adjustment'}
                </PrimaryButton>
            </>}
        >
            <p className="text-sm text-gray-600">
                Enter the balance you confirmed in Tally or the vendor's statement. The app counts everything
                entered up to the end of that day (up to now, for today), keeps its own figure, and posts the
                difference as an adjustment line. Posted one by mistake? Reverse it from the statement.
            </p>

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label htmlFor="rc-date" className="block text-xs font-medium text-gray-600 mb-1">Balance as of <span className="text-red-500">*</span></label>
                    <input id="rc-date" type="date" max={today} value={asOf} onChange={e => setAsOf(e.target.value)} className={inputClass} />
                    {err('asOf')}
                </div>
                <fieldset>
                    <legend className="block text-xs font-medium text-gray-600 mb-1">Confirmed against <span className="text-red-500">*</span></legend>
                    <div className="flex flex-wrap gap-1.5">
                        {RECONCILE_SOURCES.map(s => (
                            <button
                                key={s}
                                type="button"
                                aria-pressed={source === s}
                                onClick={() => setSource(s)}
                                className={`flex-1 text-sm px-2 py-2 rounded-lg border whitespace-nowrap ${source === s ? 'border-blue-600 bg-blue-50 text-blue-800 font-medium' : 'border-gray-300 text-gray-600 hover:bg-gray-50'}`}
                            >
                                {s}
                            </button>
                        ))}
                    </div>
                </fieldset>
            </div>

            <div className="bg-gray-50 border border-gray-200 rounded-lg p-3 grid grid-cols-2 gap-y-2 items-center text-sm">
                <span className="text-gray-500">App balance at the end of {formatDate(asOf)}</span>
                <span className="text-right font-semibold tabular-nums">{fmtMoney(paiseToInput(system))}</span>
                <label htmlFor="rc-confirmed" className="text-gray-700 font-medium">Confirmed balance (₹) <span className="text-red-500">*</span></label>
                <div>
                    <input id="rc-confirmed" inputMode="decimal" value={confirmed} onChange={e => setConfirmed(e.target.value)} className={`${inputClass} text-right tabular-nums`} />
                    {err('confirmed')}
                </div>
                <span className="text-gray-500 border-t border-gray-200 pt-2">Adjustment to post</span>
                <span className={`text-right font-bold tabular-nums border-t border-gray-200 pt-2 ${difference ? 'text-orange-800' : 'text-gray-700'}`}>
                    {difference == null ? '—' : difference === 0 ? 'None — balances agree'
                        : `${difference < 0 ? '−' : '+'} ${fmtMoney(paiseToInput(Math.abs(difference)))}`}
                </span>
            </div>

            <div>
                <label htmlFor="rc-reason" className="block text-xs font-medium text-gray-600 mb-1">Reason <span className="text-red-500">*</span></label>
                <textarea id="rc-reason" rows={3} value={reason} onChange={e => setReason(e.target.value)} className={inputClass} />
                {err('reason')}
            </div>
            <p className="text-xs text-gray-500">Recorded with your name and the time. Reconcile again whenever needed; nothing already entered is changed.</p>
            {reconcile.error && <p className="text-sm text-red-600">{reconcile.error.message}</p>}
        </LedgerModal>
    )
}
