import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { useTickets } from '../hooks/useTickets'
import TicketList from '../components/tickets/TicketList'

export default function Tickets() {
  const { userProfile } = useAuth()
  const [filters, setFilters] = useState({})
  const { data: tickets, isLoading } = useTickets(filters)

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex justify-between items-center">
            <div>
              <h1 className="text-xl font-bold text-gray-900">Tickets</h1>
              {tickets && (
                <p className="text-sm text-gray-600 mt-1">
                  {tickets.length} ticket{tickets.length !== 1 ? 's' : ''} found
                </p>
              )}
            </div>
            <Link
              to="/tickets/new"
              className="bg-blue-600 text-white px-4 py-2 rounded-lg font-medium hover:bg-blue-700"
            >
              + New Ticket
            </Link>
          </div>
        </div>
      </div>

      {/* Filters (Phase 1 - Basic) */}
      <div className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-3">
          <div className="flex gap-3 overflow-x-auto">
            <select
              value={filters.status || ''}
              onChange={(e) => setFilters({ ...filters, status: e.target.value || undefined })}
              className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All Status</option>
              <option value="Pending">Pending</option>
              <option value="Team Assigned">Team Assigned</option>
              <option value="Completed">Completed</option>
              <option value="Rejected">Rejected</option>
            </select>

            <select
              value={filters.category || ''}
              onChange={(e) => setFilters({ ...filters, category: e.target.value || undefined })}
              className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="">All Categories</option>
              <option value="Mechanical">Mechanical</option>
              <option value="Electrical">Electrical</option>
              <option value="Body">Body</option>
              <option value="Tyre">Tyre</option>
              <option value="GPS/Camera">GPS/Camera</option>
              <option value="Other">Other</option>
            </select>

            <input
              type="text"
              placeholder="Search vehicle..."
              value={filters.vehicle_number || ''}
              onChange={(e) => setFilters({ ...filters, vehicle_number: e.target.value || undefined })}
              className="px-3 py-1.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 min-w-[200px]"
            />

            {(filters.status || filters.category || filters.vehicle_number) && (
              <button
                onClick={() => setFilters({})}
                className="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-900"
              >
                Clear filters
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6">
        <TicketList tickets={tickets} loading={isLoading} />
      </div>
    </div>
  )
}
