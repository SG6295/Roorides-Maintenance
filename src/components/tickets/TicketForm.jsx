import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useCreateTicket, useSites, useVehicles } from '../../hooks/useTickets'

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
      await createTicket.mutateAsync(data)
      alert('Ticket submitted successfully!')
      navigate('/tickets')
    } catch (error) {
      console.error('Error creating ticket:', error)
      alert('Failed to submit ticket. Please try again.')
    }
  }

  const categories = ['Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS/Camera', 'Other']

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm sticky top-0 z-10">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex items-center">
            <button
              onClick={() => navigate(-1)}
              className="mr-4 text-gray-600 hover:text-gray-900"
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

          {/* Photo Upload (Phase 1 - Coming Soon) */}
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <p className="text-sm text-blue-800">
              📸 Photo upload coming in next update
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
