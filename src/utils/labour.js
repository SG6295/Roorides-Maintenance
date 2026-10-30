/**
 * Labour on a work item (MAIN-116).
 *
 * Hours are recorded per technician in `issue_labour`. Work items logged before that
 * carry a single `issues.labour_hours` with nobody attached; it counts as unattributed
 * until someone is added, after which it is ignored.
 */

const toNumber = (v) => parseFloat(v) || 0

/**
 * @param {object} issue - an issue row, optionally with `issue_labour` embedded
 * @returns {{ hours: number, unattributed: number }}
 */
export function issueLabourHours(issue) {
    const rows = issue?.issue_labour || []
    if (rows.length > 0) {
        return { hours: rows.reduce((s, r) => s + toNumber(r.hours), 0), unattributed: 0 }
    }
    const legacy = toNumber(issue?.labour_hours)
    return { hours: legacy, unattributed: legacy }
}

/** Total hours across a list of issues. */
export function totalLabourHours(issues) {
    return (issues || []).reduce((s, i) => s + issueLabourHours(i).hours, 0)
}

/** Distinct technician names on a list of issues, in the order they first appear. */
export function labourTechnicianNames(issues) {
    const names = []
    for (const issue of issues || []) {
        for (const row of issue.issue_labour || []) {
            const name = row.technician?.name
            if (name && !names.includes(name)) names.push(name)
        }
    }
    return names
}

/** 2 → "2", 2.5 → "2.5", 2.25 → "2.25" */
export function formatHours(hours) {
    return String(Math.round(hours * 100) / 100)
}

/** "Mechanical Manoj" → "MM" */
export function initials(name) {
    return (name || '')
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map(w => w[0].toUpperCase())
        .join('')
}
