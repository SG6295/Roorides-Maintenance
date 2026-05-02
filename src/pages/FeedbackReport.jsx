import { useState, useMemo } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { format, startOfMonth, endOfMonth, parseISO } from 'date-fns'
import { supabase } from '../lib/supabase'
import Navigation from '../components/shared/Navigation'
import { ChevronUpIcon, ChevronDownIcon } from '@heroicons/react/24/outline'
import { useUpdateIssue } from '../hooks/useIssues'
import { useSites } from '../hooks/useTickets'
import { useAuth } from '../hooks/useAuth'
import FeedbackModal from '../components/tickets/FeedbackModal'
import FilterSelect from '../components/shared/FilterSelect'
import DateRangeFilter from '../components/tickets/DateRangeFilter'

const SMILEYS = [
    { value: 'Good', emoji: '😊', activeColor: 'text-green-500', label: 'Good' },
    { value: 'Ok', emoji: '😐', activeColor: 'text-yellow-500', label: 'Ok' },
    { value: 'Bad', emoji: '☹️', activeColor: 'text-red-500', label: 'Bad' }
]

function ReportFeedbackSmileys({ issue, userProfile, onRatingClick, isUpdating }) {
    const [hoveredSmiley, setHoveredSmiley] = useState(null)
    const hasRating = issue.rating !== null && issue.rating !== undefined
    const isCreator = issue.ticket?.supervisor_id === userProfile?.employee_id

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
    const [dateRange, setDateRange] = useState({
        start: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
        end: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
    })
    const [filters, setFilters] = useState({ site: '', vehicle_number: '', rating: '' })
    const [modalOpen, setModalOpen] = useState(false)
    const [selectedIssue, setSelectedIssue] = useState(null)

    const { data: feedbackData = [], isLoading } = useQuery({
        queryKey: ['feedback-report'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('issues')
                .select(`
                    id, issue_number, description, category, severity, status,
                    created_at, rating, rating_remarks, rated_at, ticket_id,
                    ticket:ticket_id (
                        ticket_number, vehicle_number, site, supervisor_id
                    )
                `)
                .eq('status', 'Done')
                .order('created_at', { ascending: false })

            if (error) throw error
            return data || []
        }
    })

    const filteredAndSortedData = useMemo(() => {
        let result = [...feedbackData]

        result = result.filter(issue => {
            const issueDate = format(parseISO(issue.created_at), 'yyyy-MM-dd')
            if (issueDate < dateRange.start || issueDate > dateRange.end) return false
            if (filters.site && issue.ticket?.site !== filters.site) return false
            if (filters.vehicle_number) {
                const vehicle = issue.ticket?.vehicle_number || ''
                if (!vehicle.toLowerCase().includes(filters.vehicle_number.toLowerCase())) return false
            }
            if (filters.rating === 'Not Rated') {
                if (issue.rating !== null && issue.rating !== undefined) return false
            } else if (filters.rating) {
                if (issue.rating !== filters.rating) return false
            }
            return true
        })

        result.sort((a, b) => {
            let aValue = a[sortConfig.key]
            let bValue = b[sortConfig.key]
            if (sortConfig.key === 'ticket_number') { aValue = a.ticket?.ticket_number; bValue = b.ticket?.ticket_number }
            else if (sortConfig.key === 'vehicle_number') { aValue = a.ticket?.vehicle_number || ''; bValue = b.ticket?.vehicle_number || '' }
            else if (sortConfig.key === 'supervisor_name') { aValue = a.ticket?.supervisor_id || ''; bValue = b.ticket?.supervisor_id || '' }
            if (sortConfig.key === 'created_at' || sortConfig.key === 'rated_at') {
                aValue = aValue ? new Date(aValue).getTime() : 0
                bValue = bValue ? new Date(bValue).getTime() : 0
            }
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

    const clearFilters = () => setFilters({ site: '', vehicle_number: '', rating: '' })
    const hasActiveFilters = filters.site || filters.vehicle_number || filters.rating

    const handleRatingClick = (issue) => { setSelectedIssue(issue); setModalOpen(true) }

    const handleRatingSubmit = (data) => {
        if (!selectedIssue) return
        updateIssue.mutate({
            id: selectedIssue.id,
            updates: { rating: data.rating, rating_remarks: data.rating_remarks, rated_at: new Date().toISOString() },
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
        if (sortConfig.key !== column) return <span className="text-gray-300 ml-1">↕</span>
        return sortConfig.direction === 'asc'
            ? <ChevronUpIcon className="w-3 h-3 ml-1 inline" />
            : <ChevronDownIcon className="w-3 h-3 ml-1 inline" />
    }

    const columns = [
        { key: 'issue_number', label: 'Issue ID', sortable: true },
        { key: 'vehicle_number', label: 'Vehicle', sortable: true },
        { key: 'description', label: 'Description', sortable: false },
        { key: 'category', label: 'Category', sortable: true },
        { key: 'severity', label: 'Severity', sortable: true },
        { key: 'created_at', label: 'Created Date', sortable: true },
        { key: 'ticket_number', label: 'Ticket', sortable: true },
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
                <div className="px-4 sm:px-6 py-4">
                    <div className="flex flex-col gap-3">
                        <div className="flex justify-between items-center">
                            <div>
                                <h1 className="text-2xl font-bold text-gray-900">Feedback Report</h1>
                                <p className="text-sm text-gray-600 mt-0.5">
                                    {filteredAndSortedData.length} record{filteredAndSortedData.length !== 1 ? 's' : ''}
                                </p>
                            </div>
                        </div>

                        {/* Filter Bar */}
                        <div className="flex flex-wrap gap-2 items-center">
                            <DateRangeFilter dateRange={dateRange} onDateRangeChange={setDateRange} />

                            <FilterSelect
                                value={filters.site}
                                onChange={(site) => setFilters({ ...filters, site })}
                                placeholder="All Sites"
                                options={sites.map(s => ({ value: s.name, label: s.name }))}
                            />

                            <input
                                type="text"
                                placeholder="Search vehicle..."
                                value={filters.vehicle_number}
                                onChange={(e) => setFilters({ ...filters, vehicle_number: e.target.value })}
                                className="px-4 py-2.5 text-sm border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 min-w-[150px] min-h-[48px]"
                            />

                            {/* Rating Filter */}
                            <FilterSelect
                                value={filters.rating}
                                onChange={v => setFilters({ ...filters, rating: v })}
                                placeholder="All Ratings"
                                options={[
                                    { value: 'Good', label: '😊 Good' },
                                    { value: 'Ok', label: '😐 Ok' },
                                    { value: 'Bad', label: '☹️ Bad' },
                                    { value: 'Not Rated', label: 'Not Rated' },
                                ]}
                            />

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

            {/* Full-width table */}
            <div className="px-4 sm:px-6 py-6">
                <div className="bg-white rounded-lg shadow overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-200">
                        <thead>
                            <tr className="bg-gray-50 sticky top-0 z-10 shadow-sm">
                                {columns.map(col => (
                                    <th
                                        key={col.key}
                                        onClick={() => col.sortable && handleSort(col.key)}
                                        className={`px-4 py-3 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider whitespace-nowrap border-b border-gray-200 ${col.sortable ? 'cursor-pointer hover:bg-gray-100 select-none' : ''}`}
                                    >
                                        {col.label}
                                        {col.sortable && <SortIcon column={col.key} />}
                                    </th>
                                ))}
                            </tr>
                        </thead>
                        <tbody className="bg-white divide-y divide-gray-100">
                            {isLoading ? (
                                <tr>
                                    <td colSpan={columns.length} className="px-4 py-12 text-center text-gray-500 text-sm">
                                        Loading...
                                    </td>
                                </tr>
                            ) : filteredAndSortedData.length === 0 ? (
                                <tr>
                                    <td colSpan={columns.length} className="px-4 py-12 text-center text-gray-500 text-sm">
                                        No feedback records found
                                    </td>
                                </tr>
                            ) : (
                                filteredAndSortedData.map((row) => (
                                    <tr key={row.id} className="hover:bg-gray-50 transition-colors">
                                        <td className="px-4 py-3 whitespace-nowrap text-sm font-medium text-gray-700">
                                            {row.issue_number}
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm font-semibold text-gray-900">
                                            {row.ticket?.vehicle_number || '-'}
                                        </td>
                                        <td className="px-4 py-3 text-sm text-gray-700 max-w-xs truncate" title={row.description}>
                                            {row.description}
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-600">
                                            {row.category}
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm">
                                            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${row.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-600'}`}>
                                                {row.severity}
                                            </span>
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-600">
                                            {row.created_at ? format(new Date(row.created_at), 'MMM d, yyyy') : '-'}
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm">
                                            <Link to={`/tickets/${row.ticket_id}`} className="text-blue-600 hover:underline font-medium">
                                                #{row.ticket?.ticket_number}
                                            </Link>
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-700">
                                            {row.ticket?.supervisor_id || '-'}
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm">
                                            <ReportFeedbackSmileys
                                                issue={row}
                                                userProfile={userProfile}
                                                onRatingClick={handleRatingClick}
                                                isUpdating={updateIssue.isPending}
                                            />
                                        </td>
                                        <td className="px-4 py-3 text-sm text-gray-600 max-w-xs truncate" title={row.rating_remarks || ''}>
                                            {row.rating_remarks || '-'}
                                        </td>
                                        <td className="px-4 py-3 whitespace-nowrap text-sm text-gray-600">
                                            {row.rated_at ? format(new Date(row.rated_at), 'MMM d, yyyy') : '-'}
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
            </div>

            <FeedbackModal
                isOpen={modalOpen}
                onClose={() => { setModalOpen(false); setSelectedIssue(null) }}
                onSubmit={handleRatingSubmit}
                isLoading={updateIssue.isPending}
                issueDescription={selectedIssue?.description || ''}
                initialRating={selectedIssue?.rating}
                initialRemarks={selectedIssue?.rating_remarks}
            />
        </div>
    )
}
