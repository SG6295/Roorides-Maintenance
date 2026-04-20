import { useState, useEffect, useRef } from 'react'
import { useForm, Controller } from 'react-hook-form'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'
import { useCreateTicket, useSites, useVehicles } from '../../hooks/useTickets'
import { useQueryClient } from '@tanstack/react-query'
import Navigation from '../shared/Navigation'
import PhotoUpload from './PhotoUpload'
import SearchableSelect from '../shared/SearchableSelect'
import { logSLAEvent, SLA_EVENTS } from '../../utils/slaLogger'

export default function TicketForm() {
  const { userProfile } = useAuth()
  const navigate = useNavigate()

  const queryClient = useQueryClient()
  const [syncing, setSyncing] = useState(false)

  const {
    register,
    handleSubmit,
    control,
    setValue,
    formState: { errors },
    watch,
  } = useForm({
    defaultValues: {
      site: userProfile?.role === 'supervisor'
        ? (userProfile?.sites?.length === 1 ? userProfile.sites[0].name : '')
        : (userProfile?.site || ''),
      supervisor_name: userProfile?.name || '',
      supervisor_id: userProfile?.employee_id || '',
      supervisor_contact: userProfile?.contact || '',
    },
  })

  const watchSite = watch('site')

  // Clear vehicle selection when site changes
  const prevSiteRef = useRef(null)
  useEffect(() => {
    if (prevSiteRef.current !== null && prevSiteRef.current !== watchSite) {
      setValue('vehicle_number', '')
    }
    prevSiteRef.current = watchSite
  }, [watchSite, setValue])

  const { data: allSites = [] } = useSites()

  // Supervisors only see their assigned sites; others see all
  const isSupervisor = userProfile?.role === 'supervisor'
  const supervisorSites = userProfile?.sites || []
  const availableSites = isSupervisor
    ? allSites.filter(s => supervisorSites.some(us => us.name === s.name))
    : allSites

  const { data: vehicles = [] } = useVehicles(watchSite || null)
  const createTicket = useCreateTicket()

  const handleRefreshVehicles = async () => {
    setSyncing(true)
    try {
      const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/sync-roorides-vehicles`
      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': import.meta.env.VITE_SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${import.meta.env.VITE_SUPABASE_ANON_KEY}`,
        },
        body: JSON.stringify({}),
      })
      const body = await resp.json()
      if (!resp.ok) throw new Error(body?.error || `HTTP ${resp.status}`)
      await queryClient.invalidateQueries({ queryKey: ['vehicles'] })
      alert('Vehicle list refreshed successfully!')
    } catch (err) {
      console.error('Vehicle refresh failed:', err)
      alert(`Could not refresh vehicle list: ${err.message}`)
    } finally {
      setSyncing(false)
    }
  }

  const onSubmit = async (data) => {
    try {
      // Map form fields to DB columns
      const ticketData = {
        site: data.site,
        vehicle_number: data.vehicle_number,
        supervisor_name: data.supervisor_name,
        supervisor_id: data.supervisor_id,
        supervisor_contact: data.supervisor_contact,
        initial_remarks: data.complaint + (data.remarks ? `\n\nAdditional: ${data.remarks}` : ''),
        // Existing fields handled by defaults/triggers: status, created_at, ticket_number
        photos: photoUrls.length > 0 ? photoUrls : null
      }

      // Create ticket and get the new record
      const newTicket = await createTicket.mutateAsync(ticketData)

      // Log SLA Event: CREATED
      if (newTicket?.id) {
        await logSLAEvent(newTicket.id, SLA_EVENTS.CREATED, userProfile.id)
      }

      alert('Ticket submitted successfully!')
      navigate('/tickets')
    } catch (error) {
      console.error('Error creating ticket:', error)
      alert(error.message || 'Failed to submit ticket. Please try again.')
    }
  }

  const [photoUrls, setPhotoUrls] = useState([])

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
            <Controller
              name="site"
              control={control}
              rules={{ required: 'Site is required' }}
              render={({ field: { value, onChange }, fieldState: { error } }) => (
                <SearchableSelect
                  label={<span>Site <span className="text-red-500">*</span></span>}
                  value={value}
                  onChange={onChange}
                  options={availableSites.map(s => ({ value: s.name, label: s.name }))}
                  disabled={isSupervisor && supervisorSites.length <= 1}
                  error={error}
                  placeholder="Type to search site..."
                />
              )}
            />
          </div>

          {/* Vehicle Number */}
          <div>
            <Controller
              name="vehicle_number"
              control={control}
              rules={{ required: 'Vehicle number is required' }}
              render={({ field: { value, onChange }, fieldState: { error } }) => (
                <SearchableSelect
                  label={<span>Vehicle Number <span className="text-red-500">*</span></span>}
                  value={value}
                  onChange={onChange}
                  options={vehicles.map(v => ({
                    value: v.registration_number,
                    label: `${v.registration_number}${v.make ? ` — ${v.make}` : ''}${v.model ? ` ${v.model}` : ''}`
                  }))}
                  error={error}
                  placeholder="Type to search vehicle..."
                />
              )}
            />
            <button
              type="button"
              onClick={handleRefreshVehicles}
              disabled={syncing}
              className="mt-1.5 text-xs text-blue-600 hover:text-blue-800 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {syncing ? 'Refreshing vehicle list...' : "Can't find your vehicle? Refresh list"}
            </button>
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
              <label className="block text-xs text-gray-600 mb-1">Name</label>
              <input
                {...register('supervisor_name')}
                readOnly
                className="w-full px-3 py-2 bg-white border border-gray-300 rounded text-sm"
              />
            </div>

            <div>
              <label className="block text-xs text-gray-600 mb-1">Employee ID</label>
              <input
                {...register('supervisor_id')}
                readOnly
                className="w-full px-3 py-2 bg-white border border-gray-300 rounded text-sm"
              />
            </div>

            <div>
              <label className="block text-xs text-gray-600 mb-1">Contact</label>
              <input
                {...register('supervisor_contact')}
                placeholder="Phone number (optional)"
                className="w-full px-3 py-2 bg-white border border-gray-300 rounded text-sm"
              />
            </div>
          </div>

          {/* Photo Upload */}
          <PhotoUpload onPhotosChange={setPhotoUrls} maxPhotos={5} />

          {/* Submit Button */}
          <div className="sticky bottom-0 bg-white py-4 -mx-4 px-4 border-t border-gray-300">
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
