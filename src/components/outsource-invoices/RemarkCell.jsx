import { useRef, useState } from 'react'
import { useUpdateFinancePaymentStatus } from '../../hooks/useOutsourceInvoices'

/**
 * The Finance Remark cell (MAIN-98). Finance and super_admin click to edit; Enter
 * or clicking away saves, Esc cancels. Everyone else sees the text.
 */
export default function RemarkCell({ invoice, canEdit }) {
    const remark = invoice.finance_remark ?? ''
    const [editing, setEditing] = useState(false)
    const [draft, setDraft] = useState(remark)
    // Esc unmounts the input, which fires blur — this stops that blur from saving.
    const cancelled = useRef(false)
    const update = useUpdateFinancePaymentStatus()

    if (!canEdit) {
        return (
            <span className="block max-w-[16rem] truncate text-gray-700" title={remark || undefined}>
                {remark || '—'}
            </span>
        )
    }

    const start = () => {
        cancelled.current = false
        setDraft(remark)
        setEditing(true)
    }

    const save = () => {
        setEditing(false)
        if (cancelled.current) return
        if ((draft.trim() || null) === (invoice.finance_remark ?? null)) return
        update.mutate({ id: invoice.id, financeRemark: draft })
    }

    const onKeyDown = e => {
        if (e.key === 'Enter') {
            e.preventDefault()
            e.currentTarget.blur()
        } else if (e.key === 'Escape') {
            cancelled.current = true
            setEditing(false)
        }
    }

    if (editing) {
        return (
            <input
                autoFocus
                value={draft}
                onChange={e => setDraft(e.target.value)}
                onBlur={save}
                onKeyDown={onKeyDown}
                aria-label="Finance remark"
                className="w-64 text-sm border border-blue-300 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
        )
    }

    return (
        <div>
            <button
                type="button"
                onClick={start}
                title={remark || 'Add a remark'}
                className={`block max-w-[16rem] truncate text-left rounded px-1 -mx-1 hover:bg-blue-50 ${remark ? 'text-gray-700' : 'text-gray-400 italic'}`}
            >
                {update.isPending ? 'Saving…' : remark || 'Add remark'}
            </button>
            {update.error && <p className="text-xs text-red-600 mt-0.5 whitespace-normal">{update.error.message}</p>}
        </div>
    )
}
