import { useMemo, useState } from 'react'
import { MagnifyingGlassIcon, TruckIcon, ClockIcon } from '@heroicons/react/24/outline'
import FilterSelect from '../../components/shared/FilterSelect'
import ChangeCompanyModal from '../../components/vehicles/ChangeCompanyModal'
import VehicleCompanyHistory from '../../components/vehicles/VehicleCompanyHistory'
import { useVehicles } from '../../hooks/useVehicles'
import { useAuth } from '../../hooks/useAuth'
import { VEHICLE_COMPANIES, companyColor, companyLabel } from '../../constants/vehicleCompanies'

// "KA 51 B 5997", "ka51b5997" and "KA51B5997" are one search.
const plateKey = s => (s ?? '').toUpperCase().replace(/[\s-]/g, '')

/**
 * Vehicle Registration Master (MAIN-155): which company each vehicle is registered to.
 * Everyone can view; finance and super_admin assign Unknown vehicles and move vehicles
 * between the companies (set_vehicle_company). The list is small (under 1,000 rows), so it
 * is loaded once and filtered here, which also gives the per-company counts.
 */
export default function VehicleRegistrationMaster() {
    const { userProfile } = useAuth()
    const canEdit = ['finance', 'super_admin'].includes(userProfile?.role)

    const { data: vehicles = [], isLoading } = useVehicles({})

    const [search, setSearch] = useState('')
    const [company, setCompany] = useState('')
    const [status, setStatus] = useState('active')
    const [changing, setChanging] = useState(null)
    const [historyFor, setHistoryFor] = useState(null)

    const inStatus = useMemo(() => vehicles.filter(v =>
        status === 'active' ? v.is_active : status === 'inactive' ? !v.is_active : true
    ), [vehicles, status])

    const counts = useMemo(() => {
        const c = Object.fromEntries(VEHICLE_COMPANIES.map(x => [x.value, 0]))
        for (const v of inStatus) c[v.company] = (c[v.company] ?? 0) + 1
        return c
    }, [inStatus])

    const shown = useMemo(() => {
        const q = search.trim().toLowerCase()
        const qPlate = plateKey(search)
        return inStatus.filter(v =>
            (!company || v.company === company) &&
            (!q
                || plateKey(v.registration_number).includes(qPlate)
                || `${v.make ?? ''} ${v.model ?? ''}`.toLowerCase().includes(q)
                || (v.vehicle_sites ?? []).some(s => s.site_name.toLowerCase().includes(q)))
        )
    }, [inStatus, company, search])

    const statusLabel = status === 'active' ? 'active ' : status === 'inactive' ? 'inactive ' : ''

    return (
        <div>
            <div className="mb-5">
                <h2 className="text-lg font-medium text-gray-900">Vehicle Registration Master</h2>
                <p className="text-sm text-gray-500 mt-1">
                    The company each vehicle is registered to. Work on an Unknown vehicle is blocked until
                    finance assigns it.{!canEdit && ' Only finance can change a company.'}
                </p>
            </div>

            {/* Per-company counts; each is a shortcut to its filter */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-5">
                {VEHICLE_COMPANIES.map(c => (
                    <button
                        key={c.value}
                        type="button"
                        onClick={() => setCompany(company === c.value ? '' : c.value)}
                        className={`text-left rounded-lg border px-4 py-3 transition-colors ${company === c.value ? 'border-blue-500 ring-1 ring-blue-500' : 'border-gray-200 hover:border-gray-300'}`}
                    >
                        <p className="text-xs text-gray-500">{c.label}</p>
                        <p className="text-2xl font-semibold text-gray-900">{isLoading ? '…' : counts[c.value]}</p>
                    </button>
                ))}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-4 gap-3 mb-4">
                <div className="relative sm:col-span-2">
                    <input
                        type="text"
                        placeholder="Search by reg. number, make, model or site…"
                        className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500"
                        value={search}
                        onChange={e => setSearch(e.target.value)}
                    />
                    <MagnifyingGlassIcon className="w-4 h-4 text-gray-400 absolute left-3 top-2.5" />
                </div>
                <FilterSelect
                    value={company}
                    onChange={setCompany}
                    placeholder="All companies"
                    options={VEHICLE_COMPANIES.map(c => ({ value: c.value, label: c.label }))}
                />
                <FilterSelect
                    value={status}
                    onChange={setStatus}
                    placeholder="Active and inactive"
                    options={[
                        { value: 'active', label: 'Active only' },
                        { value: 'inactive', label: 'Inactive only' },
                    ]}
                />
            </div>

            {isLoading ? (
                <p className="py-10 text-center text-sm text-gray-500">Loading vehicles…</p>
            ) : shown.length === 0 ? (
                <div className="py-12 text-center border border-gray-200 rounded-lg">
                    <TruckIcon className="w-10 h-10 text-gray-300 mx-auto mb-3" />
                    <p className="text-gray-500 text-sm">No vehicles found.</p>
                </div>
            ) : (
                <div className="border border-gray-200 rounded-lg overflow-hidden">
                    <div className="max-h-[32rem] overflow-auto">
                        <table className="min-w-full divide-y divide-gray-100 text-sm">
                            <thead className="bg-gray-50 text-xs font-medium text-gray-500 uppercase tracking-wide sticky top-0">
                                <tr>
                                    <th className="px-3 py-2.5 text-left">Registration</th>
                                    <th className="px-3 py-2.5 text-left">Make / Model</th>
                                    <th className="px-3 py-2.5 text-left">Site</th>
                                    <th className="px-3 py-2.5 text-left">Status</th>
                                    <th className="px-3 py-2.5 text-left">Company</th>
                                    <th className="px-3 py-2.5 text-right"><span className="sr-only">Actions</span></th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-50 bg-white">
                                {shown.map(v => (
                                    <tr key={v.id} className="hover:bg-gray-50">
                                        <td className="px-3 py-2.5 font-mono font-medium text-gray-900">{v.registration_number}</td>
                                        <td className="px-3 py-2.5 text-gray-700 max-w-[9rem] truncate" title={[v.make, v.model].filter(Boolean).join(' ')}>
                                            {[v.make, v.model].filter(Boolean).join(' ') || '—'}
                                        </td>
                                        <td className="px-3 py-2.5 text-gray-500 max-w-[8rem] truncate" title={v.vehicle_sites?.map(vs => vs.site_name).join(', ')}>
                                            {v.vehicle_sites?.map(vs => vs.site_name).join(', ') || '—'}
                                        </td>
                                        <td className="px-3 py-2.5">
                                            {v.is_active
                                                ? <span className="px-2 py-0.5 text-xs rounded-full bg-green-100 text-green-700">Active</span>
                                                : <span className="px-2 py-0.5 text-xs rounded-full bg-gray-100 text-gray-500">Inactive</span>}
                                        </td>
                                        <td className="px-3 py-2.5">
                                            <span className={`px-2 py-0.5 text-xs rounded-full whitespace-nowrap ${companyColor(v.company)}`}>
                                                {companyLabel(v.company)}
                                            </span>
                                        </td>
                                        <td className="px-3 py-2.5">
                                            <div className="flex items-center justify-end gap-2">
                                                <button
                                                    type="button"
                                                    onClick={() => setHistoryFor(v)}
                                                    title="Show this vehicle's history"
                                                    className="text-gray-400 hover:text-blue-600"
                                                >
                                                    <ClockIcon className="w-4 h-4" />
                                                    <span className="sr-only">History</span>
                                                </button>
                                                {canEdit && (
                                                    <button
                                                        type="button"
                                                        onClick={() => setChanging(v)}
                                                        className="text-xs px-2.5 py-1 text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 whitespace-nowrap"
                                                    >
                                                        {v.company === 'unknown' ? 'Assign' : 'Change'}
                                                    </button>
                                                )}
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                    <div className="px-3 py-2 bg-gray-50 text-xs text-gray-500 border-t">
                        {shown.length} {statusLabel}vehicle{shown.length !== 1 ? 's' : ''}
                    </div>
                </div>
            )}

            <VehicleCompanyHistory key={historyFor?.id ?? 'all'} vehicle={historyFor} onShowAll={() => setHistoryFor(null)} />

            {changing && <ChangeCompanyModal vehicle={changing} onClose={() => setChanging(null)} />}
        </div>
    )
}
