import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'
import CreditDaysEditor from '../components/supplier-ledger/CreditDaysEditor'
import RecordPaymentModal from '../components/supplier-ledger/RecordPaymentModal'
import ReconcileModal from '../components/supplier-ledger/ReconcileModal'
import ReasonModal from '../components/supplier-ledger/ReasonModal'
import { LedgerTable, OpenItems, Tile } from '../components/supplier-ledger/LedgerParts'
import { useAuth } from '../hooks/useAuth'
import {
    useSupplierBalance, useSupplierStatement, useSupplierOpenItems,
    useRecordSupplierPayment, useCancelSupplierPayment, useReverseAdjustment,
} from '../hooks/useSupplierLedger'
import { LEDGER_WRITE_ROLES } from '../constants/supplierLedger'
import { describeLine } from '../utils/supplierLedger'
import { exportSupplierStatement } from '../utils/supplierLedgerExport'
import { todayLocal } from '../utils/datetime'
import { fmtMoney, fmtDate } from '../components/outsource-invoices/format'

/**
 * One supplier's ledger statement (MAIN-119): every invoice, advance, payment and
 * adjustment in the order it was recorded, with the running balance; what is still open
 * and which Wednesday it goes in; and finance's actions — record or cancel a payment,
 * reconcile or reverse an adjustment, set credit days. Exec reads only.
 */
