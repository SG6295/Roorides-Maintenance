import { ArrowDownIcon, ArrowUpIcon, DocumentIcon, PlusIcon, XMarkIcon } from '@heroicons/react/24/outline'
import { isImage } from '../../lib/filesToPdf'

/**
 * Thumbnail for one pending file. The object URL is created when the <img>
 * mounts and revoked by the ref cleanup when it goes away, which keeps the two
 * in step even under StrictMode's mount-unmount-remount: creating the URL in a
 * memo instead left the src pointing at an already-revoked blob.
 */
function Thumbnail({ file }) {
    if (!isImage(file)) return <DocumentIcon className="w-5 h-5 text-gray-400" />
    return (
        <img
            alt=""
            className="w-full h-full object-cover"
            ref={node => {
                if (!node) return
                const url = URL.createObjectURL(file)
                node.src = url
                return () => URL.revokeObjectURL(url)
            }}
        />
    )
}

/**
 * The staging panel shown when two or more files are attached: numbered
 * thumbnails with reorder and remove controls, above an explicit confirm.
 *
 * Page order is the user's to set, which is why this is a visible panel rather
 * than a yes/no confirmation — a confirmation couldn't show order at all.
 *
 * Presentational: the caller owns the `files` array and receives every change
 * through `onChange`.
 */
export default function PendingPdfPanel({
    files,
    onChange,
    onAddMore,
    onConfirm,
    onCancel,
    busy = false,
    busyLabel = '',
    error = null,
}) {
    function move(index, delta) {
        const target = index + delta
        if (target < 0 || target >= files.length) return
        const next = [...files]
        ;[next[index], next[target]] = [next[target], next[index]]
        onChange(next)
    }

    function remove(index) {
        onChange(files.filter((_, i) => i !== index))
    }

    return (
        <div className="border border-blue-200 bg-blue-50/50 rounded-lg p-3">
            <p className="text-xs font-medium text-blue-800 mb-2">
                {files.length > 1
                    ? `${files.length} files will be combined into one PDF, in the order shown.`
                    : 'This file will be attached as it is.'}
            </p>

            <ul className="space-y-1.5">
                {files.map((file, i) => (
                    <li
                        key={`${file.name}-${file.lastModified}-${i}`}
                        className="flex items-center gap-2.5 bg-white border border-gray-200 rounded-lg px-2 py-1.5"
                    >
                        <span className="w-5 shrink-0 text-xs font-semibold text-gray-400 text-center">{i + 1}</span>

                        <div className="w-10 h-10 shrink-0 rounded border border-gray-200 bg-gray-50 overflow-hidden flex items-center justify-center">
                            <Thumbnail file={file} />
                        </div>

                        <div className="min-w-0 flex-1">
                            <p className="text-xs text-gray-700 truncate">{file.name}</p>
                            <p className="text-[11px] text-gray-400">{formatSize(file.size)}</p>
                        </div>

                        <div className="flex items-center gap-0.5 shrink-0">
                            <button
                                type="button"
                                onClick={() => move(i, -1)}
                                disabled={busy || i === 0}
                                aria-label={`Move ${file.name} up`}
                                className="p-1 text-gray-400 hover:text-gray-700 disabled:opacity-30 disabled:hover:text-gray-400"
                            >
                                <ArrowUpIcon className="w-3.5 h-3.5" />
                            </button>
                            <button
                                type="button"
                                onClick={() => move(i, 1)}
                                disabled={busy || i === files.length - 1}
                                aria-label={`Move ${file.name} down`}
                                className="p-1 text-gray-400 hover:text-gray-700 disabled:opacity-30 disabled:hover:text-gray-400"
                            >
                                <ArrowDownIcon className="w-3.5 h-3.5" />
                            </button>
                            <button
                                type="button"
                                onClick={() => remove(i)}
                                disabled={busy}
                                aria-label={`Remove ${file.name}`}
                                className="p-1 text-gray-400 hover:text-red-500 disabled:opacity-30"
                            >
                                <XMarkIcon className="w-4 h-4" />
                            </button>
                        </div>
                    </li>
                ))}
            </ul>

            {error && <p className="mt-2 text-xs text-red-600">{error}</p>}

            <div className="flex items-center gap-2 mt-3">
                <button
                    type="button"
                    onClick={onConfirm}
                    disabled={busy || files.length === 0}
                    className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                >
                    {busy && <div className="w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin" />}
                    {busy ? busyLabel : files.length > 1 ? 'Attach as one PDF' : 'Attach'}
                </button>
                <button
                    type="button"
                    onClick={onAddMore}
                    disabled={busy}
                    className="flex items-center gap-1 px-2.5 py-1.5 text-xs text-blue-600 hover:text-blue-800 disabled:opacity-50"
                >
                    <PlusIcon className="w-3.5 h-3.5" />
                    Add more
                </button>
                <button
                    type="button"
                    onClick={onCancel}
                    disabled={busy}
                    className="px-2.5 py-1.5 text-xs text-gray-500 hover:text-gray-700 disabled:opacity-50"
                >
                    Cancel
                </button>
            </div>
        </div>
    )
}

function formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}
