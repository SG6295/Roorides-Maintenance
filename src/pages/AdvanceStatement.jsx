import { useState } from 'react'
import { useParams } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'
import RecordPaymentModal from '../components/supplier-ledger/RecordPaymentModal'
import ReasonModal from '../components/supplier-ledger/ReasonModal'
import { LedgerTable, OpenItems, Tile } from '../components/supplier-ledger/LedgerParts'
import { useAuth } from '../hooks/useAuth'
import {
    useAdvanceBalances, useAdvanceStatement, useAdvanceOpenItems,
    useRecordAdvanceRepayment, useCancelAdvanceRepayment,
} from '../hooks/useSupplierLedger'
import { ADVANCE_PEOPLE, LEDGER_WRITE_ROLES } from '../constants/supplierLedger'
import { describeAdvanceLine } from '../utils/supplierLedger'
import { upcomingRuns } from '../utils/paymentRuns'
import { exportAdvanceStatement } from '../utils/supplierLedgerExport'
import { todayLocal } from '../utils/datetime'
import { fmtMoney, fmtDate } from '../components/outsource-invoices/format'

/**
 * What NVS owes one person for advances they paid suppliers upfront (MAIN-119): each
 * advance on an accepted invoice, each repayment, in recording order with the running
 * balance; what is still open and which Wednesday it goes in. Finance records and
 * cancels repayments; exec reads.
 */
export default function AdvanceStatement() {
    const { person: personParam } = useParams()
    const person = ADVANCE_PEOPLE.find(p => p.ledger === decodeURIComponent(personParam))
    const { userProfile } = useAuth()
    const canWrite = LEDGER_WRITE_ROLES.includes(userProfile?.role)
    const { data: balances = [], isLoading } = useAdvanceBalances()
    const { data: lines = [], isLoading: linesLoading } = useAdvanceStatement(person?.ledger)
    const { data: openItems = [] } = useAdvanceOpenItems(person?.ledger)
    const record = useRecordAdvanceRepayment()
    const cancel = useCancelAdvanceRepayment()
    const [dialog, setDialog] = useState(null)
    const today = todayLocal()
    const { thisRun } = upcomingRuns(today)

    if (!person) return <Page><div className="p-8 text-center text-sm text-red-600">Unknown person.</div></Page>
    if (isLoading) return <Page name={person.name}><div className="p-8 text-center text-sm text-gray-500">Loading…</div></Page>

    const bal = balances.find(b => b.person === person.ledger) ?? { owed: 0, overdue: 0, due_this_wednesday: 0, due_next_wednesday: 0, later: 0 }
    const close = () => setDialog(null)

    return (
        <Page name={person.name}>
            <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">Advances to repay — {person.name}</h1>
                    <p className="text-sm text-gray-600 mt-1">
                        Ledger <span className="font-medium">{person.ledger}</span> · advances paid to suppliers upfront on accepted invoices.
                        Each is due on the first Wednesday after the invoice reached finance.
                    </p>
                </div>
                <div className="flex flex-wrap gap-2">
                    <button
                        type="button"
                        onClick={() => exportAdvanceStatement(person.name, lines, today)}
                        disabled={lines.length === 0}
                        className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50"
                    >
                        Export to Excel
                    </button>
                    {canWrite && (
                        <button type="button" onClick={() => setDialog({ type: 'repay' })} className="text-sm px-3 py-2 font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700">
                            Record repayment
                        </button>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Tile label="Owed" value={fmtMoney(bal.owed)} note={bal.owed < 0 ? 'Repaid more than advanced' : null} />
                <Tile label="Overdue" value={fmtMoney(bal.overdue)} tone={bal.overdue > 0 ? 'text-red-700' : ''} />
                <Tile label="Due this Wednesday" value={fmtMoney(bal.due_this_wednesday)} tone={bal.due_this_wednesday > 0 ? 'text-amber-700' : ''} note={`Run of ${fmtDate(thisRun)}`} highlight />
                <Tile label="Next Wednesday" value={fmtMoney(bal.due_next_wednesday)} note={bal.later > 0 ? `+ ${fmtMoney(bal.later)} later` : 'Nothing later'} />
            </div>

            <OpenItems items={openItems} showSupplier />

            <LedgerTable
                lines={lines}
                loading={linesLoading}
                describe={describeAdvanceLine}
                actionFor={line => (canWrite && line.kind === 'repayment' ? { label: 'Cancel', onClick: () => setDialog({ type: 'cancel', line }) } : null)}
                hasActions={canWrite}
                emptyText={`No advances by ${person.name} on accepted invoices yet.`}
            />

            {dialog?.type === 'repay' && (
                <RecordPaymentModal
                    title="Record repayment"
                    subtitle={`${person.name} · ${person.ledger}`}
                    balance={bal.owed}
                    mutation={record}
                    onSubmit={p => record.mutate({
                        person: person.ledger,
                        payment: { amount: p.amount, paid_on: p.paid_on, payment_method: p.payment_method, bank: p.bank, utr: p.utr },
                    }, { onSuccess: close })}
                    onClose={close}
                />
            )}
            {dialog?.type === 'cancel' && (
                <ReasonModal
                    title="Cancel repayment"
                    subtitle={`${person.name} · ${fmtMoney(-Number(dialog.line.amount))}`}
                    intro="For a transaction that failed and was refunded. The repayment stays on the statement, marked cancelled."
                    keepLabel="Keep repayment"
                    confirmLabel="Cancel repayment"
                    mutation={cancel}
                    onConfirm={reason => cancel.mutate({ repaymentId: dialog.line.line_id, reason }, { onSuccess: close })}
                    onClose={close}
                />
            )}
        </Page>
    )
}

function Page({ name, children }) {
    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Supplier ledger', href: '/supplier-ledger' }, { label: name ? `Advances — ${name}` : 'Advances' }]} />
            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">{children}</div>
        </div>
    )
}
