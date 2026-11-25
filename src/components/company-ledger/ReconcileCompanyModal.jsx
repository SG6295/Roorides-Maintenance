import { useState } from 'react'
import LedgerModal, { CompanyLine, PrimaryButton, SecondaryButton } from '../supplier-ledger/LedgerModal'
import { useReconcileCompanyLedger } from '../../hooks/useCompanyLedger'
import { RECONCILE_FIGURES, figureAsOf, figureInWords, otherCompany } from '../../utils/companyLedger'
import { companyShortLabel } from '../../constants/vehicleCompanies'
import { toPaise, paiseToInput } from '../../utils/settlement'
import { todayLocal, formatDate } from '../../utils/datetime'
import { fmtMoney } from '../outsource-invoices/format'

/**
 * Reconciles one of a company ledger's two figures against Tally (MAIN-163), the way a
 * supplier's balance is reconciled (MAIN-119): finance enters the figure confirmed as of a
 * date; the app's own figure at the end of that day is frozen and the difference posted as
 * an adjustment line. The figure shown here is from the ledger already loaded;
 * reconcile_company_ledger recomputes it when posting.
 *
 * Owed between companies is entered as an amount and a direction, never a minus sign:
 * positive = the other company owes this one, as everywhere in the ledger.
 */
export default function ReconcileCompanyModal({ company, lines, onClose, onDone }) {
    const today = todayLocal()
    const reconcile = useReconcileCompanyLedger()
    const [balance, setBalance] = useState('spent')
    const [asOf, setAsOf] = useState(today)
    const [confirmed, setConfirmed] = useState('')
    const [theyOwe, setTheyOwe] = useState(true)
    const [reason, setReason] = useState('')
    const [showErrors, setShowErrors] = useState(false)

    const us = companyShortLabel(company)
    const them = companyShortLabel(otherCompany(company))
    const isOwed = balance === 'owed'

    const system = figureAsOf(lines, balance, asOf)
    const confirmedText = confirmed.trim()
    const confirmedAbs = confirmedText === '' ? NaN : toPaise(confirmedText)
    const confirmedPaise = isNaN(confirmedAbs) ? NaN : (isOwed && !theyOwe ? -confirmedAbs : confirmedAbs)
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
            company,
            balance,
            asOf,
            confirmedBalance: paiseToInput(confirmedPaise),
            reason: reason.trim(),
        }, { onSuccess: () => onDone?.(difference === 0) })
    }

    const inputClass = 'w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500'
    const choice = on => `flex-1 text-sm px-2 py-2 rounded-lg border whitespace-nowrap ${on ? 'border-blue-600 bg-blue-50 text-blue-800 font-medium' : 'border-gray-300 text-gray-600 hover:bg-gray-50'}`

    return (
        <LedgerModal
            title="Reconcile with Tally"
            subtitle="Company ledger"
            onClose={onClose}
            footer={<>
                <SecondaryButton onClick={onClose}>Cancel</SecondaryButton>
                <PrimaryButton onClick={submit} disabled={reconcile.isPending}>
                    {reconcile.isPending ? 'Saving…' : difference === 0 ? 'Record reconciliation' : 'Post adjustment'}
                </PrimaryButton>
            </>}
        >
            <CompanyLine company={company} what="reconciliation" />
            <p className="text-sm text-gray-600">
                Enter the figure you confirmed in Tally. The app counts everything entered up to the end of that
                day (up to now, for today), keeps its own figure, and posts the difference as an adjustment line.
                Posted one by mistake? Reverse it from the ledger.
            </p>

            <fieldset>
                <legend className="block text-xs font-medium text-gray-600 mb-1">Figure <span className="text-red-500">*</span></legend>
                <div className="flex flex-wrap gap-1.5">
                    {Object.entries(RECONCILE_FIGURES).map(([value, f]) => (
                        <button key={value} type="button" aria-pressed={balance === value} onClick={() => setBalance(value)} className={choice(balance === value)}>
                            {f.label}
                        </button>
                    ))}
                </div>
            </fieldset>

            <div>
                <label htmlFor="crc-date" className="block text-xs font-medium text-gray-600 mb-1">As of <span className="text-red-500">*</span></label>
                <input id="crc-date" type="date" max={today} value={asOf} onChange={e => setAsOf(e.target.value)} className={inputClass} />
                {err('asOf')}
            </div>

            {isOwed && (
                <fieldset>
                    <legend className="block text-xs font-medium text-gray-600 mb-1">In Tally <span className="text-red-500">*</span></legend>
                    <div className="flex flex-wrap gap-1.5">
                        <button type="button" aria-pressed={theyOwe} onClick={() => setTheyOwe(true)} className={choice(theyOwe)}>{them} owes {us}</button>
                        <button type="button" aria-pressed={!theyOwe} onClick={() => setTheyOwe(false)} className={choice(!theyOwe)}>{us} owes {them}</button>
                    </div>
                </fieldset>
            )}

            <div className="bg-gray-50 border border-gray-200 rounded-lg p-3 grid grid-cols-2 gap-y-2 items-center text-sm">
                <span className="text-gray-500">App figure at the end of {formatDate(asOf)}</span>
                <span className="text-right font-semibold tabular-nums">
                    {isOwed ? figureInWords(paiseToInput(system), company) : fmtMoney(paiseToInput(system))}
                </span>
                <label htmlFor="crc-confirmed" className="text-gray-700 font-medium">Confirmed in Tally (₹) <span className="text-red-500">*</span></label>
                <div>
                    <input id="crc-confirmed" inputMode="decimal" value={confirmed} onChange={e => setConfirmed(e.target.value)} className={`${inputClass} text-right tabular-nums`} />
                    {err('confirmed')}
                </div>
                <span className="text-gray-500 border-t border-gray-200 pt-2">Adjustment to post</span>
                <span className={`text-right font-bold tabular-nums border-t border-gray-200 pt-2 ${difference ? 'text-orange-800' : 'text-gray-700'}`}>
                    {difference == null ? '—' : difference === 0 ? 'None — figures agree'
                        : `${difference < 0 ? '−' : '+'} ${fmtMoney(paiseToInput(Math.abs(difference)))}`}
                </span>
            </div>

            <div>
                <label htmlFor="crc-reason" className="block text-xs font-medium text-gray-600 mb-1">Reason <span className="text-red-500">*</span></label>
                <textarea id="crc-reason" rows={3} value={reason} onChange={e => setReason(e.target.value)} className={inputClass} />
                {err('reason')}
            </div>
            <p className="text-xs text-gray-500">
                Recorded with your name and the time. Only {us}&apos;s ledger changes — {them}&apos;s books are reconciled on its own tab.
            </p>
            {reconcile.error && <p className="text-sm text-red-600">{reconcile.error.message}</p>}
        </LedgerModal>
    )
}
