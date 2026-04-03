import { useState, useRef } from 'react'
import { supabase } from '../../lib/supabase'

export default function PhotoUpload({ onPhotosChange, maxPhotos = 5 }) {
  const [photos, setPhotos] = useState([])
  const [uploading, setUploading] = useState(false)
  const [uploadProgress, setUploadProgress] = useState({})
  const fileInputRef = useRef(null)
  const cameraInputRef = useRef(null)

  const handleFileSelect = async (e, source = 'gallery') => {
    const files = Array.from(e.target.files || [])

    if (photos.length + files.length > maxPhotos) {
      alert(`You can only upload up to ${maxPhotos} photos`)
      return
    }

    // Validate file types and sizes
    const validFiles = files.filter(file => {
      const isImage = file.type.startsWith('image/')
      const isUnder10MB = file.size <= 10 * 1024 * 1024 // 10MB limit

      if (!isImage) {
        alert(`${file.name} is not an image file`)
        return false
      }
      if (!isUnder10MB) {
        alert(`${file.name} is larger than 10MB`)
        return false
      }
      return true
    })

    if (validFiles.length === 0) return

    setUploading(true)

    try {
      const uploadPromises = validFiles.map(async (file, index) => {
        const tempId = `temp-${Date.now()}-${index}`

        // Add placeholder
        setPhotos(prev => [...prev, {
          id: tempId,
          file,
          url: null,
          preview: URL.createObjectURL(file),
          uploading: true
        }])

        setUploadProgress(prev => ({ ...prev, [tempId]: 0 }))

        try {
          // Upload to Supabase Edge Function
          const formData = new FormData()
          formData.append('file', file)

          const { data: { session } } = await supabase.auth.getSession()

          const response = await fetch(
            `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/upload-to-drive`,
            {
              method: 'POST',
              headers: {
                'Authorization': `Bearer ${session?.access_token}`,
              },
              body: formData,
            }
          )

          if (!response.ok) {
            throw new Error('Upload failed')
          }

          const result = await response.json()

          // Update photo with actual URL
          setPhotos(prev => prev.map(p =>
            p.id === tempId
              ? { ...p, id: result.fileId, url: result.url, uploading: false }
              : p
          ))

          setUploadProgress(prev => {
            const newProgress = { ...prev }
            delete newProgress[tempId]
            return newProgress
          })

          return result.url

        } catch (error) {
          console.error('Upload error:', error)
          // Remove failed upload
          setPhotos(prev => prev.filter(p => p.id !== tempId))
          setUploadProgress(prev => {
            const newProgress = { ...prev }
            delete newProgress[tempId]
            return newProgress
          })
          throw error
        }
      })

      const uploadedUrls = await Promise.all(uploadPromises)

      // Notify parent component
      const allUrls = [...photos.map(p => p.url), ...uploadedUrls].filter(Boolean)
      onPhotosChange(allUrls)

    } catch (error) {
      console.error('Error uploading photos:', error)
      alert('Failed to upload some photos. Please try again.')
    } finally {
      setUploading(false)
    }
  }

  const removePhoto = (photoId) => {
    setPhotos(prev => {
      const updated = prev.filter(p => p.id !== photoId)
      const urls = updated.map(p => p.url).filter(Boolean)
      onPhotosChange(urls)
      return updated
    })
  }

  const openGallery = () => {
    fileInputRef.current?.click()
  }

  const openCamera = () => {
    cameraInputRef.current?.click()
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <label className="block text-sm font-medium text-gray-700">
          Photos ({photos.length}/{maxPhotos})
        </label>
        <div className="flex gap-2">
          {photos.length < maxPhotos && (
            <>
              <button
                type="button"
                onClick={openCamera}
                disabled={uploading}
                className="flex items-center gap-1 px-3 py-1.5 text-xs text-blue-600 hover:text-blue-700 font-medium border border-blue-300 rounded-lg hover:bg-blue-50 disabled:opacity-50"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 9a2 2 0 012-2h.93a2 2 0 001.664-.89l.812-1.22A2 2 0 0110.07 4h3.86a2 2 0 011.664.89l.812 1.22A2 2 0 0018.07 7H19a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2V9z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 13a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                Camera
              </button>
              <button
                type="button"
                onClick={openGallery}
                disabled={uploading}
                className="flex items-center gap-1 px-3 py-1.5 text-xs text-blue-600 hover:text-blue-700 font-medium border border-blue-300 rounded-lg hover:bg-blue-50 disabled:opacity-50"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                Gallery
              </button>
            </>
          )}
        </div>
      </div>

      {/* Hidden file inputs */}
      <input
        ref={fileInputRef}
        type="file"
        accept="image/*"
        multiple
        onChange={(e) => handleFileSelect(e, 'gallery')}
        className="hidden"
      />
      <input
        ref={cameraInputRef}
        type="file"
        accept="image/*"
        capture="environment"
        onChange={(e) => handleFileSelect(e, 'camera')}
        className="hidden"
      />

      {/* Photo Grid */}
      {photos.length > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          {photos.map((photo) => (
            <div key={photo.id} className="relative group">
              <div className="aspect-square rounded-lg overflow-hidden bg-gray-100 border-2 border-gray-300">
                <img
                  src={photo.preview}
                  alt="Upload preview"
                  className="w-full h-full object-cover"
                />
                {photo.uploading && (
                  <div className="absolute inset-0 bg-black bg-opacity-50 flex items-center justify-center">
                    <div className="text-white text-xs font-medium">
                      <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-white mx-auto mb-2"></div>
                      Uploading...
                    </div>
                  </div>
                )}
              </div>
              {!photo.uploading && (
                <button
                  type="button"
                  onClick={() => removePhoto(photo.id)}
                  className="absolute -top-2 -right-2 p-1.5 bg-red-600 text-white rounded-full shadow-lg hover:bg-red-700 transition-colors"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {photos.length === 0 && (
        <div className="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center">
          <svg className="w-12 h-12 mx-auto text-gray-500 mb-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
          <p className="text-sm text-gray-600 mb-1">No photos added</p>
          <p className="text-xs text-gray-600">Use Camera or Gallery buttons to add photos</p>
        </div>
      )}

      <p className="mt-2 text-xs text-gray-600">
        💡 Max {maxPhotos} photos, up to 10MB each. Photos are uploaded to Google Drive.
      </p>
    </div>
  )
}
