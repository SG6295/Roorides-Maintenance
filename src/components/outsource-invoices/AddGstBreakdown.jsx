import { useState } from 'react'
import GstBreakdownFields from './GstBreakdownFields'
import { gstBreakdownProblem, gstRowsToBreakdown } from '../../utils/gstBreakdown'
import { useSaveInvoiceGstBreakdown } from '../../hooks/useOutsourceInvoices'
import { useToast } from '../../hooks/useFeedback'

/**
 * For a job card invoice saved before MAIN-166: its card is Completed, so the details are
 * read-only, but its GST breakdown can still be added while finance has not accepted or
 * rejected it. Shown only to execs, only while the invoice has no breakdown.
 */
export default function AddGstBreakdown({ invoice }) {
    const toast = useToast()
    const save = useSaveInvoiceGstBreakdown()
    const [open, setOpen] = useState(false)
    const [rows, setRows] = useState([])
    const [showErrors, setShowErrors] = useState(false)

    if (!open) {
        return (
            <button
                type="button"
                onClick={() => setOpen(true)}
                className="text-xs px-3 py-1.5 text-blue-700 border border-blue-200 bg-blue-50 rounded-lg hover:bg-blue-100"
            >
                Add GST breakdown
            </button>
        )
    }

    const problem = gstBreakdownProblem(rows, invoice.invoice_value)
    const submit = () => {
        setShowErrors(true)
        if (problem) return
        save.mutate(
            { id: invoice.id, breakdown: gstRowsToBreakdown(rows) },
            {
                onSuccess: () => toast.success('GST breakdown saved'),
                onError: e => toast.error('Failed to save the GST breakdown: ' + e.message),
            },
        )
    }

    return (
        <div className="border border-blue-100 bg-blue-50/40 rounded-lg p-3 space-y-3">
            <GstBreakdownFields
                rows={rows}
                onChange={setRows}
                invoiceValue={invoice.invoice_value}
                error={problem}
                showErrors={showErrors}
            />
            <div className="flex justify-end gap-2">
                <button
                    type="button"
                    onClick={() => { setOpen(false); setRows([]); setShowErrors(false) }}
                    className="text-xs px-3 py-1.5 text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50"
                >
                    Cancel
                </button>
                <button
                    type="button"
                    onClick={submit}
                    disabled={save.isPending}
                    className="text-xs px-3 py-1.5 text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                    {save.isPending ? 'Saving…' : 'Save GST breakdown'}
                </button>
            </div>
        </div>
    )
}
