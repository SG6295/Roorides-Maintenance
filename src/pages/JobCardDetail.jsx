import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { useAuth } from '../hooks/useAuth'
import { useJobCard, useUpdateJobCard } from '../hooks/useJobCards'
import { useUpdateIssue } from '../hooks/useIssues'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'

// Icons
import {
    CheckCircleIcon,
    UserIcon,
    TruckIcon
} from '@heroicons/react/24/outline'

export default function JobCardDetail() {
    const { id } = useParams()
    const navigate = useNavigate()
    const { userProfile } = useAuth()

    const { data: jobCard, isLoading } = useJobCard(id)
    const updateJobCard = useUpdateJobCard()
    const updateIssue = useUpdateIssue()

    const [remarks, setRemarks] = useState('')

    useEffect(() => {
        if (jobCard) {
            setRemarks(jobCard.remarks || '')
        }
    }, [jobCard])

    if (isLoading) return <TicketDetailSkeleton />
    if (!jobCard) return <div className="p-8 text-center">Job Card not found</div>

    const isExec = userProfile?.role === 'maintenance_exec'
    const isMechanic = userProfile?.role === 'mechanic' || userProfile?.role === 'maintenance_exec' // Mechanic or Exec can work on it

    // Handlers
    const handleIssueStatus = async (issue, newStatus) => {
        try {
            await updateIssue.mutateAsync({
                id: issue.id,
                updates: { status: newStatus },
                userId: userProfile?.id,
                oldData: issue
            })
        } catch (e) {
            console.error('Failed to update issue:', e)
            alert('Failed to update issue: ' + e.message)
        }
    }

    const handleCompleteJobCard = async () => {
        if (!confirm('Are you sure you want to complete this Job Card? Ensure all work is done.')) return

        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: {
                    status: 'Completed',
                    completed_at: new Date().toISOString(),
                    remarks: remarks
                }
            })
            alert('Job Card Completed!')
        } catch (e) {
            alert('Failed to complete job card')
        }
    }

    const handleSaveRemarks = async () => {
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { remarks: remarks }
            })
            alert('Remarks saved')
        } catch (e) {
            alert('Failed to save')
        }
    }

    // Derived state
    const totalIssues = jobCard.issues?.length || 0
    const completedIssues = jobCard.issues?.filter(i => i.status === 'Done').length || 0
    const progress = totalIssues > 0 ? (completedIssues / totalIssues) * 100 : 0
    const isAllDone = totalIssues > 0 && totalIssues === completedIssues

    return (
        <div className="min-h-screen bg-gray-50 pb-12">
            <Navigation
                breadcrumbs={[
                    { label: 'Job Cards', href: '/job-cards' },
                    { label: `Job Card #${jobCard.job_card_number}` },
                ]}
            />

            <div className="max-w-4xl mx-auto px-4 sm:px-6 py-8">
                {/* Header */}
                <div className="bg-white rounded-lg shadow-sm p-6 mb-6">
                    <div className="flex flex-col md:flex-row md:items-start justify-between gap-4">
                        <div>
                            <div className="flex items-center gap-3 mb-2">
                                <h1 className="text-2xl font-bold text-gray-900">
                                    Job Card #{jobCard.job_card_number}
                                </h1>
                                <span className={`px-2.5 py-0.5 rounded-full text-xs font-medium ${jobCard.status === 'Completed' ? 'bg-green-100 text-green-800' : 'bg-blue-100 text-blue-800'
                                    }`}>
                                    {jobCard.status}
                                </span>
                            </div>
                            <p className="text-sm text-gray-500 flex items-center gap-6">
                                <span>Created {format(new Date(jobCard.created_at), 'MMM d, yyyy')}</span>
                                <span className="flex items-center gap-1">
                                    <TruckIcon className="w-4 h-4" /> {jobCard.vehicle_number}
                                </span>
                                <span className="flex items-center gap-1">
                                    <UserIcon className="w-4 h-4" />
                                    {jobCard.type === 'InHouse' ? jobCard.mechanic?.name || 'Mechanic' : jobCard.vendor_name}
                                </span>
                            </p>
                        </div>

                        <div className="flex flex-col items-end gap-2">
                            {/* Progress Bar */}
                            <div className="w-48 text-right">
                                <div className="text-xs text-gray-500 mb-1">{completedIssues} of {totalIssues} issues closed</div>
                                <div className="w-full bg-gray-200 rounded-full h-2">
                                    <div
                                        className="bg-green-500 h-2 rounded-full transition-all duration-500"
                                        style={{ width: `${progress}%` }}
                                    />
                                </div>
                            </div>

                            {isMechanic && jobCard.status !== 'Completed' && (
                                <button
                                    onClick={handleCompleteJobCard}
                                    disabled={!isAllDone}
                                    className={`mt-2 px-4 py-2 rounded-lg text-sm font-medium text-white shadow-sm transition-colors ${isAllDone
                                        ? 'bg-green-600 hover:bg-green-700'
                                        : 'bg-gray-400 cursor-not-allowed'
                                        }`}
                                    title={!isAllDone ? "All issues must be 'Done' first" : ""}
                                >
                                    Complete Job Card
                                </button>
                            )}
                        </div>
                    </div>
                </div>

                {/* Issues List */}
                <div className="bg-white rounded-lg shadow-sm overflow-hidden mb-6">
                    <div className="px-6 py-4 border-b border-gray-200">
                        <h2 className="text-lg font-semibold text-gray-900">Work Items</h2>
                    </div>
                    <div className="overflow-x-auto">
                        <table className="min-w-full divide-y divide-gray-200">
                            <thead className="bg-gray-50">
                                <tr>
                                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                        Ticket #
                                    </th>
                                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                        Description
                                    </th>
                                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                        Category
                                    </th>
                                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                        SLA Due
                                    </th>
                                    <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                        Status
                                    </th>
                                    {(isMechanic && jobCard.status !== 'Completed') && (
                                        <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                                            Action
                                        </th>
                                    )}
                                </tr>
                            </thead>
                            <tbody className="bg-white divide-y divide-gray-200">
                                {jobCard.issues?.map(issue => (
                                    <tr key={issue.id} className="hover:bg-gray-50 transition-colors">
                                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                                            <Link
                                                to={`/tickets/${issue.ticket_id}`}
                                                className="text-blue-600 hover:text-blue-800 hover:underline"
                                            >
                                                #{issue.ticket?.ticket_number || issue.ticket_id.slice(0, 8)}
                                            </Link>
                                        </td>
                                        <td className="px-6 py-4 text-sm text-gray-900">
                                            {issue.description}
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <span className="text-xs px-2 py-0.5 bg-gray-100 rounded text-gray-600">
                                                {issue.category}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                                            {issue.sla_end_date ? format(new Date(issue.sla_end_date), 'MMM d') : '-'}
                                        </td>
                                        <td className="px-6 py-4 whitespace-nowrap">
                                            <span className={`px-2 py-1 rounded text-xs ${issue.status === 'Done' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'
                                                }`}>
                                                {issue.status}
                                            </span>
                                        </td>
                                        {(isMechanic && jobCard.status !== 'Completed') && (
                                            <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                                                <button
                                                    onClick={() => handleIssueStatus(issue, issue.status === 'Done' ? 'Open' : 'Done')}
                                                    className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium transition-colors ${issue.status === 'Done'
                                                        ? 'bg-green-100 text-green-700 hover:bg-green-200'
                                                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                                                        }`}
                                                >
                                                    <CheckCircleIcon className={`w-4 h-4 ${issue.status === 'Done' ? 'text-green-600' : 'text-gray-400'}`} />
                                                    {issue.status === 'Done' ? 'Done' : 'Mark Done'}
                                                </button>
                                            </td>
                                        )}
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>

                {/* Remarks / Notes */}
                <div className="bg-white rounded-lg shadow-sm p-6">
                    <div className="flex justify-between items-center mb-4">
                        <h2 className="text-lg font-semibold text-gray-900">Execution Remarks</h2>
                        {isMechanic && jobCard.status !== 'Completed' && (
                            <button onClick={handleSaveRemarks} className="text-blue-600 text-sm hover:underline">Save Remarks</button>
                        )}
                    </div>
                    {isMechanic && jobCard.status !== 'Completed' ? (
                        <textarea
                            value={remarks}
                            onChange={e => setRemarks(e.target.value)}
                            className="w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                            rows={4}
                            placeholder="Enter parts used, work details, or issues faced..."
                        />
                    ) : (
                        <p className="text-gray-700 whitespace-pre-wrap">{remarks || 'No remarks.'}</p>
                    )}
                </div>

            </div>
        </div>
    )
}
