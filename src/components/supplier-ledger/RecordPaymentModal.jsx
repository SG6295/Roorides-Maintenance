import { useState } from 'react'
import CustomSelect from '../shared/CustomSelect'
import LedgerModal, { PrimaryButton, SecondaryButton } from './LedgerModal'
import { PAYMENT_METHODS, BANK_OPTIONS } from '../../constants/outsourceInvoices'
import { toPaise, paiseToInput } from '../../utils/settlement'
import { todayLocal } from '../../utils/datetime'
import { fmtMoney } from '../outsource-invoices/format'

/**
 * Records money going out (MAIN-119): a Bill accounted payment to a supplier (with TDS),
 * or a repayment to a person who paid a supplier upfront (no TDS). Shows the balance
 * before and after. The database function behind `onSubmit` makes the binding checks.
 *
 * onSubmit({ amount, tds, paid_on, payment_method, bank, utr }) — amounts as two-decimal
 * strings; `mutation` is the hook's result, for its pending state and error.
 */
export default function RecordPaymentModal({ title, subtitle, balance, withTds = false, mutation, onSubmit, onClose }) {
    const today = todayLocal()
    const [form, setForm] = useState({ amount: '', tds: '', paidOn: today, method: 'NEFT', bank: '', utr: '' })
    const [showErrors, setShowErrors] = useState(false)
    const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

    const amount = toPaise(form.amount)
    const tds = withTds ? toPaise(form.tds) : 0
    const isCash = form.method === 'Cash'
    // Display only: a numeric(12,2) from the database is exact in paise once rounded.
    const balancePaise = Math.round(Number(balance ?? 0) * 100)
    const after = !isNaN(amount) && !isNaN(tds) ? balancePaise - amount - tds : balancePaise

    const errors = {}
    if (isNaN(amount)) errors.amount = 'Enter an amount with at most two decimals'
    if (isNaN(tds)) errors.tds = 'Enter an amount with at most two decimals'
    if (!isNaN(amount) && !isNaN(tds) && amount + tds <= 0) errors.amount = withTds ? 'Enter a paid value or TDS' : 'Enter the amount'
    if (!form.paidOn) errors.paidOn = 'Required'
    else if (form.paidOn > today) errors.paidOn = 'Cannot be in the future'
    if (!isCash && !form.bank) errors.bank = 'Required'
    if (!isCash && !form.utr.trim()) errors.utr = 'Required'
    const err = k => showErrors && errors[k] && <p className="text-xs text-red-600 mt-1">{errors[k]}</p>

    const submit = () => {
        if (Object.keys(errors).length > 0) {
            setShowErrors(true)
            return
        }
        onSubmit({
            amount: paiseToInput(amount),
            tds: paiseToInput(tds),
            paid_on: form.paidOn,
            payment_method: form.method,
            bank: isCash ? null : form.bank,
            utr: isCash ? null : form.utr.trim(),
        })
    }

    const inputClass = 'w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500'
    const label = (text, htmlFor, required = true) => (
        <label htmlFor={htmlFor} className="block text-xs font-medium text-gray-600 mb-1">
            {text} {required && <span className="text-red-500">*</span>}
        </label>
    )

    return (
        <LedgerModal
            title={title}
            subtitle={`${subtitle} · balance ${fmtMoney(balance)}`}
            onClose={onClose}
            footer={<>
                <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
                <PrimaryButton onClick={submit} disabled={mutation.isPending}>
                    {mutation.isPending ? 'Saving…' : title}
                </PrimaryButton>
            </>}
        >
            <div className="grid grid-cols-2 gap-3">
                <div>
                    {label(withTds ? 'Paid value (₹)' : 'Amount (₹)', 'pm-amount')}
                    <input id="pm-amount" inputMode="decimal" value={form.amount} onChange={e => set('amount', e.target.value)} className={inputClass} />
                    {err('amount')}
                </div>
                {withTds && (
                    <div>
                        {label('TDS (₹)', 'pm-tds', false)}
                        <input id="pm-tds" inputMode="decimal" value={form.tds} onChange={e => set('tds', e.target.value)} className={inputClass} />
                        {err('tds')}
                    </div>
                )}
                <div>
                    {label('Date paid', 'pm-date')}
                    <input id="pm-date" type="date" max={today} value={form.paidOn} onChange={e => set('paidOn', e.target.value)} className={inputClass} />
                    {err('paidOn')}
                </div>
                <div>
                    <span className="block text-xs font-medium text-gray-600">Method <span className="text-red-500">*</span></span>
                    <CustomSelect value={form.method} onChange={v => set('method', v)} options={PAYMENT_METHODS} />
                </div>
                {!isCash && (
                    <div>
                        <span className="block text-xs font-medium text-gray-600">Bank <span className="text-red-500">*</span></span>
                        <CustomSelect value={form.bank} onChange={v => set('bank', v)} options={BANK_OPTIONS} placeholder="Choose bank" error={showErrors && errors.bank} />
                        {err('bank')}
                    </div>
                )}
            </div>
            {!isCash && (
                <div>
                    {label('UTR', 'pm-utr')}
                    <input id="pm-utr" value={form.utr} onChange={e => set('utr', e.target.value)} className={inputClass} />
                    {err('utr')}
                </div>
            )}

            <div className="border-t border-gray-100 pt-3 grid grid-cols-2 gap-y-1 text-sm">
                <span className="text-gray-500">Balance now</span>
                <span className="text-right tabular-nums">{fmtMoney(balance)}</span>
                <span className="text-gray-500">After this payment</span>
                <span className="text-right tabular-nums font-semibold">{fmtMoney(paiseToInput(after))}</span>
            </div>
            {after < 0 && (
                <p className="text-xs text-amber-700">This pays {fmtMoney(paiseToInput(-after))} more than is owed; it will show as a credit.</p>
            )}
            {mutation.error && <p className="text-sm text-red-600">{mutation.error.message}</p>}
        </LedgerModal>
    )
}
