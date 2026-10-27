import { useEffect, useState } from 'react'
import CustomSelect from '../shared/CustomSelect'
import { useUpdateFinancePaymentStatus } from '../../hooks/useOutsourceInvoices'
import {
    MANUAL_FINANCE_PAYMENT_STATUSES,
    PAYMENT_DERIVED_STATUSES,
} from '../../constants/outsourceInvoices'
import { financeStatusColor } from './format'

/**
 * The Finance Status cell (MAIN-98). Finance and super_admin pick a status straight
 * from the table and it saves on pick; everyone else sees the badge, with the
 * remark on hover.
 *
 * Partly Paid and Paid come only from payments, so they are not offered. When the
 * invoice is in one of them it is listed so the dropdown can show it, but choosing
 * it again changes nothing.
 */
export default function FinanceStatusCell({ invoice, canEdit }) {
    const update = useUpdateFinancePaymentStatus()
    const [saved, setSaved] = useState(false)

    useEffect(() => {
        if (!saved) return
        const t = setTimeout(() => setSaved(false), 2000)
        return () => clearTimeout(t)
    }, [saved])

    const status = invoice.finance_payment_status

    if (!canEdit) {
        return (
            <span
                title={invoice.finance_remark || undefined}
                className={`px-2 py-0.5 rounded-full text-xs font-medium ${financeStatusColor(status)}`}
            >
                {status}
            </span>
        )
    }

    const options = PAYMENT_DERIVED_STATUSES.includes(status)
        ? [status, ...MANUAL_FINANCE_PAYMENT_STATUSES]
        : MANUAL_FINANCE_PAYMENT_STATUSES

    const pick = next => {
        if (next === status) return
        update.mutate(
            { id: invoice.id, financePaymentStatus: next },
            { onSuccess: () => setSaved(true) },
        )
    }

    return (
        <div className="min-w-[13rem]">
            <CustomSelect
                value={status}
                onChange={pick}
                options={options}
                disabled={update.isPending}
                compact
            />
            {saved && <p className="text-xs text-green-700 mt-0.5">Saved ✓</p>}
            {update.error && <p className="text-xs text-red-600 mt-0.5 whitespace-normal">{update.error.message}</p>}
        </div>
    )
}
