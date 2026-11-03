import { useState } from 'react'
import CustomSelect from '../shared/CustomSelect'
import LedgerModal, { PrimaryButton, SecondaryButton } from './LedgerModal'
import { useRecordSupplierPayment } from '../../hooks/useSupplierLedger'
import { LEDGER_OPTIONS, PAYMENT_METHODS, BANK_OPTIONS } from '../../constants/outsourceInvoices'
import { VENDOR_LEDGER } from '../../constants/supplierLedger'
import { toPaise, paiseToInput } from '../../utils/settlement'
import { todayLocal } from '../../utils/datetime'
import { fmtMoney } from '../outsource-invoices/format'

/**
 * Records a payment against a supplier (MAIN-119). Posted to Bill accounted it pays the
 * vendor and reduces the balance; posted to a person it repays their advance and is
 * listed for reference only — the form says which, and shows the balance after.
 * record_supplier_payment makes the binding checks.
 */
export default function RecordSupplierPaymentModal({ supplier, outstanding, onClose }) {
    const today = todayLocal()
    const record = useRecordSupplierPayment()
    const [form, setForm] = useState({
        amountPaid: '', tds: '', paidOn: today, ledger: VENDOR_LEDGER, method: 'NEFT', bank: '', utr: '',
    })
    const [showErrors, setShowErrors] = useState(false)
    const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

    const paid = toPaise(form.amountPaid)
    const tds = toPaise(form.tds)
    const isCash = form.method === 'Cash'
    const toVendor = form.ledger === VENDOR_LEDGER
    // Display only: a numeric(12,2) from the database is exact in paise once rounded.
    const outstandingPaise = Math.round(Number(outstanding ?? 0) * 100)
    const after = toVendor && !isNaN(paid) && !isNaN(tds) ? outstandingPaise - paid - tds : outstandingPaise

    const errors = {}
    if (isNaN(paid)) errors.amountPaid = 'Enter an amount with at most two decimals'
    if (isNaN(tds)) errors.tds = 'Enter an amount with at most two decimals'
    if (!isNaN(paid) && !isNaN(tds) && paid + tds <= 0) errors.amountPaid = 'Enter a paid value or TDS'
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
        record.mutate({
            supplierId: supplier.id,
            payment: {
                amount_paid: paiseToInput(paid),
                tds_amount: paiseToInput(tds),
                paid_on: form.paidOn,
                ledger: form.ledger,
                payment_method: form.method,
                bank: isCash ? null : form.bank,
                utr: isCash ? null : form.utr.trim(),
            },
        }, { onSuccess: onClose })
    }

    const inputClass = 'w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500'

    return (
        <LedgerModal
            title="Record payment"
            subtitle={`${supplier.entity_name} · balance ${fmtMoney(outstanding)}`}
            onClose={onClose}
            footer={<>
                <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
                <PrimaryButton onClick={submit} disabled={record.isPending}>
                    {record.isPending ? 'Saving…' : 'Record payment'}
                </PrimaryButton>
            </>}
        >
            <div className="grid grid-cols-2 gap-3">
                <div>
                    <label htmlFor="sp-paid" className="block text-xs font-medium text-gray-600 mb-1">Paid value (₹) <span className="text-red-500">*</span></label>
                    <input id="sp-paid" inputMode="decimal" value={form.amountPaid} onChange={e => set('amountPaid', e.target.value)} className={inputClass} />
                    {err('amountPaid')}
                </div>
                <div>
                    <label htmlFor="sp-tds" className="block text-xs font-medium text-gray-600 mb-1">TDS (₹)</label>
                    <input id="sp-tds" inputMode="decimal" value={form.tds} onChange={e => set('tds', e.target.value)} className={inputClass} />
                    {err('tds')}
                </div>
                <div>
                    <label htmlFor="sp-date" className="block text-xs font-medium text-gray-600 mb-1">Date paid <span className="text-red-500">*</span></label>
                    <input id="sp-date" type="date" max={today} value={form.paidOn} onChange={e => set('paidOn', e.target.value)} className={inputClass} />
                    {err('paidOn')}
                </div>
                <div>
                    <span className="block text-xs font-medium text-gray-600">Posted ledger <span className="text-red-500">*</span></span>
                    <CustomSelect value={form.ledger} onChange={v => set('ledger', v)} options={LEDGER_OPTIONS} />
                </div>
            </div>

            {!toVendor && (
                <p className="text-sm text-blue-900 bg-blue-50 border border-blue-200 rounded-lg p-3">
                    <strong>Paying {form.ledger} back for an advance.</strong> It is recorded on {supplier.entity_name}'s
                    statement for reference, but does <strong>not</strong> change what the supplier is owed.
                    To pay the supplier, choose <em>{VENDOR_LEDGER}</em>.
                </p>
            )}

            <div className="grid grid-cols-2 gap-3">
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
                    <label htmlFor="sp-utr" className="block text-xs font-medium text-gray-600 mb-1">UTR <span className="text-red-500">*</span></label>
                    <input id="sp-utr" value={form.utr} onChange={e => set('utr', e.target.value)} className={inputClass} />
                    {err('utr')}
                </div>
            )}

            <div className="border-t border-gray-100 pt-3 grid grid-cols-2 gap-y-1 text-sm">
                <span className="text-gray-500">Supplier balance now</span>
                <span className="text-right tabular-nums">{fmtMoney(outstanding)}</span>
                <span className="text-gray-500">After this payment</span>
                <span className="text-right tabular-nums font-semibold">
                    {fmtMoney(paiseToInput(after))}
                    {!toVendor && <span className="font-normal text-gray-500"> (unchanged)</span>}
                </span>
            </div>
            {toVendor && after < 0 && (
                <p className="text-xs text-amber-700">This pays more than is owed; the supplier will show a credit of {fmtMoney(paiseToInput(-after))}.</p>
            )}
            {record.error && <p className="text-sm text-red-600">{record.error.message}</p>}
        </LedgerModal>
    )
}
