import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useCreateTicket, useSites, useVehicles } from '../../hooks/useTickets'
import Navigation from '../shared/Navigation'

export default function TicketForm() {
  const { userProfile } = useAuth()
  const navigate = useNavigate()
  const [selectedSite, setSelectedSite] = useState(userProfile?.site || '')

  const { data: sites = [] } = useSites()
  const { data: vehicles = [] } = useVehicles(selectedSite)
  const createTicket = useCreateTicket()

  const {
    register,
    handleSubmit,
    formState: { errors },
    watch,
  } = useForm({
    defaultValues: {
      site: userProfile?.site || '',
      supervisor_name: userProfile?.name || '',
      supervisor_id: userProfile?.employee_id || '',
      supervisor_contact: userProfile?.contact || '',
    },
  })

  const watchSite = watch('site')

  // Update selected site when form changes
  useState(() => {
    if (watchSite) {
      setSelectedSite(watchSite)
    }
  }, [watchSite])

  const onSubmit = async (data) => {
    try {
      // Filter out empty photo links
      const validPhotoLinks = photoLinks.filter(link => link.trim() !== '')

      const ticketData = {
        ...data,
        photos: validPhotoLinks.length > 0 ? validPhotoLinks : null
      }

      await createTicket.mutateAsync(ticketData)
      alert('Ticket submitted successfully!')
      navigate('/tickets')
    } catch (error) {
      console.error('Error creating ticket:', error)
      alert('Failed to submit ticket. Please try again.')
    }
  }

  const categories = ['Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS/Camera', 'Other']

  const [photoLinks, setPhotoLinks] = useState([''])

  const addPhotoLink = () => {
    if (photoLinks.length < 5) {
      setPhotoLinks([...photoLinks, ''])
    }
  }

  const updatePhotoLink = (index, value) => {
    const newLinks = [...photoLinks]
    newLinks[index] = value
    setPhotoLinks(newLinks)
  }

  const removePhotoLink = (index) => {
    const newLinks = photoLinks.filter((_, i) => i !== index)
    setPhotoLinks(newLinks.length === 0 ? [''] : newLinks)
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation
        breadcrumbs={[
          { label: 'Tickets', href: '/tickets' },
          { label: 'New Ticket' },
        ]}
      />

      {/* Header with Back Button */}
      <div className="bg-white border-b">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex items-center">
            <button
              onClick={() => navigate(-1)}
              className="mr-4 text-gray-600 hover:text-gray-900 font-medium"
            >
              ← Back
            </button>
            <h1 className="text-xl font-bold text-gray-900">New Ticket</h1>
          </div>
        </div>
      </div>

      {/* Form */}
      <div className="max-w-3xl mx-auto px-4 sm:px-6 py-6">
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
          {/* Site */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Site <span className="text-red-500">*</span>
            </label>
            <select
              {...register('site', { required: 'Site is required' })}
              disabled={userProfile?.role === 'supervisor'}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100"
            >
              <option value="">Select site</option>
              {sites.map((site) => (
                <option key={site.id} value={site.name}>
                  {site.name}
                </option>
              ))}
            </select>
            {errors.site && (
              <p className="mt-1 text-sm text-red-600">{errors.site.message}</p>
            )}
          </div>

          {/* Vehicle Number */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Vehicle Number <span className="text-red-500">*</span>
            </label>
            <select
              {...register('vehicle_number', { required: 'Vehicle number is required' })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">Select vehicle</option>
              {vehicles.map((vehicle) => (
                <option key={vehicle.id} value={vehicle.number}>
                  {vehicle.number} {vehicle.type && `(${vehicle.type})`}
                </option>
              ))}
            </select>
            {errors.vehicle_number && (
              <p className="mt-1 text-sm text-red-600">{errors.vehicle_number.message}</p>
            )}
          </div>

          {/* Category */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Category <span className="text-red-500">*</span>
            </label>
            <select
              {...register('category', { required: 'Category is required' })}
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">Select category</option>
              {categories.map((cat) => (
                <option key={cat} value={cat}>
                  {cat}
                </option>
              ))}
            </select>
            {errors.category && (
              <p className="mt-1 text-sm text-red-600">{errors.category.message}</p>
            )}
          </div>

          {/* Complaint */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Complaint / Issue <span className="text-red-500">*</span>
            </label>
            <textarea
              {...register('complaint', { required: 'Complaint is required' })}
              rows={4}
              placeholder="Describe the issue in detail..."
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
            {errors.complaint && (
              <p className="mt-1 text-sm text-red-600">{errors.complaint.message}</p>
            )}
          </div>

          {/* Remarks (Optional) */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Additional Remarks
            </label>
            <textarea
              {...register('remarks')}
              rows={3}
              placeholder="Any additional information..."
              className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          {/* Supervisor Info (Auto-filled, read-only) */}
          <div className="bg-gray-50 rounded-lg p-4 space-y-3">
            <h3 className="text-sm font-medium text-gray-700">Supervisor Information</h3>

            <div>
              <label className="block text-xs text-gray-500 mb-1">Name</label>
              <input
                {...register('supervisor_name')}
                readOnly
                className="w-full px-3 py-2 bg-white border border-gray-200 rounded text-sm"
              />
            </div>

            <div>
              <label className="block text-xs text-gray-500 mb-1">Employee ID</label>
              <input
                {...register('supervisor_id')}
                readOnly
                className="w-full px-3 py-2 bg-white border border-gray-200 rounded text-sm"
              />
            </div>

            <div>
              <label className="block text-xs text-gray-500 mb-1">Contact</label>
              <input
                {...register('supervisor_contact')}
                placeholder="Phone number (optional)"
                className="w-full px-3 py-2 bg-white border border-gray-200 rounded text-sm"
              />
            </div>
          </div>

          {/* Photo Links (Google Drive) */}
          <div>
            <div className="flex items-center justify-between mb-3">
              <label className="block text-sm font-medium text-gray-700">
                Photo Links (Google Drive)
              </label>
              {photoLinks.length < 5 && (
                <button
                  type="button"
                  onClick={addPhotoLink}
                  className="text-sm text-blue-600 hover:text-blue-700 font-medium flex items-center gap-1"
                >
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                  </svg>
                  Add Photo Link
                </button>
              )}
            </div>

            <div className="space-y-3">
              {photoLinks.map((link, index) => (
                <div key={index} className="flex gap-2">
                  <div className="flex-1 relative">
                    <input
                      type="url"
                      value={link}
                      onChange={(e) => updatePhotoLink(index, e.target.value)}
                      placeholder="https://drive.google.com/file/d/..."
                      className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent pr-10"
                    />
                    <svg className="w-5 h-5 text-gray-400 absolute right-3 top-1/2 -translate-y-1/2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                    </svg>
                  </div>
                  {photoLinks.length > 1 && (
                    <button
                      type="button"
                      onClick={() => removePhotoLink(index)}
                      className="p-3 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                      title="Remove photo link"
                    >
                      <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                    </button>
                  )}
                </div>
              ))}
            </div>

            <p className="mt-2 text-xs text-gray-500">
              💡 Upload photos to Google Drive and paste the shareable link here (Max 5 photos)
            </p>
          </div>

          {/* Submit Button */}
          <div className="sticky bottom-0 bg-white py-4 -mx-4 px-4 border-t border-gray-200">
            <button
              type="submit"
              disabled={createTicket.isPending}
              className="w-full bg-blue-600 text-white py-3 px-4 rounded-lg font-medium hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {createTicket.isPending ? 'Submitting...' : 'Submit Ticket'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
