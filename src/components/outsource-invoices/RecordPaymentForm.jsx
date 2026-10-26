import { useState } from 'react'
import CustomSelect from '../shared/CustomSelect'
import { useRecordInvoicePayment } from '../../hooks/useOutsourceInvoices'
import { todayLocal } from '../../utils/datetime'
import { toPaise, paiseToInput, roundOffOffer } from '../../utils/settlement'
import { LEDGER_OPTIONS, PAYMENT_METHODS, BANK_OPTIONS } from '../../constants/outsourceInvoices'
import { fmtPaise } from './format'

const inputClass =
    'w-full text-sm border rounded-lg px-3 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500'

/**
 * Records one payment against an outsource invoice (MAIN-95).
 *
 * The Paid value follows Balance − TDS until finance types into it, so a payment
 * that settles the invoice needs no arithmetic. Amounts are checked in paise; the
 * database makes the binding checks and its messages are shown as they come.
 */
export default function RecordPaymentForm({ invoiceId, balancePaise, onDone }) {
    const todayStr = todayLocal()
    const [tds, setTds] = useState('0')
    const [amount, setAmount] = useState('')
    const [amountTouched, setAmountTouched] = useState(false)
    const [paidOn, setPaidOn] = useState(todayStr)
    const [ledger, setLedger] = useState('')
    const [method, setMethod] = useState('')
    const [bank, setBank] = useState('')
    const [utr, setUtr] = useState('')
    const [writeOff, setWriteOff] = useState(false)
    const [error, setError] = useState(null)
    const record = useRecordInvoicePayment()

    const tdsPaise = toPaise(tds)
    const shownAmount = amountTouched
        ? amount
        : paiseToInput(Math.max(balancePaise - (Number.isNaN(tdsPaise) ? 0 : tdsPaise), 0))
    const amountPaise = toPaise(shownAmount)
    const isCash = method === 'Cash'
    const amountsValid = !Number.isNaN(amountPaise) && !Number.isNaN(tdsPaise)
    const offer = amountsValid ? roundOffOffer(balancePaise, amountPaise, tdsPaise) : 0
    const roundOffPaise = offer && writeOff ? offer : 0

    const submit = () => {
        setError(null)
        if (!amountsValid) return setError('Amounts must be numbers with at most two decimals.')
        if (amountPaise + tdsPaise <= 0) return setError('Enter a paid value or a TDS amount.')
        const over = amountPaise + tdsPaise + roundOffPaise - balancePaise
        if (over > 0) return setError(`This would overpay by ${fmtPaise(over)}; the balance is ${fmtPaise(Math.max(balancePaise, 0))}.`)
        if (!paidOn) return setError('Enter the date the payment was made.')
        if (paidOn > todayStr) return setError('The payment date cannot be in the future.')
        if (!ledger) return setError('Choose the ledger the payment was posted to.')
        if (!method) return setError('Choose the payment method.')
        if (!isCash && (!bank || !utr.trim())) return setError('Bank and UTR are required for every method except Cash.')

        record.mutate(
            {
                invoiceId,
                payment: {
                    amount_paid: paiseToInput(amountPaise),
                    tds_amount: paiseToInput(tdsPaise),
                    round_off: paiseToInput(roundOffPaise),
                    paid_on: paidOn,
                    ledger,
                    payment_method: method,
                    bank: isCash ? null : bank,
                    utr: isCash ? null : utr.trim(),
                },
            },
            { onSuccess: onDone, onError: err => setError(err.message) },
        )
    }

    return (
        <div className="space-y-3 rounded-lg border border-blue-100 bg-blue-50/40 p-4">
            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Paid value (₹)</label>
                    <input
                        type="text"
                        inputMode="decimal"
                        value={shownAmount}
                        onChange={e => { setAmountTouched(true); setAmount(e.target.value) }}
                        className={`${inputClass} border-gray-300`}
                    />
                </div>
                <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">TDS (₹)</label>
                    <input
                        type="text"
                        inputMode="decimal"
                        value={tds}
                        onChange={e => setTds(e.target.value)}
                        className={`${inputClass} border-gray-300`}
                    />
                </div>
            </div>

            {offer > 0 && (
                <label className="flex items-center gap-2 text-sm text-gray-700">
                    <input
                        type="checkbox"
                        checked={writeOff}
                        onChange={e => setWriteOff(e.target.checked)}
                        className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    Write off {fmtPaise(offer)} as round-off
                </label>
            )}

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Payment made on</label>
                    <input
                        type="date"
                        value={paidOn}
                        max={todayStr}
                        onChange={e => setPaidOn(e.target.value)}
                        className={`${inputClass} border-gray-300`}
                    />
                </div>
                <div>
                    <CustomSelect
                        label="Posted ledger"
                        value={ledger}
                        onChange={setLedger}
                        options={LEDGER_OPTIONS}
                        placeholder="Select…"
                    />
                </div>
            </div>

            <div className="grid grid-cols-2 gap-3">
                <div>
                    <CustomSelect
                        label="Payment method"
                        value={method}
                        onChange={setMethod}
                        options={PAYMENT_METHODS}
                        placeholder="Select…"
                    />
                </div>
                {!isCash && (
                    <div>
                        <CustomSelect
                            label="Bank"
                            value={bank}
                            onChange={setBank}
                            options={BANK_OPTIONS}
                            placeholder="Select…"
                        />
                    </div>
                )}
            </div>

            {!isCash && (
                <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">Transaction identifier (UTR)</label>
                    <input
                        type="text"
                        value={utr}
                        onChange={e => setUtr(e.target.value)}
                        className={`${inputClass} border-gray-300`}
                    />
                </div>
            )}

            {error && <p className="text-sm text-red-600">{error}</p>}

            <div className="flex justify-end gap-2">
                <button
                    type="button"
                    onClick={onDone}
                    className="px-4 py-2 text-sm text-gray-600 border border-gray-300 rounded-lg hover:bg-white"
                >
                    Cancel
                </button>
                <button
                    type="button"
                    onClick={submit}
                    disabled={record.isPending}
                    className="px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                    {record.isPending ? 'Saving…' : 'Record payment'}
                </button>
            </div>
        </div>
    )
}
