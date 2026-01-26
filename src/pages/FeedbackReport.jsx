import { useState, useMemo } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth, parseISO } from 'date-fns'
import { supabase } from '../lib/supabase'
import Navigation from '../components/shared/Navigation'
import { ChevronUpIcon, ChevronDownIcon } from '@heroicons/react/24/outline'
import { useUpdateIssue } from '../hooks/useIssues'
import { useSites } from '../hooks/useTickets' // Re-using hooks
import { useAuth } from '../hooks/useAuth'
import FeedbackModal from '../components/tickets/FeedbackModal'
import DateRangeFilter from '../components/tickets/DateRangeFilter'
import SiteFilter from '../components/tickets/SiteFilter'

// Rating emoji display - matches the database enum: 'Good', 'Ok', 'Bad'
const RATING_DISPLAY = {
    'Good': { emoji: '😊', label: 'Good', color: 'text-green-600', bg: 'bg-green-100', activeColor: 'text-green-500' },
    'Ok': { emoji: '😐', label: 'Ok', color: 'text-yellow-600', bg: 'bg-yellow-100', activeColor: 'text-yellow-500' },
    'Bad': { emoji: '☹️', label: 'Bad', color: 'text-red-600', bg: 'bg-red-100', activeColor: 'text-red-500' }
}

const SMILEYS = [
    { value: 'Good', emoji: '😊', activeColor: 'text-green-500', label: 'Good' },
    { value: 'Ok', emoji: '😐', activeColor: 'text-yellow-500', label: 'Ok' },
    { value: 'Bad', emoji: '☹️', activeColor: 'text-red-500', label: 'Bad' }
]

// Inline FeedbackSmileys for the report table - reuses same logic as TicketDetail
function ReportFeedbackSmileys({ issue, userProfile, onRatingClick, isUpdating }) {
    const [hoveredSmiley, setHoveredSmiley] = useState(null)
    const hasRating = issue.rating !== null && issue.rating !== undefined
    const isCreator = issue.ticket?.supervisor_id === userProfile?.employee_id

    // Not the ticket creator - show read-only
    if (!isCreator) {
        return (
            <div className="flex items-center gap-1">
                {SMILEYS.map((s) => (
                    <span
                        key={s.value}
                        className={`text-lg transition-all ${hasRating && issue.rating === s.value
                            ? s.activeColor
                            : 'grayscale opacity-40 cursor-not-allowed'
                            }`}
                        title={hasRating && issue.rating === s.value
                            ? `${s.label}${issue.rating_remarks ? `: ${issue.rating_remarks}` : ''}`
                            : 'Only ticket creator can provide rating'}
                    >
                        {s.emoji}
                    </span>
                ))}
            </div>
        )
    }

    // Is the ticket creator - can interact
    return (
        <div className="flex items-center gap-1">
            {SMILEYS.map((s) => (
                <button
                    key={s.value}
                    onClick={() => onRatingClick(issue)}
                    onMouseEnter={() => setHoveredSmiley(s.value)}
                    onMouseLeave={() => setHoveredSmiley(null)}
                    disabled={isUpdating}
                    className={`text-lg transition-all duration-150 hover:scale-125 cursor-pointer disabled:opacity-50 ${hasRating && issue.rating === s.value
                        ? s.activeColor
                        : hoveredSmiley === s.value
                            ? s.activeColor
                            : hasRating
                                ? 'grayscale opacity-30 hover:grayscale-0 hover:opacity-100'
                                : 'grayscale opacity-50 hover:grayscale-0 hover:opacity-100'
                        }`}
                    title={hasRating ? 'Click to edit rating' : `Click to rate as ${s.label}`}
                >
                    {s.emoji}
                </button>
            ))}
        </div>
    )
}

