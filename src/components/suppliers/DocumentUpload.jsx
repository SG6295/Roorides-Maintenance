import { useState, useRef } from 'react'
import { uploadToDrive } from '../../lib/googleDrive'
import { combineFilesToPdf, isAccepted } from '../../lib/filesToPdf'
import PendingPdfPanel from '../shared/PendingPdfPanel'

/**
 * Reusable document upload field for the supplier registration form and the
 * job-card outsource invoice.
 * Works both authenticated (app users) and unauthenticated (public form).
 * Uploads to Google Drive via the upload-to-drive edge function.
 *
 * One file uploads directly, as it always has. Two or more are staged in
 * PendingPdfPanel for ordering and combined into a single PDF first — a PAN
 * card or a vendor bill photographed across several pages no longer has to go
 * through an outside image-to-PDF site to be attached in full.
 */
export default function DocumentUpload({ label, required = false, value, onChange, accept = '.pdf,.jpg,.jpeg,.png' }) {
  const [uploading, setUploading] = useState(false)
  const [combining, setCombining] = useState(false)
  const [pending, setPending] = useState([])
  const [error, setError] = useState(null)
  const fileInputRef = useRef(null)

  const upload = async (file) => {
    setUploading(true)
    setError(null)
    try {
      const url = await uploadToDrive(file)
      onChange(url)
      setPending([])
    } catch (err) {
      setError(err.message || 'Upload failed. Please try again.')
    } finally {
      setUploading(false)
    }
  }

  const handleFileSelect = async (e) => {
    const selected = Array.from(e.target.files || [])
    // Reset first so the same file can be re-selected after a failure or removal.
    e.target.value = ''
    if (selected.length === 0) return

    const rejected = selected.find(f => !isAccepted(f))
    if (rejected) {
      setError(`"${rejected.name}" isn't a supported file. Attach a PDF, JPG or PNG.`)
      return
    }
    setError(null)

    // Adding to an existing selection keeps the panel open for ordering.
    if (pending.length > 0) {
      setPending(prev => [...prev, ...selected])
      return
    }
    if (selected.length === 1) {
      await upload(selected[0])
      return
    }
    setPending(selected)
  }

  const handleConfirm = async () => {
    if (pending.length === 0) return
    // Removing files can leave one behind; upload it as-is rather than
    // wrapping a single page in a pointless PDF.
    if (pending.length === 1) {
      await upload(pending[0])
      return
    }
    setError(null)
    setCombining(true)
    try {
      const pdf = await combineFilesToPdf(pending)
      setCombining(false)
      await upload(pdf)
    } catch (err) {
      setCombining(false)
      setError(err.message || 'Could not combine these files.')
    }
  }

  const busy = uploading || combining

  return (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1.5">
        {label}{required && <span className="text-red-500 ml-0.5">*</span>}
      </label>

      <input
        ref={fileInputRef}
        type="file"
        accept={accept}
        multiple
        onChange={handleFileSelect}
        className="hidden"
      />

      {pending.length > 0 ? (
        <PendingPdfPanel
          files={pending}
          onChange={setPending}
          onAddMore={() => fileInputRef.current?.click()}
          onConfirm={handleConfirm}
          onCancel={() => { setPending([]); setError(null) }}
          busy={busy}
          busyLabel={combining ? 'Combining…' : 'Uploading…'}
          error={error}
        />
      ) : value ? (
        <div className="flex items-center gap-2 px-3 py-2.5 bg-green-50 border border-green-200 rounded-lg">
          <svg className="w-4 h-4 text-green-600 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <a
            href={value}
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm text-green-700 truncate hover:underline flex-1"
          >
            File uploaded — click to view
          </a>
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            className="text-xs text-gray-500 hover:text-gray-700 px-2 py-1 border border-gray-300 rounded bg-white"
          >
            Replace
          </button>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={busy}
          className="flex items-center justify-center gap-2 w-full px-4 py-2.5 text-sm text-blue-600 border border-blue-300 border-dashed rounded-lg hover:bg-blue-50 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {busy ? (
            <>
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600" />
              {combining ? 'Combining...' : 'Uploading...'}
            </>
          ) : (
            <>
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
              </svg>
              Add File
            </>
          )}
        </button>
      )}

      {error && pending.length === 0 && <p className="mt-1 text-xs text-red-600">{error}</p>}
      <p className="mt-1 text-xs text-gray-400">
        PDF, JPG or PNG — max 10 MB. Add several pages at once and they'll be combined into one PDF.
      </p>
    </div>
  )
}
