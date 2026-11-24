import { useState } from 'react'
import { ClockIcon } from '@heroicons/react/24/outline'
import { useVehicleCompanyChanges } from '../../hooks/useVehicleCompany'
import { companyLabel } from '../../constants/vehicleCompanies'
import { formatDateTime } from '../../utils/datetime'

const PAGE_SIZE = 20

const rupees = v => `₹${Number(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

const Company = ({ value }) => <span className="font-medium">{companyLabel(value)}</span>

/** One history entry as a sentence. */
function describe(entry) {
    const reg = <span className="font-mono">{entry.registration_number}</span>
    if (entry.kind === 'initial_load') {
        return <>{reg} loaded from the Google Sheet as <Company value={entry.new_company} /></>
    }
    if (entry.kind === 'assignment') {
        return <>assigned {reg} to <Company value={entry.new_company} /> (was Unknown)</>
    }
    return (
        <>
            moved {reg} from <Company value={entry.old_company} /> to <Company value={entry.new_company} /> — sale of{' '}
            <span className="font-medium">{rupees(entry.sale_value)}</span> incl. GST at {Number(entry.gst_percent)}%
        </>
    )
}

/**
 * Every change of a vehicle's company, newest first (MAIN-155). With `vehicle` set, only
 * that vehicle's; `onShowAll` clears it. The parent keys it on the vehicle, so switching
 * vehicle starts again at page 1.
 */
export default function VehicleCompanyHistory({ vehicle = null, onShowAll }) {
    const [page, setPage] = useState(0)

    const { data, isLoading, isError } = useVehicleCompanyChanges({ vehicleId: vehicle?.id ?? null, page, pageSize: PAGE_SIZE })

    const entries = data?.entries ?? []
    const total = data?.total ?? 0
    const from = total === 0 ? 0 : page * PAGE_SIZE + 1
    const to = Math.min((page + 1) * PAGE_SIZE, total)

    return (
        <div className="mt-8">
            <div className="flex items-center justify-between gap-2 mb-3">
                <div className="flex items-center gap-2">
                    <ClockIcon className="h-5 w-5 text-gray-500" />
                    <h3 className="text-lg font-medium text-gray-900">
                        Change history
                        {vehicle && <span className="text-gray-500 font-normal"> — <span className="font-mono">{vehicle.registration_number}</span></span>}
                    </h3>
                </div>
                {vehicle && (
                    <button type="button" onClick={onShowAll} className="text-sm text-blue-600 hover:underline">
                        Show all vehicles
                    </button>
                )}
            </div>

            <div className="bg-white shadow overflow-hidden sm:rounded-md border border-gray-300">
                {isLoading ? (
                    <p className="px-6 py-8 text-center text-gray-600 text-sm">Loading history...</p>
                ) : isError ? (
                    <p className="px-6 py-8 text-center text-gray-600 text-sm">Could not load the change history.</p>
                ) : entries.length === 0 ? (
                    <p className="px-6 py-8 text-center text-gray-600 text-sm">No changes recorded yet.</p>
                ) : (
                    <ul role="list" className="divide-y divide-gray-200">
                        {entries.map(entry => (
                            <li key={entry.id} className="px-4 py-3 sm:px-6">
                                <div className="flex flex-col sm:flex-row sm:items-baseline sm:justify-between gap-1">
                                    <p className="text-sm text-gray-700">
                                        <span className="font-semibold text-gray-900">{entry.performed_by_name || 'Unknown user'}</span>
                                        {entry.kind === 'initial_load' ? ': ' : ' '}
                                        {describe(entry)}
                                    </p>
                                    <span className="text-xs text-gray-500 whitespace-nowrap flex-shrink-0">
                                        {formatDateTime(entry.created_at)}
                                    </span>
                                </div>
                            </li>
                        ))}
                    </ul>
                )}

                {total > PAGE_SIZE && (
                    <div className="flex items-center justify-between border-t border-gray-200 bg-gray-50 px-4 py-3 sm:px-6">
                        <p className="text-xs text-gray-600">Showing {from}–{to} of {total}</p>
                        <div className="flex gap-2">
                            <button
                                type="button"
                                onClick={() => setPage(p => Math.max(0, p - 1))}
                                disabled={page === 0}
                                className="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
                            >
                                Previous
                            </button>
                            <button
                                type="button"
                                onClick={() => setPage(p => p + 1)}
                                disabled={to >= total}
                                className="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed"
                            >
                                Next
                            </button>
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
