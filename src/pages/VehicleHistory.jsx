import { useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { format, parseISO } from 'date-fns'
import Navigation from '../components/shared/Navigation'
import { TicketListSkeleton } from '../components/shared/LoadingSkeleton'
import { useVehicleHistory, useJobCardParts } from '../hooks/useInventory'
import { ChevronDownIcon, ChevronUpIcon, WrenchScrewdriverIcon } from '@heroicons/react/24/outline'

const STATUS_BADGE = {
    Completed: 'bg-green-100 text-green-700',
    Open: 'bg-blue-100 text-blue-700',
    'In Progress': 'bg-yellow-100 text-yellow-700',
}

function JobCardRow({ jc }) {
    const [expanded, setExpanded] = useState(false)
    const { data: parts = [], isLoading: partsLoading } = useJobCardParts(expanded ? jc.id : null)

    const totalLabour = jc.issues?.reduce((s, i) => s + (parseFloat(i.labour_hours) || 0), 0) ?? 0

    return (
        <>
            <tr
                className="hover:bg-gray-50 cursor-pointer"
                onClick={() => setExpanded(p => !p)}
            >
                <td className="px-4 py-3 font-mono text-xs text-blue-600">
                    <Link
                        to={`/job-cards/${jc.job_card_number}`}
                        onClick={e => e.stopPropagation()}
                        className="hover:underline"
                    >
                        JC-{jc.job_card_number}
                    </Link>
                </td>
                <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                    {jc.created_at ? format(parseISO(jc.created_at), 'dd MMM yyyy') : '—'}
                </td>
                <td className="px-4 py-3 text-gray-500 text-xs whitespace-nowrap">
                    {jc.completed_at ? format(parseISO(jc.completed_at), 'dd MMM yyyy') : '—'}
                </td>
                <td className="px-4 py-3 text-gray-700 text-sm">
                    {jc.mechanic ? (
                        <Link
                            to={`/mechanics/${jc.mechanic.id}`}
                            onClick={e => e.stopPropagation()}
                            className="text-blue-600 hover:underline"
                        >
                            {jc.mechanic.name}
                        </Link>
                    ) : '—'}
                </td>
                <td className="px-4 py-3 text-center text-gray-500 text-sm">{jc.issues?.length ?? 0}</td>
                <td className="px-4 py-3 text-right text-gray-700 text-sm">
                    {totalLabour > 0 ? `${totalLabour} hrs` : '—'}
                </td>
                <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 text-xs rounded-full ${STATUS_BADGE[jc.status] || 'bg-gray-100 text-gray-600'}`}>
                        {jc.status}
                    </span>
                </td>
                <td className="px-4 py-3 text-center text-gray-400">
                    {expanded
                        ? <ChevronUpIcon className="w-4 h-4 mx-auto" />
                        : <ChevronDownIcon className="w-4 h-4 mx-auto" />}
                </td>
            </tr>

            {expanded && (
                <tr>
                    <td colSpan={8} className="bg-gray-50 px-6 py-3">
                        {/* Issues */}
                        {jc.issues?.length === 0 ? (
                            <p className="text-xs text-gray-400">No issues recorded.</p>
                        ) : (
                            <div className="space-y-1 mb-3">
                                {jc.issues.map(issue => (
                                    <div key={issue.id} className="flex items-center gap-3 text-xs">
                                        <span className="font-medium text-gray-800">{issue.description || 'No description'}</span>
                                        <span className="text-gray-400">{issue.status}</span>
                                        {issue.labour_hours > 0 && (
                                            <span className="text-gray-500">{issue.labour_hours} hrs</span>
                                        )}
                                    </div>
                                ))}
                            </div>
                        )}
                        {/* Parts used */}
                        {partsLoading ? (
                            <p className="text-xs text-gray-400">Loading parts…</p>
                        ) : parts.length > 0 && (
                            <div>
                                <p className="text-xs font-medium text-gray-500 mb-1">Parts used:</p>
                                <div className="flex flex-wrap gap-2">
                                    {parts.map(ip => (
                                        <span key={ip.id} className="bg-white border px-2 py-0.5 rounded text-xs text-gray-600">
                                            {ip.part?.name} × {ip.quantity_used} {ip.part?.unit}
                                        </span>
                                    ))}
                                </div>
                            </div>
                        )}
                    </td>
                </tr>
            )}
        </>
    )
}

export default function VehicleHistory() {
    const { vehicleNumber } = useParams()
    const decoded = decodeURIComponent(vehicleNumber)
    const { data: jobCards = [], isLoading } = useVehicleHistory(decoded)

    const totalJobCards = jobCards.length
    const openJobCards = jobCards.filter(jc => jc.status !== 'Completed').length
    const totalLabourHours = jobCards.reduce((s, jc) =>
        s + (jc.issues?.reduce((is, i) => is + (parseFloat(i.labour_hours) || 0), 0) ?? 0), 0
    )

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[
                { label: 'Vehicles', href: '/vehicles' },
                { label: decoded },
            ]} />

            <div className="max-w-7xl mx-auto px-4 sm:px-6 py-8">
                {/* Header */}
                <div className="flex items-center gap-3 mb-6">
                    <div className="p-2 bg-blue-100 rounded-lg">
                        <WrenchScrewdriverIcon className="w-6 h-6 text-blue-600" />
                    </div>
                    <div>
                        <h1 className="text-2xl font-bold text-gray-900">{decoded}</h1>
                        <p className="text-sm text-gray-500">Vehicle maintenance history</p>
                    </div>
                </div>

                {isLoading ? (
                    <TicketListSkeleton />
                ) : (
                    <>
                        {/* Stats */}
                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
                            {[
                                { label: 'Total Job Cards', value: totalJobCards },
                                { label: 'Open / In Progress', value: openJobCards },
                                { label: 'Total Labour Hours', value: totalLabourHours > 0 ? `${totalLabourHours} hrs` : '—' },
                            ].map(stat => (
                                <div key={stat.label} className="bg-white rounded-lg shadow-sm px-5 py-4">
                                    <p className="text-xs text-gray-500 uppercase tracking-wide">{stat.label}</p>
                                    <p className="text-2xl font-bold text-gray-900 mt-1">{stat.value}</p>
                                </div>
                            ))}
                        </div>

                        {/* Job cards table */}
                        {jobCards.length === 0 ? (
                            <div className="bg-white rounded-lg shadow-sm p-12 text-center text-gray-400 text-sm">
                                No job cards found for this vehicle.
                            </div>
                        ) : (
                            <div className="bg-white rounded-lg shadow-sm overflow-hidden">
                                <table className="min-w-full divide-y divide-gray-100 text-sm">
                                    <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide">
                                        <tr>
                                            <th className="px-4 py-3 text-left">Job Card</th>
                                            <th className="px-4 py-3 text-left">Created</th>
                                            <th className="px-4 py-3 text-left">Completed</th>
                                            <th className="px-4 py-3 text-left">Mechanic</th>
                                            <th className="px-4 py-3 text-center">Issues</th>
                                            <th className="px-4 py-3 text-right">Labour</th>
                                            <th className="px-4 py-3 text-left">Status</th>
                                            <th className="px-4 py-3 w-8"></th>
                                        </tr>
                                    </thead>
                                    <tbody className="divide-y divide-gray-50">
                                        {jobCards.map(jc => (
                                            <JobCardRow key={jc.id} jc={jc} />
                                        ))}
                                    </tbody>
                                </table>
                                <div className="px-4 py-2 bg-gray-50 text-xs text-gray-400 border-t">
                                    {totalJobCards} job card{totalJobCards !== 1 ? 's' : ''}
                                </div>
                            </div>
                        )}
                    </>
                )}
            </div>
        </div>
    )
}
