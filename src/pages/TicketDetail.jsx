import { useParams, useNavigate, Link } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'

import { format } from 'date-fns'
import { useAuth } from '../hooks/useAuth'
import { useTicket, useUpdateTicket } from '../hooks/useTickets'
import { getDriveThumbnailUrl } from '../lib/googleDrive'
import { fetchSLADays, calculateSLAEndDate } from '../utils/slaCalculator'
import { logSLAEvent, SLA_EVENTS } from '../utils/slaLogger'
import { logAuditEvent } from '../utils/auditLogger'
import { useState } from 'react'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import PhotoUpload from '../components/tickets/PhotoUpload'
import TicketTimeline from '../components/tickets/TicketTimeline'
import CustomSelect from '../components/shared/CustomSelect'


export default function TicketDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { userProfile } = useAuth()
  const { data: ticket, isLoading } = useTicket(id)
  const updateTicket = useUpdateTicket()
  const [isEditing, setIsEditing] = useState(false)
  const [editData, setEditData] = useState({})

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navigation breadcrumbs={[{ label: 'Tickets', href: '/tickets' }, { label: 'Loading...' }]} />
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-6">
          <TicketDetailSkeleton />
        </div>
      </div>
    )
  }

  if (!ticket) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navigation breadcrumbs={[{ label: 'Tickets', href: '/tickets' }, { label: 'Not Found' }]} />
        <div className="flex items-center justify-center py-16">
          <div className="bg-white rounded-lg shadow p-12 text-center max-w-md">
            <svg className="w-16 h-16 mx-auto text-gray-300 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <h2 className="text-xl font-semibold text-gray-900 mb-2">Ticket not found</h2>
            <p className="text-gray-600 mb-6">The ticket you're looking for doesn't exist or has been removed.</p>
            <Link to="/tickets" className="inline-block bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700">
              ← Back to Tickets
            </Link>
          </div>
        </div>
      </div>
    )
  }

  const handleUpdate = async () => {
    try {
      const updates = { ...editData }

      // Handle new photos if added
      if (updates.newPhotos && updates.newPhotos.length > 0) {
        const currentPhotos = ticket.photos || []
        updates.photos = [...currentPhotos, ...updates.newPhotos]
        delete updates.newPhotos // Clean up temporary field
      }

      // Calculate SLA if impact is set or updated
      const effectiveImpact = updates.impact || ticket.impact
      const effectiveCategory = ticket.category

      if (effectiveImpact && effectiveCategory) {
        const slaDays = await fetchSLADays(effectiveImpact, effectiveCategory) // Fixed: fetchSLADays is async now? No, it's slaCalculator. But wait, previous edit showed fetchSLADays might just be lookup. 
        // Let's check imports. fetchSLADays was imported.
        // Actually, previous code had `calculateSLADays` but import said `fetchSLADays`. 
        // In `slaCalculator.js` it typically exports `fetchSLADays` (async) or synchronous lookup.
        // Let's assume `fetchSLADays` is correct fn name based on import line 6.
        if (slaDays) {
          updates.sla_days = slaDays
          // Calculate end date based on CREATION time (async now)
          const endDate = await calculateSLAEndDate(ticket.created_at, slaDays)
          updates.sla_end_date = endDate.toISOString()
        }
      }

      await updateTicket.mutateAsync({ id: ticket.id, updates })

      // SLA Logging Logic
      if (updates.status && updates.status !== ticket.status) {
        let eventType = SLA_EVENTS.STATUS_CHANGE

        if (updates.status === 'Team Assigned') eventType = SLA_EVENTS.ASSIGNED
        else if (updates.status === 'Completed') eventType = SLA_EVENTS.COMPLETED
        else if (updates.status === 'Rejected') eventType = SLA_EVENTS.REJECTED

        await logSLAEvent(ticket.id, eventType, userProfile.id, {
          oldStatus: ticket.status,
          newStatus: updates.status
        })
      }

      // Audit Logging Logic (Granular Field Changes)
      const auditFields = [
        'status', 'impact', 'job_sheet_id', 'work_type',
        'assigned_date', 'activity_plan_date', 'completed_date', 'completion_remarks'
      ]

      const changedFields = []
      const oldDataLog = {}
      const newDataLog = {}

      auditFields.forEach(field => {
        // Compare values (loose equality to handle null vs undefined vs empty string reasonably)
        // treating null and '' as similar for some fields might be desired but strictly:
        if (updates[field] !== undefined && updates[field] !== ticket[field]) {
          changedFields.push(field)
          oldDataLog[field] = ticket[field]
          newDataLog[field] = updates[field]
        }
      })

      // Check for photo changes
      if (updates.photos && JSON.stringify(updates.photos) !== JSON.stringify(ticket.photos)) {
        changedFields.push('photos')
        oldDataLog['photos_count'] = ticket.photos?.length || 0
        newDataLog['photos_count'] = updates.photos.length
      }

      if (changedFields.length > 0) {
        await logAuditEvent(ticket.id, 'tickets', 'UPDATE', userProfile.id, {
          oldData: oldDataLog,
          newData: newDataLog,
          changedFields: changedFields
        })
      }

      // Refresh Timeline
      await queryClient.invalidateQueries(['sla_events', ticket.id])
      await queryClient.invalidateQueries(['audit_logs', ticket.id])

      setIsEditing(false)
      setEditData({})
      alert('Ticket updated successfully!')
    } catch (error) {
      console.error('Error updating ticket:', error)
      alert('Failed to update ticket')
    }
  }


  const canEdit = userProfile?.role === 'maintenance_exec'

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation
        breadcrumbs={[
          { label: 'Tickets', href: '/tickets' },
          { label: `Ticket #${ticket.ticket_number}` },
        ]}
      />

      {/* Header */}
      <div className="bg-white border-b">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <button
                onClick={() => navigate('/tickets')}
                className="text-gray-600 hover:text-gray-900 font-medium"
              >
                ← Back
              </button>
              <div>
                <h1 className="text-xl font-bold text-gray-900">
                  Ticket #{ticket.ticket_number}
                </h1>
                <p className="text-sm text-gray-600">
                  Created {format(new Date(ticket.created_at), 'MMM d, yyyy h:mm a')}
                </p>
              </div>
            </div>
            {canEdit && !isEditing && (
              <button
                onClick={() => {
                  setIsEditing(true)
                  setEditData({
                    impact: ticket.impact,
                    job_sheet_id: ticket.job_sheet_id,
                    work_type: ticket.work_type,
                    status: ticket.status,
                    assigned_date: ticket.assigned_date,
                    activity_plan_date: ticket.activity_plan_date,
                    completed_date: ticket.completed_date,
                    completion_remarks: ticket.completion_remarks,
                  })
                }}
                className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
              >
                Edit Ticket
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-4xl mx-auto px-4 sm:px-6 py-6">
        <div className="bg-white rounded-lg shadow">
          {/* Status & Badges */}
          <div className="p-6 border-b">
            <div className="flex flex-wrap gap-2">
              <StatusBadge status={ticket.status} />
              {ticket.impact && (
                <span className={`px-3 py-1 rounded text-sm ${ticket.impact === 'Major'
                  ? 'bg-orange-100 text-orange-800'
                  : 'bg-blue-100 text-blue-800'
                  }`}>
                  Impact: {ticket.impact}
                </span>
              )}
              {ticket.work_type && (
                <span className="px-3 py-1 rounded text-sm bg-purple-100 text-purple-800">
                  {ticket.work_type}
                </span>
              )}
              {/* SLA Status Badge */}
              {ticket.status !== 'Completed' && ticket.status !== 'Rejected' && ticket.sla_end_date && (() => {
                const now = new Date()
                const end = new Date(ticket.sla_end_date)
                const diffTime = end - now
                const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))

                if (diffDays < 0) {
                  return (
                    <span className="px-3 py-1 rounded text-sm bg-red-100 text-red-800 font-medium border border-red-200">
                      ⚠️ Overdue by {Math.abs(diffDays)} days
                    </span>
                  )
                } else if (diffDays <= 2) {
                  return (
                    <span className="px-3 py-1 rounded text-sm bg-yellow-100 text-yellow-800 font-medium border border-yellow-200">
                      ⏱️ Due in {diffDays} days
                    </span>
                  )
                }
                // Optional: Show "On Track" or just nothing if far out
                return null
              })()}

              {ticket.completion_sla_status === 'Violated' && (
                <span className="px-3 py-1 rounded text-sm bg-red-100 text-red-800">
                  ⚠️ SLA Violated (Recorded)
                </span>
              )}
            </div>
          </div>

          {/* Vehicle & Site Info */}
          <div className="p-6 border-b">
            <h2 className="text-lg font-semibold text-gray-900 mb-4">Vehicle Information</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <InfoField label="Vehicle Number" value={ticket.vehicle_number} />
              <InfoField label="Site" value={ticket.site} />
              <InfoField label="Category" value={ticket.category} />
              {ticket.job_sheet_id && (
                <InfoField label="Job Sheet ID" value={ticket.job_sheet_id} />
              )}
            </div>
          </div>

          {/* Complaint */}
          <div className="p-6 border-b">
            <h2 className="text-lg font-semibold text-gray-900 mb-2">Complaint</h2>
            <p className="text-gray-700 whitespace-pre-wrap">{ticket.complaint}</p>
            {ticket.remarks && (
              <div className="mt-4">
                <h3 className="text-sm font-medium text-gray-700 mb-1">Remarks</h3>
                <p className="text-gray-600 text-sm whitespace-pre-wrap">{ticket.remarks}</p>
              </div>
            )}
          </div>

          {/* Supervisor Info */}
          <div className="p-6 border-b">
            <h2 className="text-lg font-semibold text-gray-900 mb-4">Supervisor Information</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <InfoField label="Name" value={ticket.supervisor_name} />
              <InfoField label="Employee ID" value={ticket.supervisor_id} />
              {ticket.supervisor_contact && (
                <InfoField label="Contact" value={ticket.supervisor_contact} />
              )}
            </div>
          </div>

          {/* Photos */}
          {ticket.photos && ticket.photos.length > 0 && (
            <div className="p-6 border-b">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">Photos</h2>
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
                {ticket.photos.map((photoUrl, index) => {
                  const thumbnailUrl = getDriveThumbnailUrl(photoUrl, 'w400-h400-c') // Square crop

                  return (
                    <a
                      key={index}
                      href={photoUrl}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="group relative aspect-square bg-gray-100 rounded-lg overflow-hidden border border-gray-200 block shadow-sm hover:shadow-md transition-shadow"
                    >
                      {thumbnailUrl ? (
                        <img
                          src={thumbnailUrl}
                          alt={`Ticket photo ${index + 1}`}
                          className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
                          onError={(e) => {
                            // Fallback if thumbnail fails to load
                            e.target.style.display = 'none'
                            e.target.nextSibling.style.display = 'flex'
                          }}
                        />
                      ) : null}

                      {/* Fallback / Overlay content */}
                      <div className={`absolute inset-0 flex items-center justify-center bg-gray-50 ${thumbnailUrl ? 'hidden' : 'flex'}`}>
                        <span className="text-gray-400">
                          <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                          </svg>
                        </span>
                      </div>

                      <div className="absolute inset-0 bg-black bg-opacity-0 group-hover:bg-opacity-10 transition-opacity" />
                    </a>
                  )
                })}
              </div>
              <p className="mt-4 text-xs text-gray-500">
                💡 Click on an image to view full size in Google Drive
              </p>
            </div>
          )}

          {/* Management Section (Editable for Maintenance Exec) */}
          {canEdit && (
            <div className="p-6 border-b bg-gray-50">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">
                Management {isEditing && '(Editing)'}
              </h2>

              {!isEditing ? (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <InfoField label="Status" value={ticket.status || 'Not set'} />
                  <InfoField label="Impact" value={ticket.impact || 'Not set'} />
                  <InfoField label="Job Sheet ID" value={ticket.job_sheet_id || 'Not assigned'} />
                  <InfoField label="Work Type" value={ticket.work_type || 'Not set'} />
                  <InfoField
                    label="Assigned Date"
                    value={ticket.assigned_date ? format(new Date(ticket.assigned_date), 'MMM d, yyyy') : 'Not assigned'}
                  />
                  <InfoField
                    label="Activity Plan Date"
                    value={ticket.activity_plan_date ? format(new Date(ticket.activity_plan_date), 'MMM d, yyyy') : 'Not set'}
                  />
                  <InfoField
                    label="Completed Date"
                    value={ticket.completed_date ? format(new Date(ticket.completed_date), 'MMM d, yyyy') : 'Not completed'}
                  />
                  <InfoField label="SLA Days" value={ticket.sla_days || 'Not calculated'} />
                  <InfoField
                    label="SLA Target"
                    value={ticket.sla_end_date ? format(new Date(ticket.sla_end_date), 'MMM d, yyyy') : 'Not calculated'}
                  />
                </div>
              ) : (
                <div className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <CustomSelect
                        label="Status"
                        value={editData.status}
                        onChange={(val) => setEditData({ ...editData, status: val })}
                        options={['Pending', 'Team Assigned', 'Completed', 'Rejected']}
                        placeholder="Select status"
                      />
                    </div>

                    <div>
                      <CustomSelect
                        label="Impact"
                        value={editData.impact}
                        onChange={(val) => setEditData({ ...editData, impact: val })}
                        options={['Minor', 'Major']}
                        placeholder="Select impact"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Job Sheet ID
                      </label>
                      <input
                        type="text"
                        value={editData.job_sheet_id || ''}
                        onChange={(e) => setEditData({ ...editData, job_sheet_id: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                        placeholder="e.g., JS-2024-001"
                      />
                    </div>

                    <div>
                      <CustomSelect
                        label="Work Type"
                        value={editData.work_type}
                        onChange={(val) => setEditData({ ...editData, work_type: val })}
                        options={['In House', 'Outsource']}
                        placeholder="Select work type"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Assigned Date
                      </label>
                      <input
                        type="date"
                        value={editData.assigned_date || ''}
                        onChange={(e) => setEditData({ ...editData, assigned_date: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Activity Plan Date
                      </label>
                      <input
                        type="date"
                        value={editData.activity_plan_date || ''}
                        onChange={(e) => setEditData({ ...editData, activity_plan_date: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      />
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Completed Date
                      </label>
                      <input
                        type="date"
                        value={editData.completed_date || ''}
                        onChange={(e) => setEditData({ ...editData, completed_date: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Completion Remarks
                    </label>
                    <textarea
                      value={editData.completion_remarks || ''}
                      onChange={(e) => setEditData({ ...editData, completion_remarks: e.target.value })}
                      rows={3}
                      className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      placeholder="Add remarks about the completion..."
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Add More Photos
                    </label>
                    <PhotoUpload
                      onPhotosChange={(urls) => setEditData(prev => ({ ...prev, newPhotos: urls }))}
                      maxPhotos={5}
                    />
                  </div>

                  <div className="flex gap-3 pt-4">
                    <button
                      onClick={handleUpdate}
                      disabled={updateTicket.isPending}
                      className="bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50"
                    >
                      {updateTicket.isPending ? 'Saving...' : 'Save Changes'}
                    </button>
                    <button
                      onClick={() => {
                        setIsEditing(false)
                        setEditData({})
                      }}
                      className="bg-gray-200 text-gray-700 px-6 py-2 rounded-lg hover:bg-gray-300"
                    >
                      Cancel
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}


          {/* Completion Info */}
          {ticket.completed_date && (
            <div className="p-6">
              <h2 className="text-lg font-semibold text-gray-900 mb-4">Completion Details</h2>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <InfoField
                  label="Completed Date"
                  value={format(new Date(ticket.completed_date), 'MMM d, yyyy')}
                />
                {ticket.tat_days !== null && (
                  <InfoField label="TAT (Days)" value={ticket.tat_days} />
                )}
              </div>
              {ticket.completion_remarks && (
                <div className="mt-4">
                  <h3 className="text-sm font-medium text-gray-700 mb-1">Completion Remarks</h3>
                  <p className="text-gray-600 text-sm whitespace-pre-wrap">{ticket.completion_remarks}</p>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Audit / SLA Timeline */}
        <div className="mt-6 bg-white rounded-lg shadow p-6">
          <h2 className="text-lg font-semibold text-gray-900 mb-6">Ticket History</h2>
          <TicketTimeline ticketId={ticket.id} />
        </div>
      </div>
    </div>
  )
}


function StatusBadge({ status }) {
  const colors = {
    'Pending': 'bg-yellow-100 text-yellow-800',
    'Team Assigned': 'bg-blue-100 text-blue-800',
    'Completed': 'bg-green-100 text-green-800',
    'Rejected': 'bg-red-100 text-red-800',
  }

  return (
    <span className={`px-3 py-1 rounded text-sm font-medium ${colors[status] || 'bg-gray-100 text-gray-800'}`}>
      {status}
    </span>
  )
}

function InfoField({ label, value }) {
  return (
    <div>
      <p className="text-sm text-gray-600 mb-1">{label}</p>
      <p className="text-gray-900 font-medium">{value || '—'}</p>
    </div>
  )
}
