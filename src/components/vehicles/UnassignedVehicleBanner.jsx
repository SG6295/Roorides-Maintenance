import { Link } from 'react-router-dom'
import { ExclamationTriangleIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../../hooks/useAuth'
import { unassignedVehicleMessage } from '../../constants/vehicleCompanies'

/**
 * Shown on a ticket or job card whose vehicle is still Unknown (MAIN-155). The page turns
 * its actions off; the database refuses them anyway (guard_unassigned_vehicle).
 */
export default function UnassignedVehicleBanner({ registrationNumber }) {
    const { userProfile } = useAuth()
    const canAssign = ['finance', 'super_admin'].includes(userProfile?.role)

    return (
        <div role="alert" className="flex items-start gap-3 rounded-xl bg-amber-50 border border-amber-200 px-4 py-3">
            <ExclamationTriangleIcon className="w-5 h-5 text-amber-600 flex-shrink-0 mt-0.5" />
            <div className="text-sm">
                <p className="font-medium text-amber-900">{unassignedVehicleMessage(registrationNumber)}</p>
                <p className="text-amber-800 mt-0.5">
                    Nothing on this page can be changed until the vehicle is assigned to a company.
                    {canAssign && (
                        <> <Link to="/settings/vehicle-registration" className="underline font-medium">Assign it in the Vehicle Registration Master</Link>.</>
                    )}
                </p>
            </div>
        </div>
    )
}
