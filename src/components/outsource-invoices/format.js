import { format, isValid } from 'date-fns'
import { toDate } from '../../utils/datetime'
import { paiseToInput } from '../../utils/settlement'

export function fmtMoney(v) {
    if (v == null || v === '') return '—'
    return `₹${Number(v).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
}

export function fmtPaise(paise) {
    return fmtMoney(paiseToInput(paise))
}

export function fmtDate(d) {
    if (!d) return '—'
    const parsed = toDate(d)
    return parsed && isValid(parsed) ? format(parsed, 'dd MMM yyyy') : '—'
}

export function fmtDateTime(d) {
    if (!d) return '—'
    const parsed = toDate(d)
    return parsed && isValid(parsed) ? format(parsed, 'dd MMM yyyy, h:mm a') : '—'
}

export const MAINTENANCE_STATUS_COLORS = {
    Approved: 'bg-green-100 text-green-800',
    Hold:     'bg-amber-100 text-amber-800',
    Reject:   'bg-red-100 text-red-800',
}

// Finance's Hold and Reject statuses each come in several reasons; colour by the family.
export function financeStatusColor(status) {
    if (status === 'Paid') return 'bg-green-100 text-green-800'
    if (status === 'Partly Paid') return 'bg-blue-100 text-blue-800'
    if (status?.startsWith('Hold')) return 'bg-amber-100 text-amber-800'
    if (status?.startsWith('Reject')) return 'bg-red-100 text-red-800'
    return 'bg-gray-100 text-gray-700'
}

// finance_payment_status, finance_remark and the payments belong to finance; the
// database refuses anyone else, super_admin aside.
export const FINANCE_ROLES = ['finance', 'super_admin']
