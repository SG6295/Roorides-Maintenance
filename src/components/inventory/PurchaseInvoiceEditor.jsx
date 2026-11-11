import EditPurchaseModal from './EditPurchaseModal'
import EditRefurbishmentModal from './EditRefurbishmentModal'

/**
 * Opens a purchase invoice in the form for its kind (MAIN-130): Purchase History's edit
 * button and /inventory?tab=history&invoice=<id>, which Outsource Invoices and the
 * supplier ledger link to, both come through here.
 */
export default function PurchaseInvoiceEditor({ invoice, onClose }) {
    const Form = invoice.kind === 'refurbishment' ? EditRefurbishmentModal : EditPurchaseModal
    return <Form invoice={invoice} onClose={onClose} />
}