export default function FeedbackReport() {
    const { userProfile } = useAuth()
    const queryClient = useQueryClient()
    const updateIssue = useUpdateIssue()
    const { data: sites = [] } = useSites()

    const [sortConfig, setSortConfig] = useState({ key: 'created_at', direction: 'desc' })

    // Filters State
    const [dateRange, setDateRange] = useState({
        start: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
        end: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
    })

    const [filters, setFilters] = useState({
        site: '',
        vehicle_number: ''
    })

    const [modalOpen, setModalOpen] = useState(false)
    const [selectedIssue, setSelectedIssue] = useState(null)


    // Fetch issues with feedback
    const { data: feedbackData = [], isLoading, error: queryError } = useQuery({
        queryKey: ['feedback-report'],
        queryFn: async () => {
            console.log('Fetching feedback data...')
            const { data, error } = await supabase
                .from('issues')
                .select(`
                    id,
                    issue_number,
                    description,
                    category,
                    severity,
                    status,
                    created_at,
                    rating,
                    rating_remarks,
                    rated_at,
                    ticket_id,
                    ticket:ticket_id (
                        ticket_number,
                        vehicle_number,
                        site,
                        supervisor_id
                    )
                `)
                .eq('status', 'Done')
                .order('created_at', { ascending: false })

            console.log('Feedback query result:', { data, error })
            if (error) {
                console.error('Feedback query error:', error)
                throw error
            }
            return data || []
        }
    })

    // Debug: log the data
    console.log('feedbackData:', feedbackData, 'isLoading:', isLoading, 'error:', queryError)

    // Apply filters and sorting
    const filteredAndSortedData = useMemo(() => {
        let result = [...feedbackData]

        // Apply filters
        result = result.filter(issue => {
            // Date Range
            const issueDate = format(parseISO(issue.created_at), 'yyyy-MM-dd')
            if (issueDate < dateRange.start || issueDate > dateRange.end) return false

            // Site
            if (filters.site && issue.ticket?.site !== filters.site) return false

            // Vehicle
            if (filters.vehicle_number) {
                const vehicle = issue.ticket?.vehicle_number || ''
                if (!vehicle.toLowerCase().includes(filters.vehicle_number.toLowerCase())) return false
            }

            return true
        })

        // Apply sorting
        result.sort((a, b) => {
            let aValue = a[sortConfig.key]
            let bValue = b[sortConfig.key]

            // Handle nested fields
            if (sortConfig.key === 'ticket_number') {
                aValue = a.ticket?.ticket_number
                bValue = b.ticket?.ticket_number
            } else if (sortConfig.key === 'vehicle_number') {
                aValue = a.ticket?.vehicle_number || ''
                bValue = b.ticket?.vehicle_number || ''
            } else if (sortConfig.key === 'supervisor_name') {
                aValue = a.ticket?.supervisor_id || ''
                bValue = b.ticket?.supervisor_id || ''
            }

            // Handle dates
            if (sortConfig.key === 'created_at' || sortConfig.key === 'rated_at') {
                aValue = aValue ? new Date(aValue).getTime() : 0
                bValue = bValue ? new Date(bValue).getTime() : 0
            }

            // Handle nulls
            if (aValue === null || aValue === undefined) aValue = ''
            if (bValue === null || bValue === undefined) bValue = ''

            if (aValue < bValue) return sortConfig.direction === 'asc' ? -1 : 1
            if (aValue > bValue) return sortConfig.direction === 'asc' ? 1 : -1
            return 0
        })

        return result
    }, [feedbackData, filters, sortConfig, dateRange])

    const handleSort = (key) => {
        setSortConfig(prev => ({
            key,
            direction: prev.key === key && prev.direction === 'asc' ? 'desc' : 'asc'
        }))
    }

    const clearFilters = () => {
        setFilters({ site: '', vehicle_number: '' })
    }

    const hasActiveFilters = filters.site || filters.vehicle_number

    // Rating handlers
    const handleRatingClick = (issue) => {
        setSelectedIssue(issue)
        setModalOpen(true)
    }

    const handleRatingSubmit = (feedbackData) => {
        if (!selectedIssue) return
        updateIssue.mutate({
            id: selectedIssue.id,
            updates: {
                rating: feedbackData.rating,
                rating_remarks: feedbackData.rating_remarks,
                rated_at: new Date().toISOString()
            },
            userId: userProfile?.id,
            oldData: selectedIssue
        }, {
            onSuccess: () => {
                queryClient.invalidateQueries({ queryKey: ['feedback-report'] })
                setModalOpen(false)
                setSelectedIssue(null)
            }
        })
    }

    const SortIcon = ({ column }) => {
        if (sortConfig.key !== column) {
            return <span className="text-gray-300 ml-1">↕</span>
        }
        return sortConfig.direction === 'asc'
            ? <ChevronUpIcon className="w-4 h-4 ml-1 inline" />
            : <ChevronDownIcon className="w-4 h-4 ml-1 inline" />
    }

    const columns = [
        { key: 'issue_number', label: 'Issue ID', sortable: true },
        { key: 'vehicle_number', label: 'Vehicle', sortable: true },
        { key: 'description', label: 'Description', sortable: true },
        { key: 'category', label: 'Category', sortable: true },
        { key: 'severity', label: 'Severity', sortable: true },
        { key: 'created_at', label: 'Created Date', sortable: true },
        { key: 'ticket_number', label: 'Ticket ID', sortable: true },
        { key: 'supervisor_name', label: 'Ticket Creator', sortable: true },
        { key: 'rating', label: 'Rating', sortable: true },
        { key: 'rating_remarks', label: 'Comment', sortable: false },
        { key: 'rated_at', label: 'Rating Date', sortable: true },
    ]

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Feedback Report' }]} />

            {/* Header */}
            <div className="bg-white border-b">
                <div className="max-w-full mx-auto px-4 sm:px-6 py-4">
                    <div className="flex flex-col gap-4">
                        <div className="flex justify-between items-center">
                            <div>
                                <h1 className="text-2xl font-bold text-gray-900">Feedback Report</h1>
                                <p className="text-sm text-gray-600 mt-1">
                                    {filteredAndSortedData.length} feedback records
                                </p>
                            </div>
                        </div>

                        {/* Filter Bar */}
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
            </div>

            {/* Table */}
            <div className="max-w-full mx-auto px-4 sm:px-6 py-6">
                <div className="bg-white rounded-lg shadow overflow-hidden">
                    <div className="overflow-x-auto">
                        <table className="min-w-full divide-y divide-gray-200">
                            <thead className="bg-gray-50">
                                <tr>
                                    {columns.map(col => (
                                        <th
                                            key={col.key}
                                            onClick={() => col.sortable && handleSort(col.key)}
                                            className={`px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider whitespace-nowrap ${col.sortable ? 'cursor-pointer hover:bg-gray-100 select-none' : ''
                                                }`}
                                        >
                                            {col.label}
                                            {col.sortable && <SortIcon column={col.key} />}
                                        </th>
                                    ))}
                                </tr>
                            </thead>
                            <tbody className="bg-white divide-y divide-gray-200">
                                {isLoading ? (
                                    <tr>
                                        <td colSpan={columns.length} className="px-4 py-12 text-center text-gray-500">
                                            Loading...
                                        </td>
                                    </tr>
                                ) : filteredAndSortedData.length === 0 ? (
                                    <tr>
                                        <td colSpan={columns.length} className="px-4 py-12 text-center text-gray-500">
                                            No feedback records found
                                        </td>
                                    </tr>
                                ) : (
                                    filteredAndSortedData.map((row) => (
                                        <tr key={row.id} className="hover:bg-gray-50">
                                            <td className="px-4 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                                                {row.issue_number}
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                                                {row.ticket?.vehicle_number || '-'}
                                            </td>
                                            <td className="px-4 py-4 text-sm text-gray-700 max-w-xs truncate" title={row.description}>
                                                {row.description}
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                                                {row.category}
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm">
                                                <span className={`px-2 py-1 rounded-full text-xs font-medium ${row.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-600'
                                                    }`}>
                                                    {row.severity}
                                                </span>
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                                                {row.created_at ? format(new Date(row.created_at), 'MMM d, yyyy') : '-'}
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm">
                                                <Link
                                                    to={`/tickets/${row.ticket_id}`}
                                                    className="text-blue-600 hover:underline font-medium"
                                                >
                                                    #{row.ticket?.ticket_number}
                                                </Link>
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-700">
                                                {row.ticket?.supervisor_id || '-'}
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm">
                                                <ReportFeedbackSmileys
                                                    issue={row}
                                                    userProfile={userProfile}
                                                    onRatingClick={handleRatingClick}
                                                    isUpdating={updateIssue.isPending}
                                                />
                                            </td>
                                            <td className="px-4 py-4 text-sm text-gray-600 max-w-xs truncate" title={row.rating_remarks || ''}>
                                                {row.rating_remarks || '-'}
                                            </td>
                                            <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                                                {row.rated_at ? format(new Date(row.rated_at), 'MMM d, yyyy') : '-'}
                                            </td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            {/* Rating Modal */}
            <FeedbackModal
                isOpen={modalOpen}
                onClose={() => {
                    setModalOpen(false)
                    setSelectedIssue(null)
                }}
                onSubmit={handleRatingSubmit}
                isLoading={updateIssue.isPending}
                issueDescription={selectedIssue?.description || ''}
                initialRating={selectedIssue?.rating}
                initialRemarks={selectedIssue?.rating_remarks}
            />
        </div>
    )
}
