import { useState } from 'react'
import { CheckIcon, ClipboardDocumentIcon, KeyIcon, XMarkIcon } from '@heroicons/react/24/outline'

/**
 * Shows a new or reset password after Add User / Edit User (MAIN-144). It stays until
 * closed — never a message that fades — because the exec has to copy it and pass it on.
 */
export default function PasswordPanel({ heading, email, password, onClose }) {
    const [copied, setCopied] = useState(false)

    const copy = async () => {
        await navigator.clipboard.writeText(password)
        setCopied(true)
        setTimeout(() => setCopied(false), 2000)
    }

    return (
        <div role="status" className="rounded-lg border border-green-200 bg-green-50 p-4">
            <div className="flex items-start gap-3">
                <KeyIcon className="h-5 w-5 flex-shrink-0 text-green-600" aria-hidden="true" />
                <div className="flex-1 min-w-0 space-y-2">
                    <p className="text-sm font-semibold text-green-900">{heading}</p>
                    <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-sm">
                        <dt className="text-green-800">Email</dt>
                        <dd className="text-gray-900 break-all">{email}</dd>
                        <dt className="text-green-800">Password</dt>
                        <dd className="flex items-center gap-2">
                            <code className="font-mono text-gray-900 bg-white border border-green-200 rounded px-2 py-0.5 break-all">{password}</code>
                            <button
                                type="button"
                                onClick={copy}
                                className="inline-flex items-center gap-1 rounded-md border border-green-300 bg-white px-2 py-1 text-xs font-medium text-green-800 hover:bg-green-100"
                            >
                                {copied
                                    ? <><CheckIcon className="h-4 w-4" /> Copied</>
                                    : <><ClipboardDocumentIcon className="h-4 w-4" /> Copy</>}
                            </button>
                        </dd>
                    </dl>
                    <p className="text-xs text-green-800">Share it with them now — it isn't shown again once this is closed.</p>
                </div>
                <button type="button" onClick={onClose} aria-label="Close" className="flex-shrink-0 p-0.5 text-green-700 hover:text-green-900">
                    <XMarkIcon className="h-5 w-5" />
                </button>
            </div>
        </div>
    )
}
