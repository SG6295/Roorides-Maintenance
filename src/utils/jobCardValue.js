/**
 * Job card value and spare cost (MAIN-158).
 *
 * The database works both out — public.job_card_value(job_cards) and
 * public.spare_cost(issue_parts), read as PostgREST computed fields — and returns them only
 * to maintenance exec, super_admin and finance. This file only words them.
 */

export const COST_VIEWER_ROLES = ['maintenance_exec', 'super_admin', 'finance']

export const canSeeCosts = role => COST_VIEWER_ROLES.includes(role)

export const rupees = v =>
    `₹${Number(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/**
 * What to show for a job card's value.
 * In-house: its spares at first-in-first-out cost incl. GST (₹0.00 with none; NULL means a
 * spare has no price). Outsourced: the invoice's Approved Amount, or the multi-vehicle
 * invoice lines linked to it; NULL means no invoice yet.
 */
export function jobCardValueLabel(jobCard) {
    const v = jobCard?.value
    if (v !== null && v !== undefined) return { text: rupees(v), muted: false }
    return jobCard?.type === 'Outsource'
        ? { text: 'Invoice pending', muted: true }
        : { text: 'Price missing', muted: true }
}

export function jobCardValueBasis(jobCard) {
    return jobCard?.type === 'Outsource'
        ? 'Approved Amount of its invoice'
        : 'Spares at first-in-first-out cost, incl. GST'
}

/**
 * A spare refused because some of its part's stock has no price (HINT PART_NEEDS_PRICE).
 * Returns { partId, partName, unit, company, quantity } from the error's detail, or null.
 */
export function needsPriceError(error) {
    if (error?.hint !== 'PART_NEEDS_PRICE') return null
    try {
        const d = JSON.parse(error.details)
        return {
            partId: d.part_id,
            partName: d.part_name,
            unit: d.unit,
            company: d.company,
            quantity: Number(d.quantity),
        }
    } catch {
        return { partId: null, partName: null, unit: null, company: null, quantity: null }
    }
}

/** The price form's check. Returns an error message, or null when it can be saved. */
export function priceFormError({ unitPrice, gstRate }) {
    if (unitPrice === '' || unitPrice === null || unitPrice === undefined) return 'Enter the price for one unit.'
    const p = Number(unitPrice)
    if (Number.isNaN(p) || p < 0) return 'Enter a price of 0 or more.'
    if (gstRate === '' || gstRate === null || gstRate === undefined) return 'Choose the GST %.'
    return null
}

/**
 * A spare that needs stock from the other company (MAIN-159): HINT NEEDS_TRANSFER (asked
 * for the first time) or TRANSFER_CHANGED (the confirmed amount no longer matches).
 * Returns the quote from the error's detail — { changed, partName, unit, fromCompany,
 * toCompany, quantity, ownQuantity, amount, gst, gstBreakdown, jobCardNumber, vehicle } —
 * or null. `amount` is what add_spare must be sent back to confirm.
 */
export function transferQuoteError(error) {
    if (error?.hint !== 'NEEDS_TRANSFER' && error?.hint !== 'TRANSFER_CHANGED') return null
    let d
    try {
        d = JSON.parse(error.details)
    } catch {
        return null
    }
    if (d?.amount === undefined || d?.amount === null) return null
    return {
        changed: error.hint === 'TRANSFER_CHANGED',
        message: error.message,
        partName: d.part_name,
        unit: d.unit,
        fromCompany: d.from_company,
        toCompany: d.to_company,
        quantity: Number(d.quantity),
        ownQuantity: Number(d.own_quantity ?? 0),
        amount: Number(d.amount),
        gst: Number(d.gst ?? 0),
        gstBreakdown: (d.gst_breakdown ?? []).map(r => ({
            rate: Number(r.rate),
            beforeGst: Number(r.before_gst),
            gst: Number(r.gst),
            inclGst: Number(r.incl_gst),
        })),
        jobCardNumber: d.job_card_number,
        vehicle: d.vehicle,
    }
}
