/**
 * Issue categories (MAIN-140). Mirrors the issue_category enum — keep in step.
 *
 * Other is retired: no issue can be added as Other or moved to it (guard_issue_category),
 * and a new SLA version has no Turnaround Time for it. Past Other issues keep it, so it
 * stays filterable.
 */
export const ISSUE_CATEGORIES = ['Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS', 'Emission']

export const RETIRED_ISSUE_CATEGORIES = ['Other']

/** Every category an issue can carry, retired ones included — for filtering history. */
export const ALL_ISSUE_CATEGORIES = [...ISSUE_CATEGORIES, ...RETIRED_ISSUE_CATEGORIES]

/** What an issue can be set to: the current categories, plus its own if that is retired. */
export function categoryOptions(current) {
    return RETIRED_ISSUE_CATEGORIES.includes(current) ? [...ISSUE_CATEGORIES, current] : ISSUE_CATEGORIES
}
