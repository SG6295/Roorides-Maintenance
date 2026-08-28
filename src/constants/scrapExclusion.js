/**
 * Scrap exclusion reasons, shared by the closure modal and the Parts Catalog.
 */

export const EXCLUSION_REASON_OPTIONS = [
    { value: 'consumable',           label: 'Consumable' },
    { value: 'destroyed_on_removal', label: 'Destroyed on removal' },
    { value: 'retained_by_vendor',   label: 'Retained by vendor' },
    { value: 'other',                label: 'Other' },
]

/**
 * The subset a part may carry as a standing default in the part master.
 *
 * `other` requires a per-exclusion note (MAIN-57) that the part master has
 * nowhere to store, so a default of `other` would pre-fill the closure modal
 * into a state the RPC rejects on submit. `retained_by_vendor` describes what
 * happened on one outsourced job, not a standing property of the part.
 *
 * Mirrors the parts_default_exclusion_reason_check constraint — keep in step.
 */
const DEFAULT_ELIGIBLE = ['consumable', 'destroyed_on_removal']

export const DEFAULT_EXCLUSION_REASON_OPTIONS = EXCLUSION_REASON_OPTIONS
    .filter(o => DEFAULT_ELIGIBLE.includes(o.value))

export function exclusionReasonLabel(value) {
    return EXCLUSION_REASON_OPTIONS.find(o => o.value === value)?.label ?? value
}
