import { UNKNOWN_COMPANY } from '../constants/vehicleCompanies'

/**
 * The lines of a multi-vehicle invoice whose vehicle belongs to a company other than the
 * one it is billed to (MAIN-161) — mirrors save_batch_service_invoice's COMPANY_MISMATCH.
 *
 * A saved line keeps its vehicle's company from when it was saved, so it is checked only
 * when it is new, its vehicle changed, or Billed to itself changed; otherwise a vehicle
 * sold after the work would make the invoice uneditable. Unknown vehicles are left out:
 * they are refused on their own, with finance's message.
 *
 * @param {object}   args
 * @param {Array}    args.lines         form lines: { key, id, vehicle_number }
 * @param {string}   args.billedTo      the company chosen on the form ('' when none yet)
 * @param {string}   [args.savedBilledTo] the batch's saved Billed to (none for a new one)
 * @param {Map}      args.savedVehicles saved line id → its saved vehicle number
 * @param {Map}      args.companyOf     registration number → vehicle company
 * @returns {Set<string>} the keys of the lines that can't be saved
 */
export function wrongCompanyLines({ lines, billedTo, savedBilledTo, savedVehicles, companyOf }) {
    const wrong = new Set()
    if (!billedTo) return wrong
    const billedToChanged = savedBilledTo !== billedTo
    for (const line of lines) {
        const company = companyOf.get(line.vehicle_number)
        if (!company || company === UNKNOWN_COMPANY || company === billedTo) continue
        const unchanged = line.id && savedVehicles.get(line.id) === line.vehicle_number
        if (billedToChanged || !unchanged) wrong.add(line.key)
    }
    return wrong
}
