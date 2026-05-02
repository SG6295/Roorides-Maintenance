import { useState } from 'react'
import { Link } from 'react-router-dom'
import { format } from 'date-fns'
import { useIssues } from '../hooks/useIssues'
import Navigation from '../components/shared/Navigation'
import FilterSelect from '../components/shared/FilterSelect'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'

export default function Issues() {
    const [filters, setFilters] = useState({
        status: '',
        category: ''
    })

    const { data: issues, isLoading } = useIssues(filters)

    if (isLoading) {
        return (
            <div className="min-h-screen bg-gray-50">
                <Navigation breadcrumbs={[{ label: 'Issues' }]} />
                <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                    <TicketListSkeleton />
                </div>
            </div>
        )
    }

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Issues' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                <h1 className="text-2xl font-bold text-gray-900 mb-6">Issues Registry</h1>

                {/* Filters */}
                <div className="bg-white p-4 rounded-lg shadow-sm mb-6 flex flex-wrap gap-3">
                    <FilterSelect
                        value={filters.status}
                        onChange={v => setFilters({ ...filters, status: v })}
                        placeholder="All Statuses"
                        options={[
                            { value: 'Open', label: 'Open' },
                            { value: 'Done', label: 'Done' },
                        ]}
                    />
                    <FilterSelect
                        value={filters.category}
                        onChange={v => setFilters({ ...filters, category: v })}
                        placeholder="All Categories"
                        options={['Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS', 'AdBlue', 'Other'].map(c => ({ value: c, label: c }))}
                    />
                </div>

                {/* Table */}
                <div className="bg-white rounded-lg shadow overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-200">
                        <thead className="bg-gray-50">
                            <tr>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">Issue ID</th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">Vehicle / Ticket</th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">Category</th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">Severity</th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">Status</th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">SLA Due</th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase">Job Card</th>
                            </tr>
                        </thead>
                        <tbody className="bg-white divide-y divide-gray-200">
                            {issues?.map(issue => (
                                <tr key={issue.id} className="hover:bg-gray-50">
                                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                                        {issue.issue_number}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                                        <div className="font-medium text-gray-900">{issue.ticket?.vehicle_number}</div>
                                        <Link to={`/tickets/${issue.ticket_id}`} className="text-blue-600 hover:underline">
                                            Ticket #{issue.ticket?.ticket_number}
                                        </Link>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">{issue.category}</td>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <span className={`px-2 py-1 rounded text-xs ${issue.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-600'}`}>
                                            {issue.severity}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <span className={`px-2 py-1 rounded-full text-xs ${issue.status === 'Done' ? 'bg-green-100 text-green-800' : 'bg-blue-100 text-blue-800'}`}>
                                            {issue.status}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                                        {issue.sla_end_date ? format(new Date(issue.sla_end_date), 'MMM d') : '-'}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                                        {issue.job_card?.job_card_number ? (
                                            <Link to={`/job-cards/${issue.job_card.job_card_number}`} className="text-blue-600 hover:underline">
                                                #{issue.job_card.job_card_number}
                                            </Link>
                                        ) : '-'}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    )
}
