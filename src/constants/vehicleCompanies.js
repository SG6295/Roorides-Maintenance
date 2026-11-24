/**
 * The company a vehicle is registered to (MAIN-155, epic MAIN-154). Mirrors
 * `vehicles_company_check` — change both together.
 *
 * A vehicle is Unknown until finance assigns it in the Vehicle Registration Master, and
 * while it is Unknown the database refuses any work on it (`guard_unassigned_vehicle`).
 */
export const UNKNOWN_COMPANY = 'unknown'

export const VEHICLE_COMPANIES = [
    { value: 'nvs_travels', label: 'NVS Travels', color: 'bg-blue-100 text-blue-800' },
    { value: 'nvs_travel_solutions', label: 'NVS Travel Solutions Pvt Ltd', color: 'bg-purple-100 text-purple-800' },
    { value: UNKNOWN_COMPANY, label: 'Unknown', color: 'bg-amber-100 text-amber-800' },
]

/** The two companies a vehicle can be assigned or moved to — never back to Unknown. */
export const ASSIGNABLE_COMPANIES = VEHICLE_COMPANIES.filter(c => c.value !== UNKNOWN_COMPANY)

const BY_VALUE = new Map(VEHICLE_COMPANIES.map(c => [c.value, c]))

export const companyLabel = value => BY_VALUE.get(value)?.label ?? value ?? '—'
export const companyColor = value => BY_VALUE.get(value)?.color ?? 'bg-gray-100 text-gray-700'

/** True when work on this vehicle is blocked. A vehicle not found (null) is not blocked. */
export const isUnassignedVehicle = vehicle => vehicle?.company === UNKNOWN_COMPANY

/** The same words `assert_vehicle_assigned` raises. */
export const unassignedVehicleMessage = registration =>
    `Kindly contact finance to assign vehicle ${registration} in order to proceed.`

/**
 * What a change from `from` to `to` is: the first assignment of an Unknown vehicle (no
 * sale — it always belonged there) or a sale between the two companies.
 */
export const changeKind = (from, to) =>
    !to || to === from ? null : from === UNKNOWN_COMPANY ? 'assignment' : 'sale'

/** Field errors for a sale's value (incl. GST) and GST %, as set_vehicle_company checks them. */
export function saleErrors({ saleValue, gstPercent }) {
    const errors = {}
    const value = String(saleValue ?? '').trim()
    const gst = String(gstPercent ?? '').trim()
    if (!/^[0-9]{1,12}(\.[0-9]{1,2})?$/.test(value) || Number(value) <= 0) {
        errors.saleValue = 'Enter the sale value, including GST.'
    }
    if (!/^[0-9]{1,3}(\.[0-9]{1,2})?$/.test(gst) || Number(gst) > 100) {
        errors.gstPercent = 'Enter the GST % of the sale, between 0 and 100.'
    }
    return errors
}
