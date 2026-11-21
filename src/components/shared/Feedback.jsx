import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { CheckCircleIcon, ExclamationCircleIcon, XMarkIcon } from '@heroicons/react/24/outline'
import { FeedbackContext } from '../../hooks/useFeedback'

/** The provider behind useToast / useConfirm (src/hooks/useFeedback.js) — MAIN-144. */

const SUCCESS_MS = 4000

export function FeedbackProvider({ children }) {
    const [toasts, setToasts] = useState([])
    const [pending, setPending] = useState(null)
    const nextId = useRef(0)

    const dismiss = useCallback(id => setToasts(list => list.filter(t => t.id !== id)), [])

    const push = useCallback((type, message) => {
        const id = ++nextId.current
        setToasts(list => [...list, { id, type, message }])
        return id
    }, [])

    const toast = useMemo(() => ({
        success: message => push('success', message),
        error: message => push('error', message),
    }), [push])

    const confirm = useCallback(options => new Promise(resolve => {
        setPending({ ...options, resolve })
    }), [])

    const settle = useCallback(result => {
        pending?.resolve(result)
        setPending(null)
    }, [pending])

    const value = useMemo(() => ({ toast, confirm }), [toast, confirm])

    return (
        <FeedbackContext.Provider value={value}>
            {children}
            {createPortal(
                <div
                    aria-live="polite"
                    className="pointer-events-none fixed inset-x-0 bottom-0 z-[60] flex flex-col items-center gap-2 p-4 sm:items-end"
                >
                    {toasts.map(t => <Toast key={t.id} toast={t} onDismiss={() => dismiss(t.id)} />)}
                </div>,
                document.body,
            )}
            {pending && <ConfirmDialog {...pending} onSettle={settle} />}
        </FeedbackContext.Provider>
    )
}

function Toast({ toast, onDismiss }) {
    const isError = toast.type === 'error'

    useEffect(() => {
        if (isError) return
        const timer = setTimeout(onDismiss, SUCCESS_MS)
        return () => clearTimeout(timer)
    }, [isError, onDismiss])

    const Icon = isError ? ExclamationCircleIcon : CheckCircleIcon
    return (
        <div
            role={isError ? 'alert' : 'status'}
            className={`pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-lg border p-3 shadow-lg ${
                isError ? 'border-red-200 bg-red-50 text-red-800' : 'border-green-200 bg-green-50 text-green-800'
            }`}
        >
            <Icon className={`h-5 w-5 flex-shrink-0 ${isError ? 'text-red-500' : 'text-green-500'}`} aria-hidden="true" />
            <p className="flex-1 text-sm whitespace-pre-line break-words">{toast.message}</p>
            <button type="button" onClick={onDismiss} aria-label="Close" className="flex-shrink-0 p-0.5 opacity-70 hover:opacity-100">
                <XMarkIcon className="h-4 w-4" />
            </button>
        </div>
    )
}

/** Styled like RejectInvoiceModal. Esc and the backdrop count as Cancel. */
function ConfirmDialog({ title, message, confirmLabel = 'Confirm', cancelLabel = 'Cancel', tone = 'danger', reason, onSettle }) {
    const [text, setText] = useState('')
    const trimmed = text.trim()
    const canConfirm = !reason?.required || trimmed !== ''

    useEffect(() => {
        const onKey = e => { if (e.key === 'Escape') onSettle(reason ? null : false) }
        document.addEventListener('keydown', onKey)
        return () => document.removeEventListener('keydown', onKey)
    }, [onSettle, reason])

    const cancel = () => onSettle(reason ? null : false)
    const accept = () => { if (canConfirm) onSettle(reason ? trimmed : true) }
    const confirmClass = tone === 'danger'
        ? 'bg-red-600 hover:bg-red-700'
        : 'bg-blue-600 hover:bg-blue-700'

    return createPortal(
        <div className="fixed inset-0 z-[70] overflow-y-auto whitespace-normal">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={cancel} />

            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="alertdialog" aria-modal="true" aria-labelledby="confirm-dialog-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-md">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="confirm-dialog-title" className="text-lg font-semibold text-gray-900">{title}</h3>
                        <button type="button" onClick={cancel} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    <div className="p-5 space-y-4">
                        {message && <p className="text-sm text-gray-700 whitespace-pre-line">{message}</p>}
                        {reason && (
                            <div>
                                <label htmlFor="confirm-dialog-reason" className="block text-sm font-medium text-gray-700 mb-1">
                                    {reason.label} {reason.required && <span className="text-red-500">*</span>}
                                </label>
                                <textarea
                                    id="confirm-dialog-reason"
                                    autoFocus
                                    rows={3}
                                    value={text}
                                    onChange={e => setText(e.target.value)}
                                    className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                />
                            </div>
                        )}
                    </div>

                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button
                            type="button"
                            onClick={cancel}
                            className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50"
                        >
                            {cancelLabel}
                        </button>
                        <button
                            type="button"
                            autoFocus={!reason}
                            onClick={accept}
                            disabled={!canConfirm}
                            className={`px-4 py-2 text-sm font-medium text-white rounded-lg disabled:opacity-50 disabled:cursor-not-allowed ${confirmClass}`}
                        >
                            {confirmLabel}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}
