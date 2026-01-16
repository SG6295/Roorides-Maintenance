import { useState, useMemo, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth, parseISO } from 'date-fns'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import { useTickets, useSites } from '../hooks/useTickets'
import Navigation from '../components/shared/Navigation'
import StatusAccordion from '../components/tickets/StatusAccordion'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import SiteFilter from '../components/tickets/SiteFilter'
import FilterModal from '../components/tickets/FilterModal'

export default function Tickets() {
  const { userProfile } = useAuth()
  const { data: sites = [] } = useSites()

  // SLA & Timer State
  const [assignmentSLADays, setAssignmentSLADays] = useState(1)
  const [now, setNow] = useState(new Date())

  // Initialize with current month as default
  const [dateRange, setDateRange] = useState({
    start: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
    end: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
  })

  const [filters, setFilters] = useState({
    status: '',
    site: '',
    vehicle_number: '',
    work_type: '',
    impact: '',
    category: '',
  })

  const [isFilterModalOpen, setIsFilterModalOpen] = useState(false)

  // Fetch all tickets (we'll filter by date on client side)
  const { data: allTickets, isLoading, refetch } = useTickets({})

  // Fetch System Settings & Start Timer
  useEffect(() => {
    // 1. Fetch Assignment SLA Threshold
    const fetchSettings = async () => {
      const { data } = await supabase
        .from('system_settings')
        .select('value')
        .eq('key', 'assignment_sla_days')
        .single()

      if (data) {
        setAssignmentSLADays(parseInt(data.value) || 1)
      }
    }
    fetchSettings()

    // 2. Sync timer to next full minute for cleaner updates
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

  // Filter tickets by date range and other filters
  const filteredTickets = useMemo(() => {
    if (!allTickets) return []

    return allTickets.filter((ticket) => {
      // Date range filter
      const ticketDate = format(parseISO(ticket.created_at), 'yyyy-MM-dd')
      if (ticketDate < dateRange.start || ticketDate > dateRange.end) {
        return false
      }

      // Status filter
      if (filters.status && ticket.status !== filters.status) return false

      // Site filter
      if (filters.site && ticket.site !== filters.site) return false

      // Vehicle search
      if (filters.vehicle_number && !ticket.vehicle_number.toLowerCase().includes(filters.vehicle_number.toLowerCase())) {
        return false
      }

      // Work type filter
      if (filters.work_type && ticket.work_type !== filters.work_type) return false

      // Impact filter
      if (filters.impact && ticket.impact !== filters.impact) return false

      // Category filter
      if (filters.category && ticket.category !== filters.category) return false

      return true
    })
  }, [allTickets, dateRange, filters])

  // Calculate status counts
  const statusCounts = useMemo(() => {
    if (!allTickets) return {}

    const counts = {
      total: 0,
      Pending: 0,
      'Team Assigned': 0,
      Completed: 0,
      Rejected: 0,
    }

    allTickets.forEach((ticket) => {
      // Apply date filter for counts
      const ticketDate = format(parseISO(ticket.created_at), 'yyyy-MM-dd')
      if (ticketDate >= dateRange.start && ticketDate <= dateRange.end) {
        counts.total++
        if (ticket.status in counts) {
          counts[ticket.status]++
        }
      }
    })

    return counts
  }, [allTickets, dateRange])

  const handleApplyModalFilters = (modalFilters) => {
    setFilters({ ...filters, ...modalFilters })
  }

  const clearFilters = () => {
    setFilters({
      status: '',
      site: '',
      vehicle_number: '',
      work_type: '',
      impact: '',
      category: '',
    })
  }

  const hasActiveFilters = filters.site || filters.vehicle_number || filters.work_type || filters.impact || filters.category

  const activeFilterCount = [
    filters.work_type,
    filters.impact,
    filters.category,
  ].filter(Boolean).length

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation breadcrumbs={[{ label: 'Tickets' }]} />

      {/* Header */}
      <div className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex justify-between items-center gap-3">
            <div className="flex-1 min-w-0">
              <h1 className="text-2xl font-bold text-gray-900">Tickets</h1>
              <p className="text-sm text-gray-600 mt-1">
                {filteredTickets.length} ticket{filteredTickets.length !== 1 ? 's' : ''} found
              </p>
            </div>
            <Link
              to="/tickets/new"
              className="bg-blue-600 text-white px-5 py-2.5 rounded-lg font-medium hover:bg-blue-700 active:bg-blue-800 transition-colors min-h-[48px] flex items-center whitespace-nowrap shadow-sm"
            >
              + New
            </Link>
          </div>
        </div>
      </div>

      {/* Filters Bar - Mobile Optimized */}
      <div className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex flex-wrap gap-2">
            {/* Date Range Filter */}
            <DateRangeFilter dateRange={dateRange} onDateRangeChange={setDateRange} />

            {/* Site Filter */}
            <SiteFilter
              sites={sites}
              selectedSite={filters.site}
              onSiteChange={(site) => setFilters({ ...filters, site })}
            />

            {/* Vehicle Search */}
            <input
              type="text"
              placeholder="Search vehicle..."
              value={filters.vehicle_number}
              onChange={(e) => setFilters({ ...filters, vehicle_number: e.target.value })}
              className="px-4 py-2.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 min-w-[160px] sm:min-w-[200px] min-h-[48px] flex-1 sm:flex-none"
            />

            {/* More Filters Button */}
            <button
              onClick={() => setIsFilterModalOpen(true)}
              className="relative flex items-center gap-2 px-4 py-2.5 text-sm border border-gray-300 rounded-lg bg-white hover:bg-gray-50 min-h-[48px] whitespace-nowrap font-medium"
            >
              <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
              </svg>
              <span>Filters</span>
              {activeFilterCount > 0 && (
                <span className="absolute -top-2 -right-2 bg-blue-600 text-white text-xs font-bold rounded-full w-5 h-5 flex items-center justify-center">
                  {activeFilterCount}
                </span>
              )}
            </button>

            {/* Clear All Button */}
            {hasActiveFilters && (
              <button
                onClick={clearFilters}
                className="px-4 py-2.5 text-sm text-blue-600 hover:text-blue-700 font-medium min-h-[48px] whitespace-nowrap"
              >
                Clear All
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Main Content - Status Accordions with Tickets Inside */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 py-6">
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <div className="text-gray-600">Loading tickets...</div>
          </div>
        ) : filteredTickets.length === 0 ? (
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
        ) : (
          <StatusAccordion
            tickets={filteredTickets}
            statusCounts={statusCounts}
            currentDate={now}
            assignmentSLADays={assignmentSLADays}
            onUpdate={refetch}
          />
        )}
      </div>

      {/* Filter Modal */}
      <FilterModal
        isOpen={isFilterModalOpen}
        onClose={() => setIsFilterModalOpen(false)}
        filters={filters}
        onApplyFilters={handleApplyModalFilters}
      />
    </div>
  )
}
