import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import Navigation from '../components/shared/Navigation'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'
import { useMechanicProfile, useMechanicActivity } from '../hooks/useInventory'
import { UserCircleIcon } from '@heroicons/react/24/outline'

const STATUS_BADGE = {
    Completed: 'bg-green-100 text-green-700',
    Open: 'bg-blue-100 text-blue-700',
    'In Progress': 'bg-yellow-100 text-yellow-700',
}

const TABS = [
    { key: 'activity', label: 'Activity History' },
    { key: 'labour', label: 'Labour Track' },
]

export default function MechanicDetail() {
    const { mechanicId } = useParams()
    const [tab, setTab] = useState('activity')

    const { data: profile, isLoading: profileLoading } = useMechanicProfile(mechanicId)
    const { data: jobCards = [], isLoading: activityLoading } = useMechanicActivity(mechanicId)

    const isLoading = profileLoading || activityLoading

    // Derive stats
    const totalJobCards = jobCards.length
    const completedJobCards = jobCards.filter(jc => jc.status === 'Completed').length
    const totalLabourHours = jobCards.reduce((s, jc) =>
        s + (jc.issues?.reduce((is, i) => is + (parseFloat(i.labour_hours) || 0), 0) ?? 0), 0
    )

    // Labour track rows: one row per issue that has labour_hours recorded
    const labourRows = jobCards.flatMap(jc =>
        (jc.issues || [])
            .filter(i => i.labour_hours > 0)
            .map(i => ({
                issue_id: i.id,
                issue_title: i.description,
                labour_hours: i.labour_hours,
                job_card_id: jc.id,
                job_card_number: jc.job_card_number,
                vehicle_number: jc.vehicle_number,
                job_card_status: jc.status,
                date: jc.completed_at || jc.created_at,
            }))
    ).sort((a, b) => new Date(b.date) - new Date(a.date))

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[
                { label: 'Inventory', href: '/inventory' },
                { label: profile?.name || 'Mechanic' },
            ]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">

                {isLoading ? (
                    <TicketListSkeleton />
                ) : (
                    <>
                        {/* Profile header */}
                        <div className="bg-white rounded-xl shadow-sm px-6 py-5 mb-6 flex items-center gap-5">
                            <div className="p-3 bg-blue-100 rounded-full">
                                <UserCircleIcon className="w-10 h-10 text-blue-600" />
                            </div>
                            <div>
                                <h1 className="text-2xl font-bold text-gray-900">{profile?.name}</h1>
                                <p className="text-sm text-gray-500 capitalize mt-0.5">
                                    {profile?.role?.replace('_', ' ')}
                                    {profile?.site ? ` · ${profile.site}` : ''}
                                </p>
                            </div>
                        </div>

                        {/* Stats */}
                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
                            {[
                                { label: 'Total Job Cards', value: totalJobCards },
                                { label: 'Completed', value: completedJobCards },
                                { label: 'Total Labour Hours', value: totalLabourHours > 0 ? `${totalLabourHours} hrs` : '—' },
                            ].map(stat => (
                                <div key={stat.label} className="bg-white rounded-lg shadow-sm px-5 py-4">
                                    <p className="text-xs text-gray-500 uppercase tracking-wide">{stat.label}</p>
                                    <p className="text-2xl font-bold text-gray-900 mt-1">{stat.value}</p>
                                </div>
                            ))}
                        </div>

                        {/* Tabs */}
                        <div className="flex gap-1 bg-white border rounded-lg p-1 mb-6 w-fit shadow-sm">
                            {TABS.map(t => (
                                <button
                                    key={t.key}
                                    onClick={() => setTab(t.key)}
                                    className={`px-4 py-1.5 text-sm rounded-md transition-colors ${
                                        tab === t.key
                                            ? 'bg-blue-600 text-white font-medium'
                                            : 'text-gray-600 hover:text-gray-900'
                                    }`}
                                >
                                    {t.label}
                                </button>
                            ))}
                        </div>

                        {/* Activity History */}
                        {tab === 'activity' && (
                            jobCards.length === 0 ? (
                                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                                    No job cards assigned yet.
                                </div>
                            ) : (
                                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                            <tr>
                                                <th className="px-4 py-3 text-left">Job Card</th>
                                                <th className="px-4 py-3 text-left">Vehicle</th>
                                                <th className="px-4 py-3 text-left">Type</th>
                                                <th className="px-4 py-3 text-left">Created</th>
                                                <th className="px-4 py-3 text-left">Completed</th>
                                                <th className="px-4 py-3 text-center">Issues</th>
                                                <th className="px-4 py-3 text-left">Status</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-50">
                                            {jobCards.map(jc => (
                                                <tr key={jc.id} className="hover:bg-gray-50">
                                                    <td className="px-4 py-3 font-mono text-xs">
                                                        <Link
                                                            to={`/job-cards/${jc.job_card_number}`}
                                                            className="text-blue-600 hover:underline"
                                                        >
                                                            JC-{jc.job_card_number}
                                                        </Link>
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        <Link
                                                            to={`/vehicles/${encodeURIComponent(jc.vehicle_number)}`}
                                                            className="text-blue-600 hover:underline text-sm"
                                                        >
                                                            {jc.vehicle_number}
                                                        </Link>
                                                    </td>
                                                    <td className="px-4 py-3 text-gray-500 text-sm">{jc.type || '—'}</td>
                                                    <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                                                        {jc.created_at ? format(parseISO(jc.created_at), 'dd MMM yyyy') : '—'}
                                                    </td>
                                                    <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                                                        {jc.completed_at ? format(parseISO(jc.completed_at), 'dd MMM yyyy') : '—'}
                                                    </td>
                                                    <td className="px-4 py-3 text-center text-gray-600">
                                                        {jc.issues?.length ?? 0}
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        <span className={`px-2 py-0.5 text-xs rounded-full ${STATUS_BADGE[jc.status] || 'bg-gray-100 text-gray-600'}`}>
                                                            {jc.status}
                                                        </span>
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                                        {totalJobCards} job card{totalJobCards !== 1 ? 's' : ''}
                                    </div>
                                </div>
                            )
                        )}

                        {/* Labour Track */}
                        {tab === 'labour' && (
                            labourRows.length === 0 ? (
                                <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                                    No labour hours recorded yet.
                                </div>
                            ) : (
                                <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                                    <table className="min-w-full divide-y divide-gray-100 text-sm">
                                        <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                            <tr>
                                                <th className="px-4 py-3 text-left">Date</th>
                                                <th className="px-4 py-3 text-left">Job Card</th>
                                                <th className="px-4 py-3 text-left">Vehicle</th>
                                                <th className="px-4 py-3 text-left">Issue</th>
                                                <th className="px-4 py-3 text-right">Hours</th>
                                                <th className="px-4 py-3 text-left">JC Status</th>
                                            </tr>
                                        </thead>
                                        <tbody className="divide-y divide-gray-50">
                                            {labourRows.map(row => (
                                                <tr key={row.issue_id} className="hover:bg-gray-50">
                                                    <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                                                        {row.date ? format(parseISO(row.date), 'dd MMM yyyy') : '—'}
                                                    </td>
                                                    <td className="px-4 py-3 font-mono text-xs">
                                                        <Link
                                                            to={`/job-cards/${row.job_card_number}`}
                                                            className="text-blue-600 hover:underline"
                                                        >
                                                            JC-{row.job_card_number}
                                                        </Link>
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        <Link
                                                            to={`/vehicles/${encodeURIComponent(row.vehicle_number)}`}
                                                            className="text-blue-600 hover:underline text-sm"
                                                        >
                                                            {row.vehicle_number}
                                                        </Link>
                                                    </td>
                                                    <td className="px-4 py-3 text-gray-700">{row.issue_title || '—'}</td>
                                                    <td className="px-4 py-3 text-right font-semibold text-gray-900">
                                                        {row.labour_hours} hrs
                                                    </td>
                                                    <td className="px-4 py-3">
                                                        <span className={`px-2 py-0.5 text-xs rounded-full ${STATUS_BADGE[row.job_card_status] || 'bg-gray-100 text-gray-600'}`}>
                                                            {row.job_card_status}
                                                        </span>
                                                    </td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                    <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t flex justify-between">
                                        <span>{labourRows.length} entr{labourRows.length !== 1 ? 'ies' : 'y'}</span>
                                        <span className="font-medium text-gray-600">Total: {totalLabourHours} hrs</span>
                                    </div>
                                </div>
                            )
                        )}
                    </>
                )}
            </div>
        </div>
    )
}
