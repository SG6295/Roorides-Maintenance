import { createPortal } from 'react-dom'
import { XMarkIcon } from '@heroicons/react/24/outline'

/**
 * The frame every supplier-ledger dialog shares (MAIN-119): title, close button, body
 * and a footer of actions. Rendered in a portal so a table's no-wrap cells cannot reach
 * it.
 */
export default function LedgerModal({ title, subtitle, onClose, footer, children }) {
    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto whitespace-normal">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={onClose} />
            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="ledger-modal-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-lg">
                    <div className="flex items-start justify-between p-5 border-b">
                        <div>
                            <h3 id="ledger-modal-title" className="text-lg font-semibold text-gray-900">{title}</h3>
                            {subtitle && <p className="text-sm text-gray-500 mt-0.5">{subtitle}</p>}
                        </div>
                        <button type="button" onClick={onClose} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>
                    <div className="p-5 space-y-4">{children}</div>
                    <div className="flex justify-end gap-3 p-5 border-t">{footer}</div>
                </div>
            </div>
        </div>,
        document.body,
    )
}

export function SecondaryButton({ children, ...props }) {
    return (
        <button type="button" className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50" {...props}>
            {children}
        </button>
    )
}

export function PrimaryButton({ children, tone = 'blue', ...props }) {
    const colors = tone === 'red' ? 'bg-red-600 hover:bg-red-700' : 'bg-blue-600 hover:bg-blue-700'
    return (
        <button
            type="button"
            className={`px-4 py-2 text-sm font-medium text-white rounded-lg disabled:opacity-50 disabled:cursor-not-allowed ${colors}`}
            {...props}
        >
            {children}
        </button>
    )
}
