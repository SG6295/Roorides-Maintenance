import { useState } from 'react'
import { useAuth } from './useAuth'
import { useUpdatePurchaseInvoice } from './useInventory'
import { invoiceFormFromRow, invoiceFormToRow, validateInvoiceForm } from '../components/outsource-invoices/invoiceForm'
import { isLockedByFinance, isRejectedInvoice } from '../constants/outsourceInvoices'
import { approvedAmountError } from '../utils/refurbishment'
import { todayLocal } from '../utils/datetime'

/**
 * What the purchase and refurbishment forms share (MAIN-130): the supplier, notes, the
 * invoice details for finance, the invoice file, the Accepted lock, finance's read-only
 * view, their validation and the save. Each form adds its own lines and workshop.
 * Both save through save_purchase_invoice.
 */
export function usePurchaseInvoiceForm(invoice) {
    const { userProfile } = useAuth()
    const updateInvoice = useUpdatePurchaseInvoice()
    const todayStr = todayLocal()

    // The invoice's finance invoice (MAIN-129). One recorded before purchases went to
    // finance has none, and saves as it always did.
    const finance = invoice.finance_invoice ?? null
    // Finance reviews purchase invoices but does not edit them.
    const isFinanceRole = userProfile?.role === 'finance'
    // Once finance has accepted it, only the notes can change; finance moving it back to
    // Hold lifts that.
    const accepted = isLockedByFinance(finance)
    const frozen = isFinanceRole || accepted
    // A rejected invoice is saved only by resubmitting it (MAIN-120): Save becomes
    // Resubmit to finance, with an optional note.
    const rejected = isRejectedInvoice(finance) && !isFinanceRole
    const [resubmitNote, setResubmitNote] = useState('')

    const [header, setHeader] = useState({
        invoice_number: invoice.invoice_number,
        supplier_id: invoice.supplier_id || '',
        invoice_date: invoice.invoice_date,
        notes: invoice.notes || '',
    })
    // The finance details, with the invoice number and date — shared with the header.
    const [invoiceForm, setInvoiceForm] = useState(() => finance && {
        ...invoiceFormFromRow(finance),
        dateOfActivity: invoice.invoice_date || '',
        invoiceNo: invoice.invoice_number || '',
    })
    const [showErrors, setShowErrors] = useState(false)
    const [invoiceFile, setInvoiceFile] = useState(
        invoice.invoice_file_url
            ? { name: 'Existing document', url: invoice.invoice_file_url }
            : null
    )

    const invoiceErrors = finance ? validateInvoiceForm(invoiceForm, todayStr) : {}
    const filePending = !!finance && !invoiceFile?.url

    /** The lines against the Approved Amount, or null when they match or cannot change. */
    const amountError = lines =>
        finance && !frozen ? approvedAmountError(lines, invoiceForm.approvedAmount) : null

    /** The first thing wrong with the shared fields, or null. */
    function sharedError(lines) {
        if (finance && invoice.invoice_file_url && !invoiceFile?.url) {
            return 'The invoice file cannot be removed once attached. Replace it instead.'
        }
        if (Object.keys(invoiceErrors).length > 0) return 'Check the invoice details.'
        return amountError(lines)
    }

    // An invoice with a finance invoice takes its number and date from the invoice
    // details; its other details travel alongside.
    // Billed to is required (MAIN-157); an invoice from before then reads NVS Travels.
    function save({ locationId, billedTo, lines }) {
        const { invoice_no, date_of_activity, ...details } = finance ? invoiceFormToRow(invoiceForm) : {}
        return updateInvoice.mutateAsync({
            invoiceId: invoice.id,
            invoiceData: {
                ...header,
                ...(finance ? { invoice_number: invoice_no, invoice_date: date_of_activity } : {}),
                invoice_file_url: invoiceFile?.url || null,
                location_id: locationId,
                billed_to: billedTo,
            },
            lineItems: lines,
            finance: finance ? details : null,
            resubmit: rejected ? { note: resubmitNote.trim() } : null,
        })
    }

    return {
        invoice, finance, isFinanceRole, accepted, frozen, rejected, todayStr,
        resubmitNote, setResubmitNote,
        header, setHeader,
        invoiceForm, setInvoiceForm, invoiceErrors,
        showErrors, revealErrors: () => setShowErrors(true),
        invoiceFile, setInvoiceFile, filePending,
        amountError, sharedError, save,
        saving: updateInvoice.isPending,
    }
}
