import { useState } from 'react'
import { Link } from 'react-router-dom'
import { format } from 'date-fns'

function StatusBadge({ status }) {
  const colors = {
    'Pending': 'bg-yellow-100 text-yellow-800',
    'Team Assigned': 'bg-blue-100 text-blue-800',
    'Completed': 'bg-green-100 text-green-800',
    'Rejected': 'bg-red-100 text-red-800',
  }

  return (
    <span className={`text-xs px-2 py-0.5 rounded font-medium ${colors[status] || 'bg-gray-100 text-gray-800'}`}>
      {status}
    </span>
  )
}

function TicketCard({ ticket }) {
  return (
    <Link
      to={`/tickets/${ticket.id}`}
      className="block bg-white border border-gray-200 rounded-lg hover:shadow-md transition-shadow p-4"
    >
      <div className="flex justify-between items-start mb-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1 flex-wrap">
            <span className="font-semibold text-gray-900 text-sm">
              #{ticket.ticket_number}
            </span>
            {ticket.completion_sla_status === 'Violated' && (
              <span className="text-xs bg-red-100 text-red-800 px-2 py-0.5 rounded font-medium">
                ⚠️ SLA
              </span>
            )}
          </div>
          <h3 className="text-base font-semibold text-gray-900 mb-1">
            {ticket.vehicle_number}
          </h3>
          <p className="text-sm text-gray-600 line-clamp-2 leading-relaxed">
            {ticket.complaint}
          </p>
        </div>
      </div>

      <div className="flex flex-wrap gap-2 text-xs text-gray-500 mt-3 pt-3 border-t border-gray-100">
        <span className="bg-gray-100 px-2 py-1 rounded font-medium">
          {ticket.category}
        </span>
        <span className="bg-gray-100 px-2 py-1 rounded font-medium">
          {ticket.site}
        </span>
        {ticket.impact && (
          <span className={`px-2 py-1 rounded font-medium ${
            ticket.impact === 'Major'
              ? 'bg-orange-100 text-orange-800'
              : 'bg-blue-100 text-blue-800'
          }`}>
            {ticket.impact}
          </span>
        )}
        <span className="ml-auto text-gray-400">
          {format(new Date(ticket.created_at), 'MMM d')}
        </span>
      </div>
    </Link>
  )
}

export default function StatusAccordion({ tickets, statusCounts }) {
  const [openStatuses, setOpenStatuses] = useState({
    'Pending': true,
    'Team Assigned': false,
    'Completed': false,
    'Rejected': false,
  })

  const statuses = [
    { value: 'Pending', label: 'Pending', color: 'text-yellow-700', bgColor: 'bg-yellow-50' },
    { value: 'Team Assigned', label: 'Team Assigned', color: 'text-blue-700', bgColor: 'bg-blue-50' },
    { value: 'Completed', label: 'Completed', color: 'text-green-700', bgColor: 'bg-green-50' },
    { value: 'Rejected', label: 'Rejected', color: 'text-red-700', bgColor: 'bg-red-50' },
  ]

  const toggleStatus = (label) => {
    setOpenStatuses(prev => ({ ...prev, [label]: !prev[label] }))
  }

  const getTicketsForStatus = (statusValue) => {
    if (!tickets) return []
    return tickets.filter(ticket => ticket.status === statusValue)
  }

  const getCount = (status) => {
    if (!statusCounts) return 0
    return statusCounts[status] || 0
  }

  return (
    <div className="space-y-3">
      {statuses.map((status) => {
        const count = getCount(status.value)
        const isOpen = openStatuses[status.label]
        const statusTickets = getTicketsForStatus(status.value)

        return (
          <div key={status.value} className="bg-white border border-gray-200 rounded-lg overflow-hidden">
            {/* Header */}
            <button
              onClick={() => toggleStatus(status.label)}
              className={`w-full flex items-center justify-between p-4 hover:bg-gray-50 transition-colors ${status.bgColor}`}
            >
              <div className="flex items-center gap-3">
                <svg
                  className={`w-5 h-5 text-gray-500 transition-transform ${isOpen ? 'rotate-90' : ''}`}
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
                </svg>
                <span className={`font-semibold ${status.color} text-base`}>
                  {status.label}
                </span>
              </div>
              <span className="px-3 py-1 text-sm font-bold bg-white rounded-full text-gray-700 border border-gray-200">
                {count}
              </span>
            </button>

            {/* Content - Tickets */}
            {isOpen && (
              <div className="border-t border-gray-200 p-3 space-y-3 bg-gray-50">
                {statusTickets.length > 0 ? (
                  statusTickets.map((ticket) => (
                    <TicketCard key={ticket.id} ticket={ticket} />
                  ))
                ) : (
                  <div className="text-center py-8 text-gray-500 text-sm">
                    No tickets in this status
                  </div>
                )}
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}
