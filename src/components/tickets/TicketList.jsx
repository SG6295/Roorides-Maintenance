import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { TicketListSkeleton } from '../shared/LoadingSkeleton'
import TicketCard from './TicketCard'

export default function TicketList({ tickets, loading, assignmentSLADays = 1 }) {
  // Single timer logic is now optionally passed in or managed locally if needed.
  // Since TicketList might be used in places without the global timer from Tickets.jsx,
  // we can keep the local timer as a fallback or expect it from props.
  // For now, let's keep the local timer to ensure it works standalone.
  const [now, setNow] = useState(new Date())

  useEffect(() => {
    const delay = 60000 - (new Date().getTime() % 60000)
    let interval
    const timeout = setTimeout(() => {
      setNow(new Date())
      interval = setInterval(() => {
        setNow(new Date())
      }, 60000)
    }, delay)

    return () => {
      clearTimeout(timeout)
      if (interval) clearInterval(interval)
    }
  }, [])

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
        <TicketCard
          key={ticket.id}
          ticket={ticket}
          currentDate={now}
          assignmentSLADays={assignmentSLADays}
        />
      ))}
    </div>
  )
}