export default function SupplierStatement() {
    const { supplierId } = useParams()
    const { userProfile } = useAuth()
    const canWrite = LEDGER_WRITE_ROLES.includes(userProfile?.role)
    const { data: supplier, isLoading, error } = useSupplierBalance(supplierId)
    const { data: lines = [], isLoading: linesLoading } = useSupplierStatement(supplierId)
    const { data: openItems = [] } = useSupplierOpenItems(supplierId)
    const recordPayment = useRecordSupplierPayment()
    const cancelPayment = useCancelSupplierPayment()
    const reverseAdjustment = useReverseAdjustment()
    const [dialog, setDialog] = useState(null)
    const today = todayLocal()

    if (isLoading) return <Page><div className="p-8 text-center text-sm text-gray-500">Loading…</div></Page>
    if (error || !supplier) {
        return <Page><div className="p-8 text-center text-sm text-red-600">{error ? `Could not load the ledger: ${error.message}` : 'Supplier not found.'}</div></Page>
    }

    const close = () => setDialog(null)
    const actionFor = line => {
        if (!canWrite) return null
        if (line.kind === 'payment') return { label: 'Cancel', onClick: () => setDialog({ type: 'cancel', line }) }
        if (line.kind === 'adjustment') return { label: 'Reverse', onClick: () => setDialog({ type: 'reverse', line }) }
        return null
    }

    return (
        <Page name={supplier.entity_name}>
            <div className="flex flex-wrap items-start justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">{supplier.entity_name}</h1>
                    <p className="text-sm text-gray-600 mt-1 flex flex-wrap items-center gap-x-1">
                        Credit period <CreditDaysEditor supplierId={supplier.supplier_id} value={supplier.credit_days} canEdit={canWrite} /> days
                        <span className="text-gray-400">·</span>
                        {supplier.last_reconciled_on ? `Last reconciled as of ${fmtDate(supplier.last_reconciled_on)}` : 'Not reconciled yet'}
                    </p>
                </div>
                <div className="flex flex-wrap gap-2">
                    <ExportButton onClick={() => exportSupplierStatement(supplier.entity_name, lines, today)} disabled={lines.length === 0} />
                    {canWrite && (
                        <>
                            <button type="button" onClick={() => setDialog({ type: 'reconcile' })} className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50">
                                Reconcile balance
                            </button>
                            <button type="button" onClick={() => setDialog({ type: 'payment' })} className="text-sm px-3 py-2 font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700">
                                Record payment
                            </button>
                        </>
                    )}
                </div>
            </div>

            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Tile label="Outstanding" value={fmtMoney(supplier.outstanding)} note={supplier.outstanding < 0 ? 'In credit with us' : null} />
                <Tile label="Overdue" value={fmtMoney(supplier.overdue)} tone={supplier.overdue > 0 ? 'text-red-700' : ''} />
                <Tile label="Due this Wednesday" value={fmtMoney(supplier.due_this_wednesday)} tone={supplier.due_this_wednesday > 0 ? 'text-amber-700' : ''} note={`Run of ${fmtDate(supplier.this_wednesday)}`} highlight />
                <Tile label="Next Wednesday" value={fmtMoney(supplier.due_next_wednesday)} note={supplier.later > 0 ? `+ ${fmtMoney(supplier.later)} later` : 'Nothing later'} />
            </div>

            <OpenItems items={openItems} />

            <LedgerTable
                lines={lines}
                loading={linesLoading}
                describe={describeLine}
                actionFor={actionFor}
                hasActions={canWrite}
                emptyText="Nothing in this ledger yet. Invoices appear once finance accepts them."
            />

            <p className="text-xs text-gray-500">
                Entries are in the order they were recorded. An invoice enters when finance accepts it; its due date
                still counts from the day it reached finance. Advances paid by Manjunath, Gokilavanan or Nithin are
                repaid to them under <Link to="/supplier-ledger#advances" className="text-blue-600 hover:underline">Advances to repay</Link>.
            </p>

            {dialog?.type === 'payment' && (
                <RecordPaymentModal
                    title="Record payment"
                    subtitle={`${supplier.entity_name} · Bill accounted`}
                    balance={supplier.outstanding}
                    withTds
                    mutation={recordPayment}
                    onSubmit={p => recordPayment.mutate({
                        supplierId: supplier.supplier_id,
                        payment: { amount_paid: p.amount, tds_amount: p.tds, paid_on: p.paid_on, payment_method: p.payment_method, bank: p.bank, utr: p.utr },
                    }, { onSuccess: close })}
                    onClose={close}
                />
            )}
            {dialog?.type === 'reconcile' && (
                <ReconcileModal supplier={{ id: supplier.supplier_id, entity_name: supplier.entity_name }} lines={lines} onClose={close} />
            )}
            {dialog?.type === 'cancel' && (
                <ReasonModal
                    title="Cancel payment"
                    subtitle={`${describeLine(dialog.line).title} · ${fmtMoney(-Number(dialog.line.amount))}`}
                    intro="For a transaction that failed and was refunded. The payment stays on the statement, marked cancelled."
                    keepLabel="Keep payment"
                    confirmLabel="Cancel payment"
                    mutation={cancelPayment}
                    onConfirm={reason => cancelPayment.mutate({ paymentId: dialog.line.line_id, reason }, { onSuccess: close })}
                    onClose={close}
                />
            )}
            {dialog?.type === 'reverse' && (
                <ReasonModal
                    title="Reverse adjustment"
                    subtitle={`As of ${fmtDate(dialog.line.detail?.as_of)} · ${fmtMoney(dialog.line.amount)}`}
                    intro="For an adjustment posted in error. It stays on the statement, struck through, and the balance goes back to what it was without it."
                    keepLabel="Keep adjustment"
                    confirmLabel="Reverse adjustment"
                    mutation={reverseAdjustment}
                    onConfirm={reason => reverseAdjustment.mutate({ adjustmentId: dialog.line.line_id, reason }, { onSuccess: close })}
                    onClose={close}
                />
            )}
        </Page>
    )
}

function Page({ name, children }) {
    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Supplier ledger', href: '/supplier-ledger' }, ...(name ? [{ label: name }] : [])]} />
            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6 space-y-5">{children}</div>
        </div>
    )
}

function ExportButton({ onClick, disabled }) {
    return (
        <button type="button" onClick={onClick} disabled={disabled} className="text-sm px-3 py-2 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 disabled:opacity-50">
            Export to Excel
        </button>
    )
}
