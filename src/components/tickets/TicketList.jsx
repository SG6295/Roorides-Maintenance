import { Link } from 'react-router-dom'
import { format } from 'date-fns'

export default function TicketList({ tickets, loading }) {
  if (loading) {
    return (
      <div className="text-center py-12">
        <div className="text-gray-600">Loading tickets...</div>
      </div>
    )
  }

  if (!tickets || tickets.length === 0) {
    return (
      <div className="text-center py-12">
        <p className="text-gray-600 mb-4">No tickets found</p>
        <Link to="/tickets/new" className="text-blue-600 hover:text-blue-800">
          Create your first ticket →
        </Link>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {tickets.map((ticket) => (
        <Link
          key={ticket.id}
          to={`/tickets/${ticket.id}`}
          className="block bg-white rounded-lg shadow hover:shadow-md transition-shadow p-4"
        >
          <div className="flex justify-between items-start mb-2">
            <div className="flex-1">
              <div className="flex items-center gap-2 mb-1">
                <span className="font-semibold text-gray-900">
                  #{ticket.ticket_number}
                </span>
                <StatusBadge status={ticket.status} />
                {ticket.completion_sla_status === 'Violated' && (
                  <span className="text-xs bg-red-100 text-red-800 px-2 py-0.5 rounded">
                    SLA Violated
                  </span>
                )}
              </div>
              <h3 className="text-lg font-medium text-gray-900 mb-1">
                {ticket.vehicle_number}
              </h3>
              <p className="text-sm text-gray-600 line-clamp-2">
                {ticket.complaint}
              </p>
            </div>
          </div>

          <div className="flex flex-wrap gap-2 text-xs text-gray-500 mt-3">
            <span className="bg-gray-100 px-2 py-1 rounded">
              {ticket.category}
            </span>
            <span className="bg-gray-100 px-2 py-1 rounded">
              {ticket.site}
            </span>
            {ticket.impact && (
              <span className={`px-2 py-1 rounded ${
                ticket.impact === 'Major'
                  ? 'bg-orange-100 text-orange-800'
                  : 'bg-blue-100 text-blue-800'
              }`}>
                {ticket.impact}
              </span>
            )}
            <span className="ml-auto">
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
