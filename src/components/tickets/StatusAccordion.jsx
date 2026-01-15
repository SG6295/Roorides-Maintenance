import { useState } from 'react'
import TicketCard from './TicketCard'

export default function StatusAccordion({ tickets, statusCounts, currentDate, assignmentSLADays }) {
  const [openStatuses, setOpenStatuses] = useState({
    'Pending': true,
    'Team Assigned': false,
    'Work in Progress': false,
    'Completed': false,
    'Rejected': false,
  })

  const statuses = [
    { value: 'Pending', label: 'Pending', color: 'text-yellow-700', bgColor: 'bg-yellow-50' },
    { value: 'Team Assigned', label: 'Team Assigned', color: 'text-blue-700', bgColor: 'bg-blue-50' },
    { value: 'Work in Progress', label: 'Work in Progress', color: 'text-purple-700', bgColor: 'bg-purple-50' },
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
                    <TicketCard
                      key={ticket.id}
                      ticket={ticket}
                      currentDate={currentDate}
                      assignmentSLADays={assignmentSLADays}
                    />
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
