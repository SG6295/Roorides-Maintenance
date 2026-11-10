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

// Both GST-closed statuses are final and share a colour.
export function financeStatusColor(status) {
    if (status === 'New (invoice pending)') return 'bg-orange-100 text-orange-800'
    if (status === 'Hold') return 'bg-amber-100 text-amber-800'
    if (status === 'Reject') return 'bg-red-100 text-red-800'
    if (status === 'Accepted') return 'bg-blue-100 text-blue-800'
    if (status?.startsWith('GST')) return 'bg-green-100 text-green-800'
    return 'bg-gray-100 text-gray-700'
}

// finance_payment_status and finance_remark belong to finance; the database refuses
// anyone else, super_admin aside.
export const FINANCE_ROLES = ['finance', 'super_admin']
