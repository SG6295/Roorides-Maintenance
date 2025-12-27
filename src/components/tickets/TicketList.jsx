import { Link } from 'react-router-dom'
import { format } from 'date-fns'
import { TicketListSkeleton } from '../shared/LoadingSkeleton'

export default function TicketList({ tickets, loading }) {
  if (loading) {
    return <TicketListSkeleton count={5} />
  }

  if (!tickets || tickets.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow p-12 text-center">
        <div className="max-w-sm mx-auto">
          <svg className="w-16 h-16 mx-auto text-gray-300 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
          <p className="text-gray-600 mb-2 text-lg font-medium">No tickets found</p>
          <p className="text-sm text-gray-500 mb-4">Try adjusting your filters or create a new ticket</p>
          <Link to="/tickets/new" className="inline-block bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700">
            + Create Ticket
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {tickets.map((ticket) => (
        <Link
          key={ticket.id}
          to={`/tickets/${ticket.id}`}
          className="block bg-white rounded-lg shadow card-hover p-5 active:scale-[0.99] transition-transform"
        >
          <div className="flex justify-between items-start mb-3">
            <div className="flex-1 min-w-0 pr-2">
              <div className="flex items-center gap-2 mb-2 flex-wrap">
                <span className="font-semibold text-gray-900 text-base">
                  #{ticket.ticket_number}
                </span>
                <StatusBadge status={ticket.status} />
                {ticket.completion_sla_status === 'Violated' && (
                  <span className="text-xs bg-red-100 text-red-800 px-2 py-1 rounded font-medium">
                    ⚠️ SLA
                  </span>
                )}
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-2">
                {ticket.vehicle_number}
              </h3>
              <p className="text-sm text-gray-600 line-clamp-2 leading-relaxed">
                {ticket.complaint}
              </p>
            </div>
          </div>

          <div className="flex flex-wrap gap-2 text-xs text-gray-500 mt-4 pt-3 border-t border-gray-100">
            <span className="bg-gray-100 px-2.5 py-1.5 rounded font-medium">
              {ticket.category}
            </span>
            <span className="bg-gray-100 px-2.5 py-1.5 rounded font-medium">
              {ticket.site}
            </span>
            {ticket.impact && (
              <span className={`px-2.5 py-1.5 rounded font-medium ${
                ticket.impact === 'Major'
                  ? 'bg-orange-100 text-orange-800'
                  : 'bg-blue-100 text-blue-800'
              }`}>
                {ticket.impact}
              </span>
            )}
            <span className="ml-auto text-gray-400">
              {format(new Date(ticket.created_at), 'MMM d, yyyy')}
            </span>
          </div>
        </Link>
      ))}
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
    <span className={`text-xs px-2 py-0.5 rounded ${colors[status] || 'bg-gray-100 text-gray-800'}`}>
      {status}
    </span>
  )
}
