import { useState } from 'react'

/**
 * View and copy the invoice file (job_cards.invoice_url) — what finance opens for
 * Tally entry. Used in the Invoice Link column (MAIN-98).
 */
export default function InvoiceFileLink({ url }) {
    const [copied, setCopied] = useState(false)

    if (!url) return <span className="text-gray-400 italic">No file</span>

    const copy = async () => {
        try {
            await navigator.clipboard.writeText(url)
            setCopied(true)
            setTimeout(() => setCopied(false), 2000)
        } catch {
            // Clipboard access can be refused (permissions, insecure context); the
            // View link still works, so there is nothing to recover.
        }
    }

    return (
        <div className="flex items-center gap-2">
            <a
                href={url}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs px-2 py-1 text-blue-600 border border-blue-200 rounded-md hover:bg-blue-50"
            >
                View
            </a>
            <button
                type="button"
                onClick={copy}
                className="text-xs px-2 py-1 text-gray-600 border border-gray-300 rounded-md hover:bg-gray-50"
            >
                {copied ? 'Copied ✓' : 'Copy'}
            </button>
        </div>
    )
}
