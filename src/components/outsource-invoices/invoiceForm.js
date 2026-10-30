/**
 * The outsource invoice form's values and rules — shared by the job card (one vehicle)
 * and the multi-vehicle invoice page (MAIN-99), so the two cannot drift apart. The form
 * holds the values as typed, in the camelCase shape below.
 */
export const EMPTY_INVOICE_FORM = {
    dateOfActivity: '',
    invoiceNo: '',
    paidBy: '',
    invoiceValue: '',
    approvedAmount: '',
    advanceAmount: '',
    maintenancePaymentStatus: '',
    paybyDate: '',
}

/** An outsource_invoices row as form values. */
export function invoiceFormFromRow(row) {
    return {
        dateOfActivity: row.date_of_activity || '',
        invoiceNo: row.invoice_no || '',
        paidBy: row.paid_by || '',
        invoiceValue: row.invoice_value != null ? String(row.invoice_value) : '',
        approvedAmount: row.approved_amount != null ? String(row.approved_amount) : '',
        advanceAmount: row.advance_amount != null ? String(row.advance_amount) : '',
        maintenancePaymentStatus: row.maintenance_payment_status || '',
        paybyDate: row.payby_date || '',
    }
}

/** Form values as outsource_invoices columns. Call only once validateInvoiceForm passes. */
export function invoiceFormToRow(f) {
    return {
        date_of_activity: f.dateOfActivity,
        invoice_no: f.invoiceNo.trim(),
        paid_by: f.paidBy,
        invoice_value: parseFloat(f.invoiceValue),
        approved_amount: parseFloat(f.approvedAmount),
        advance_amount: parseFloat(f.advanceAmount),
        maintenance_payment_status: f.maintenancePaymentStatus,
        payby_date: f.paybyDate,
    }
}

/** True when nothing has been typed — a job card's invoice is optional until started. */
export function isInvoiceFormEmpty(f) {
    return Object.values(f).every(v => String(v).trim() === '')
}

export function validateInvoiceForm(f, today) {
    const errors = {}
    if (!f.dateOfActivity) errors.dateOfActivity = 'Required'
    else if (f.dateOfActivity > today) errors.dateOfActivity = 'Cannot be in the future'
    if (!f.invoiceNo.trim()) errors.invoiceNo = 'Required'
    else if (f.invoiceNo.trim().length > 50) errors.invoiceNo = 'Max 50 characters'
    if (!f.paidBy) errors.paidBy = 'Required'
    const iv = parseFloat(f.invoiceValue)
    if (f.invoiceValue === '' || isNaN(iv) || iv <= 0) errors.invoiceValue = 'Must be > 0'
    const aa = parseFloat(f.approvedAmount)
    if (f.approvedAmount === '' || isNaN(aa) || aa < 0) errors.approvedAmount = 'Must be ≥ 0'
    else if (!isNaN(iv) && aa > iv) errors.approvedAmount = 'Must be ≤ invoice value'
    const adv = parseFloat(f.advanceAmount)
    if (f.advanceAmount === '' || isNaN(adv) || adv < 0) errors.advanceAmount = 'Must be ≥ 0'
    else if (!isNaN(aa) && adv > aa) errors.advanceAmount = 'Must be ≤ approved amount'
    if (!f.maintenancePaymentStatus) errors.maintenancePaymentStatus = 'Required'
    if (!f.paybyDate) errors.paybyDate = 'Required'
    else if (f.dateOfActivity && f.paybyDate < f.dateOfActivity) errors.paybyDate = 'Must be ≥ date of activity'
    return errors
}
