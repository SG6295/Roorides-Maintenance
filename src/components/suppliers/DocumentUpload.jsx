import { useState, useRef } from 'react'
import { supabase } from '../../lib/supabase'

/**
 * Reusable document upload field for the supplier registration form.
 * Works both authenticated (app users) and unauthenticated (public form).
 * Uploads to Google Drive via the upload-to-drive edge function.
 */
export default function DocumentUpload({ label, required = false, value, onChange, accept = '.pdf,.jpg,.jpeg,.png' }) {
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState(null)
  const fileInputRef = useRef(null)

  const handleFileSelect = async (e) => {
    const file = e.target.files?.[0]
    if (!file) return

    setUploading(true)
    setError(null)

    try {
      const formData = new FormData()
      formData.append('file', file)

      // Include auth token if a session exists; edge function allows anonymous too
      const { data: { session } } = await supabase.auth.getSession()
      const headers = {}
      if (session?.access_token) {
        headers['Authorization'] = `Bearer ${session.access_token}`
      }

      const response = await fetch(
        `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/upload-to-drive`,
        { method: 'POST', headers, body: formData }
      )

      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        throw new Error(err.error || 'Upload failed')
      }

      const result = await response.json()
      onChange(result.url)
    } catch (err) {
      setError(err.message || 'Upload failed. Please try again.')
    } finally {
      setUploading(false)
      // Reset so the same file can be re-selected after a failure
      e.target.value = ''
    }
  }

  return (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1.5">
        {label}{required && <span className="text-red-500 ml-0.5">*</span>}
      </label>

      <input
        ref={fileInputRef}
        type="file"
        accept={accept}
        onChange={handleFileSelect}
        className="hidden"
      />

      {value ? (
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
          disabled={uploading}
          className="flex items-center justify-center gap-2 w-full px-4 py-2.5 text-sm text-blue-600 border border-blue-300 border-dashed rounded-lg hover:bg-blue-50 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {uploading ? (
            <>
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600" />
              Uploading...
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

      {error && <p className="mt-1 text-xs text-red-600">{error}</p>}
      <p className="mt-1 text-xs text-gray-400">PDF, JPG or PNG — max 10 MB</p>
    </div>
  )
}
