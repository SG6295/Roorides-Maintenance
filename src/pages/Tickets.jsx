import { useState, useMemo, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth } from 'date-fns'
import { useAuth } from '../hooks/useAuth'
import { useTickets } from '../hooks/useTickets'
import { useAllSites } from '../hooks/useSites'
import { formatSiteLabel } from '../utils/siteLabel'
import Navigation from '../components/shared/Navigation'
import StatusAccordion from '../components/tickets/StatusAccordion'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import FilterSelect from '../components/shared/FilterSelect'
import { ArrowDownTrayIcon } from '@heroicons/react/24/outline'
import { exportTicketsToExcel } from '../utils/ticketExport'

export default function Tickets() {
  const { userProfile } = useAuth()
  const canExport = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)
  const [exporting, setExporting] = useState(false)
  // All sites, not just active — a departed school's past tickets must stay filterable.
  const { data: sites = [] } = useAllSites()

  // Timer state. The acceptance SLA threshold used to be fetched here so TicketCard could
  // compute a deadline in JavaScript; the database stamps it now (MAIN-45), so the setting
  // is no longer needed on this page.
  const [now, setNow] = useState(new Date())

  // Initialize with current month as default
  const [dateRange, setDateRange] = useState({
    start: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
    end: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
  })

  // Only keep active filters: status (from accordion logic likely, though not here), site, vehicle
  const [filters, setFilters] = useState({
    status: '',
    site: '',
    vehicle_number: '',
  })


  // The date range is filtered in the database (MAIN-83); site and vehicle stay client-side.
  // isPlaceholderData: the list on screen is still the previous date range's while the new
  // one loads, so Export is disabled until it arrives — otherwise the file would be named
  // for the new range but hold the old range's tickets.
  const { data: allTickets, isLoading, isPlaceholderData } = useTickets({ dateRange })

  // Sync timer to next full minute for cleaner updates
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

  // Filter tickets by the non-date filters
  const filteredTickets = useMemo(() => {
    if (!allTickets) return []

    return allTickets.filter((ticket) => {
      // Status filter
      if (filters.status && ticket.status !== filters.status) return false

      // Site filter
      if (filters.site && ticket.site !== filters.site) return false

      // Vehicle search
      if (filters.vehicle_number && !ticket.vehicle_number.toLowerCase().includes(filters.vehicle_number.toLowerCase())) {
        return false
      }

      return true
    })
  }, [allTickets, filters])

  // Status counts are deliberately not computed here. They used to be, from allTickets
  // with only the date range applied, while the rows came from filteredTickets — so a
  // site or vehicle filter narrowed the list but never its badge (MAIN-82). StatusAccordion
  // counts the tickets it is handed, which makes the badge and the list one computation.

  const clearFilters = () => {
    setFilters({
      status: '',
      site: '',
      vehicle_number: '',
    })
  }

  const hasActiveFilters = filters.site || filters.vehicle_number

  // Exports exactly what is on screen (MAIN-84).
  const handleExport = async () => {
    setExporting(true)
    try {
      await exportTicketsToExcel(filteredTickets, dateRange)
    } catch (err) {
      alert('Export failed: ' + err.message)
    } finally {
      setExporting(false)
    }
  }

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
            <div className="flex items-center gap-2">
              {canExport && (
                <button
                  onClick={handleExport}
                  disabled={exporting || isLoading || isPlaceholderData || filteredTickets.length === 0}
                  className="flex items-center gap-2 px-4 py-2.5 border border-gray-300 rounded-lg bg-white text-gray-700 font-medium hover:bg-gray-50 disabled:opacity-40 transition-colors min-h-[48px] whitespace-nowrap shadow-sm"
                >
                  <ArrowDownTrayIcon className="w-5 h-5" />
                  {exporting ? 'Exporting…' : 'Export'}
                </button>
              )}
              <Link
                to="/tickets/new"
                className="bg-blue-600 text-white px-5 py-2.5 rounded-lg font-medium hover:bg-blue-700 active:bg-blue-800 transition-colors min-h-[48px] flex items-center whitespace-nowrap shadow-sm"
              >
                + New
              </Link>
            </div>
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
            <FilterSelect
              value={filters.site}
              onChange={(site) => setFilters({ ...filters, site })}
              placeholder="All Sites"
              options={sites.map(s => ({ value: s.name, label: formatSiteLabel(s) }))}
            />

            {/* Vehicle Search */}
            <input
              type="text"
              placeholder="Search vehicle..."
              value={filters.vehicle_number}
              onChange={(e) => setFilters({ ...filters, vehicle_number: e.target.value })}
              className="px-4 py-2.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 min-w-[160px] sm:min-w-[200px] min-h-[48px] flex-1 sm:flex-none"
            />


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
              <p className="text-sm text-gray-600 mb-4">Try adjusting your filters or create a new ticket</p>
              <Link to="/tickets/new" className="inline-block bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700">
                + Create Ticket
              </Link>
            </div>
          </div>
        ) : (
          <StatusAccordion
            tickets={filteredTickets}
            currentDate={now}
          />
        )}
      </div>

    </div>
  )
}

