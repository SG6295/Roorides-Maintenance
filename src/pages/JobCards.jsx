import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { format } from 'date-fns'
import { useJobCards } from '../hooks/useJobCards'
import Navigation from '../components/shared/Navigation'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'

// Icons
import {
    FunnelIcon,
    MagnifyingGlassIcon,
} from '@heroicons/react/24/outline'

export default function JobCards() {
    const navigate = useNavigate()
    const [filters, setFilters] = useState({
        status: '',
        site: '',
        search: ''
    })

    // Hook handles basic filtering, client side search could be added
    const { data: jobCards, isLoading } = useJobCards(filters)

    // Client-side search for vehicle number or mechanic name if backend filter not implemented
    const filteredJobCards = jobCards?.filter(jc => {
        if (!filters.search) return true
        const term = filters.search.toLowerCase()
        return (
            jc.job_card_number?.toString().includes(term) ||
            jc.vehicle_number?.toLowerCase().includes(term) ||
            jc.vendor_name?.toLowerCase().includes(term) ||
            jc.mechanic?.name?.toLowerCase().includes(term)
        )
    })

    if (isLoading) {
        return (
            <div className="min-h-screen bg-gray-50">
                <Navigation breadcrumbs={[{ label: 'Job Cards' }]} />
                <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                    <TicketListSkeleton />
                </div>
            </div>
        )
    }

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[{ label: 'Job Cards' }]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
                    <h1 className="text-2xl font-bold text-gray-900">Job Cards</h1>
                </div>

                {/* Filters */}
                <div className="bg-white p-4 rounded-lg shadow-sm mb-6">
                    <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                        <div className="relative">
                            <input
                                type="text"
                                placeholder="Search vehicle or assignee..."
                                className="w-full pl-10 pr-4 py-2 border rounded-lg focus:ring-2 focus:ring-blue-500"
                                value={filters.search}
                                onChange={(e) => setFilters(prev => ({ ...prev, search: e.target.value }))}
                            />
                            <MagnifyingGlassIcon className="w-5 h-5 text-gray-500 absolute left-3 top-2.5" />
                        </div>

                        <select
                            className="border rounded-lg px-4 py-2 focus:ring-2 focus:ring-blue-500"
                            value={filters.status}
                            onChange={(e) => setFilters(prev => ({ ...prev, status: e.target.value }))}
                        >
                            <option value="">All Statuses</option>
                            <option value="Open">Open</option>
                            <option value="Completed">Completed</option>
                        </select>
                    </div>
                </div>

                {/* List */}
                <div className="bg-white rounded-lg shadow overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-200">
                        <thead className="bg-gray-50">
                            <tr>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Job Card
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Vehicle
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Type / Assignee
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Created
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Status
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Open Issues
                                </th>
                            </tr>
                        </thead>
                        <tbody className="bg-white divide-y divide-gray-200">
                            {filteredJobCards?.map((jc) => {
                                const openIssues = jc.issues?.filter(i => i.status === 'Open').length || 0
                                return (
                                    <tr
                                        key={jc.id}
                                        className="hover:bg-gray-50 cursor-pointer transition-colors"
                                        onClick={() => navigate(`/job-cards/${jc.job_card_number}`)}
                                    >
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <span className="text-blue-600 font-medium hover:underline">
                                                #{jc.job_card_number}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <span className="text-gray-900 font-medium">{jc.vehicle_number}</span>
                                            <span className="block text-xs text-gray-600">{jc.site}</span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <div>
                                                {jc.type === 'InHouse' ? (
                                                    <span className="bg-purple-100 text-purple-800 px-2 py-0.5 rounded text-xs font-medium">In House</span>
                                                ) : (
                                                    <span className="bg-orange-100 text-orange-800 px-2 py-0.5 rounded text-xs font-medium">Outsource</span>
                                                )}
                                                <span className="block text-sm text-gray-600 mt-0.5">
                                                    {jc.type === 'InHouse' ? jc.mechanic?.name || 'Unassigned' : jc.vendor_name}
                                                </span>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                                            {format(new Date(jc.created_at), 'MMM d, yyyy')}
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${jc.status === 'Completed' ? 'bg-green-100 text-green-800' : 'bg-blue-100 text-blue-800'
                                                }`}>
                                                {jc.status}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                                            {openIssues > 0 ? (
                                                <span className="text-red-600 font-medium">{openIssues} Open</span>
                                            ) : (
                                                <span className="text-green-600">All Done</span>
                                            )}
                                        </td>
                                    </tr>
                                )
                            })}
                            {filteredJobCards?.length === 0 && (
                                <tr>
                                    <td colSpan={6} className="px-6 py-12 text-center text-gray-600">
                                        No job cards found.
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    )
}
