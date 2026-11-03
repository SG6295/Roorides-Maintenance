import { useState } from 'react'
import { useSetSupplierCreditDays } from '../../hooks/useSupplierLedger'

/**
 * A supplier's credit days (MAIN-119), set by finance in place. Blank counts as 0 —
 * the invoice is due the day it reaches finance — so a blank is shown as "0" with a
 * prompt to set it. Enter or clicking away saves, Esc cancels.
 */
export default function CreditDaysEditor({ supplierId, value, canEdit }) {
    const [editing, setEditing] = useState(false)
    const [draft, setDraft] = useState('')
    const [error, setError] = useState(null)
    const setDays = useSetSupplierCreditDays()

    if (!canEdit) {
        return <span>{value ?? 0}</span>
    }

    const start = () => {
        setDraft(value == null ? '' : String(value))
        setError(null)
        setEditing(true)
    }

    const save = () => {
        const text = draft.trim()
        if (text !== '' && !/^\d{1,3}$/.test(text)) {
            setError('Enter whole days, 0–365')
            return
        }
        const days = text === '' ? null : Number(text)
        if (days != null && days > 365) {
            setError('Enter whole days, 0–365')
            return
        }
        setEditing(false)
        if (days === (value ?? null)) return
        setDays.mutate({ supplierId, days }, { onError: e => setError(e.message) })
    }

    if (editing) {
        return (
            <span className="inline-flex flex-col">
                <input
                    autoFocus
                    inputMode="numeric"
                    aria-label="Credit days"
                    value={draft}
                    onChange={e => setDraft(e.target.value)}
                    onBlur={save}
                    onKeyDown={e => {
                        if (e.key === 'Enter') { e.preventDefault(); e.currentTarget.blur() }
                        if (e.key === 'Escape') setEditing(false)
                    }}
                    className="w-20 text-sm border border-blue-300 rounded-md px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
                {error && <span className="text-xs text-red-600 mt-0.5">{error}</span>}
            </span>
        )
    }

    return (
        <span className="inline-flex flex-col">
            <button type="button" onClick={start} className="text-left rounded px-1 -mx-1 hover:bg-blue-50" title="Change credit days">
                {setDays.isPending ? 'Saving…' : value == null
                    ? <><span className="text-amber-700">0</span> <span className="text-xs text-blue-600">Set</span></>
                    : value}
            </button>
            {error && <span className="text-xs text-red-600 mt-0.5 whitespace-normal">{error}</span>}
        </span>
    )
}
