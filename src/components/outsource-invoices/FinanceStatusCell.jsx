import { useEffect, useState } from 'react'
import CustomSelect from '../shared/CustomSelect'
import RejectInvoiceModal from './RejectInvoiceModal'
import { useUpdateFinancePaymentStatus } from '../../hooks/useOutsourceInvoices'
import { FINANCE_STATUS_MOVES } from '../../constants/outsourceInvoices'
import { financeStatusColor } from './format'

/**
 * The Finance Status cell (MAIN-98, MAIN-118). Finance and super_admin pick a status
 * straight from the table and it saves on pick; everyone else sees the badge, with the
 * remark on hover.
 *
 * Only the moves allowed from the current status are offered, and a final status
 * (Reject, either GST-closed) is a badge for everyone. Reject asks for its reason first
 * and saves the two together, so they land as one history entry.
 */
export default function FinanceStatusCell({ invoice, canEdit }) {
    const update = useUpdateFinancePaymentStatus()
    const [saved, setSaved] = useState(false)
    const [rejecting, setRejecting] = useState(false)

    useEffect(() => {
        if (!saved) return
        const t = setTimeout(() => setSaved(false), 2000)
        return () => clearTimeout(t)
    }, [saved])

    const status = invoice.finance_payment_status
    const moves = FINANCE_STATUS_MOVES[status] ?? []

    if (!canEdit || moves.length === 0) {
        return (
            <span
                title={invoice.finance_remark || undefined}
                className={`px-2 py-0.5 rounded-full text-xs font-medium ${financeStatusColor(status)}`}
            >
                {status}
            </span>
        )
    }

    const save = (patch, onSaved) => update.mutate(
        { id: invoice.id, ...patch },
        { onSuccess: () => { setSaved(true); onSaved?.() } },
    )

    const pick = next => {
        if (next === status) return
        if (next === 'Reject') {
            update.reset()
            setRejecting(true)
            return
        }
        save({ financePaymentStatus: next })
    }

    return (
        <div className="min-w-[13rem]">
            <CustomSelect
                value={status}
                onChange={pick}
                options={[status, ...moves]}
                disabled={update.isPending}
                compact
            />
            {saved && <p className="text-xs text-green-700 mt-0.5">Saved ✓</p>}
            {update.error && !rejecting && <p className="text-xs text-red-600 mt-0.5 whitespace-normal">{update.error.message}</p>}
            {rejecting && (
                <RejectInvoiceModal
                    invoice={invoice}
                    isSaving={update.isPending}
                    error={update.error}
                    onCancel={() => setRejecting(false)}
                    onConfirm={reason => save(
                        { financePaymentStatus: 'Reject', financeRemark: reason },
                        () => setRejecting(false),
                    )}
                />
            )}
        </div>
    )
}
