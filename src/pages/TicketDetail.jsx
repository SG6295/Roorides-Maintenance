import { useParams, useNavigate, Link } from 'react-router-dom'
import { format } from 'date-fns'
import { useAuth } from '../hooks/useAuth'
import { useTicket, useUpdateTicket } from '../hooks/useTickets'
import { useState } from 'react'

export default function TicketDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { userProfile } = useAuth()
  const { data: ticket, isLoading } = useTicket(id)
  const updateTicket = useUpdateTicket()
  const [isEditing, setIsEditing] = useState(false)
  const [editData, setEditData] = useState({})

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-gray-600">Loading ticket...</div>
      </div>
    )
  }

  if (!ticket) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-600 mb-4">Ticket not found</p>
          <Link to="/tickets" className="text-blue-600 hover:text-blue-800">
            ← Back to tickets
          </Link>
        </div>
      </div>
    )
  }

  const handleUpdate = async () => {
    try {
      await updateTicket.mutateAsync({ id: ticket.id, updates: editData })
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
      {/* Header */}
      <div className="bg-white shadow-sm sticky top-0 z-10">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <button
                onClick={() => navigate('/tickets')}
                className="text-gray-600 hover:text-gray-900"
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
                <span className={`px-3 py-1 rounded text-sm ${
                  ticket.impact === 'Major'
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
              {ticket.completion_sla_status === 'Violated' && (
                <span className="px-3 py-1 rounded text-sm bg-red-100 text-red-800">
                  ⚠️ SLA Violated
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
                </div>
              ) : (
                <div className="space-y-4">
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Status
                      </label>
                      <select
                        value={editData.status || ''}
                        onChange={(e) => setEditData({ ...editData, status: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      >
                        <option value="Pending">Pending</option>
                        <option value="Team Assigned">Team Assigned</option>
                        <option value="Completed">Completed</option>
                        <option value="Rejected">Rejected</option>
                      </select>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Impact
                      </label>
                      <select
                        value={editData.impact || ''}
                        onChange={(e) => setEditData({ ...editData, impact: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      >
                        <option value="">Select impact</option>
                        <option value="Minor">Minor</option>
                        <option value="Major">Major</option>
                      </select>
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
                      <label className="block text-sm font-medium text-gray-700 mb-1">
                        Work Type
                      </label>
                      <select
                        value={editData.work_type || ''}
                        onChange={(e) => setEditData({ ...editData, work_type: e.target.value })}
                        className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                      >
                        <option value="">Select work type</option>
                        <option value="In House">In House</option>
                        <option value="Outsource">Outsource</option>
                      </select>
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

                  <div className="flex gap-3">
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
