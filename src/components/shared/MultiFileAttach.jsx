import { useRef, useState } from 'react'
import { ArrowUpTrayIcon, PaperClipIcon, XMarkIcon } from '@heroicons/react/24/outline'
import { ACCEPTED_TYPES, combineFilesToPdf, isAccepted } from '../../lib/filesToPdf'
import { uploadToDrive } from '../../lib/googleDrive'
import PendingPdfPanel from './PendingPdfPanel'

/**
 * Invoice-document field: attach one file and it uploads as it always has;
 * attach several and they are staged for ordering, then combined into a single
 * PDF before upload.
 *
 * `value` / `onChange` use the `{ name, url }` shape the purchase modals already
 * write to `invoice_file_url`, so their submit paths are untouched.
 */
export default function MultiFileAttach({
    value,
    onChange,
    accept = 'image/*,application/pdf',
    maxFileSizeMb = 20,
    idleLabel = 'Attach invoice images or PDF',
}) {
    const inputRef = useRef(null)
    const [pending, setPending] = useState([])
    const [busyLabel, setBusyLabel] = useState(null)
    const [error, setError] = useState(null)

    function validate(files) {
        for (const file of files) {
            if (!isAccepted(file)) {
                return `"${file.name}" isn't a supported file. Attach images (JPG, PNG) or PDFs.`
            }
            if (file.size > maxFileSizeMb * 1024 * 1024) {
                return `"${file.name}" is larger than ${maxFileSizeMb}MB.`
            }
        }
        return null
    }

    async function handleSelect(e) {
        const selected = Array.from(e.target.files || [])
        // Reset immediately so the same file can be picked again after a removal.
        e.target.value = ''
        if (selected.length === 0) return

        const problem = validate(selected)
        if (problem) {
            setError(problem)
            return
        }
        setError(null)

        // Adding to an existing selection keeps the panel open for ordering.
        if (pending.length > 0) {
            setPending(prev => [...prev, ...selected])
            return
        }
        // A single file is the common case and behaves exactly as before —
        // straight to upload, and pdf-lib is never fetched.
        if (selected.length === 1) {
            await upload(selected[0])
            return
        }
        setPending(selected)
    }

    async function upload(file) {
        setBusyLabel('Uploading…')
        try {
            const url = await uploadToDrive(file)
            onChange({ name: file.name, url })
            setPending([])
            setError(null)
        } catch (err) {
            console.error(err)
            setError(err.message || 'Upload failed. Please try again.')
        } finally {
            setBusyLabel(null)
        }
    }

    async function handleConfirm() {
        if (pending.length === 0) return
        // Removing files can leave one behind; upload it as-is rather than
        // wrapping a single page in a pointless PDF.
        if (pending.length === 1) {
            await upload(pending[0])
            return
        }
        setError(null)
        setBusyLabel('Combining…')
        try {
            const pdf = await combineFilesToPdf(pending)
            await upload(pdf)
        } catch (err) {
            console.error(err)
            setError(err.message || 'Could not combine these files.')
            setBusyLabel(null)
        }
    }

    if (pending.length > 0) {
        return (
            <>
                <HiddenInput inputRef={inputRef} accept={accept} onChange={handleSelect} />
                <PendingPdfPanel
                    files={pending}
                    onChange={setPending}
                    onAddMore={() => inputRef.current?.click()}
                    onConfirm={handleConfirm}
                    onCancel={() => { setPending([]); setError(null) }}
                    busy={busyLabel !== null}
                    busyLabel={busyLabel || ''}
                    error={error}
                />
            </>
        )
    }

    return (
        <>
            <HiddenInput inputRef={inputRef} accept={accept} onChange={handleSelect} />

            {busyLabel ? (
                <div className="flex items-center gap-2 px-4 py-2.5 border rounded-lg text-sm text-gray-500 bg-gray-50">
                    <div className="w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
                    {busyLabel}
                </div>
            ) : value?.url ? (
                <div className="flex items-center gap-2 px-4 py-2.5 border border-green-200 rounded-lg bg-green-50">
                    <PaperClipIcon className="w-4 h-4 text-green-600 shrink-0" />
                    <a
                        href={value.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-green-700 hover:underline truncate flex-1"
                    >
                        {value.name}
                    </a>
                    <button type="button" onClick={() => onChange(null)} className="text-gray-400 hover:text-red-500 shrink-0">
                        <XMarkIcon className="w-4 h-4" />
                    </button>
                </div>
            ) : (
                <button
                    type="button"
                    onClick={() => inputRef.current?.click()}
                    className="flex items-center gap-2 px-4 py-2.5 border-2 border-dashed border-gray-300 rounded-lg text-sm text-gray-500 hover:border-blue-400 hover:text-blue-600 transition-colors w-full justify-center"
                >
                    <ArrowUpTrayIcon className="w-4 h-4" />
                    {idleLabel}
                </button>
            )}

            {error && <p className="mt-1.5 text-xs text-red-600">{error}</p>}
            {!value?.url && !busyLabel && (
                <p className="mt-1.5 text-xs text-gray-400">
                    Attach several pages at once and they'll be combined into a single PDF.
                </p>
            )}
        </>
    )
}

function HiddenInput({ inputRef, accept, onChange }) {
    return (
        <input
            ref={inputRef}
            type="file"
            multiple
            accept={accept || ACCEPTED_TYPES.join(',')}
            onChange={onChange}
            className="hidden"
        />
    )
}
