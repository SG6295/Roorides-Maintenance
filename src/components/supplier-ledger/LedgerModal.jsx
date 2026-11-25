import { createPortal } from 'react-dom'
import { XMarkIcon } from '@heroicons/react/24/outline'
import { companyLabel } from '../../constants/vehicleCompanies'

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

/**
 * The company a ledger entry is recorded for (MAIN-162) — the tab's, shown and never
 * editable. An entry under the wrong company is cancelled with a reason and recorded again
 * on the other company's tab.
 */
export function CompanyLine({ company, what = 'entry' }) {
    return (
        <div className="rounded-lg bg-gray-50 border border-gray-200 px-3 py-2 text-sm">
            <span className="text-gray-500">For </span>
            <span className="font-semibold text-gray-900">{companyLabel(company)}</span>
            <p className="text-xs text-gray-500 mt-0.5">
                Set by the tab you are on. For the other company, record the {what} on its tab instead.
            </p>
        </div>
    )
}
