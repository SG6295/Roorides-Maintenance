/**
 * The SLA Configuration page's draft (MAIN-136). Nothing on the page saves on its own:
 * edits collect here until Review changes, and are sent to the database as one change
 * through preview_sla_changes / apply_sla_change.
 *
 * Acceptance SLA Threshold, Weekly Offs and Turnaround Time form a version and are
 * always sent whole. Holidays are not versioned; they travel as adds and removes.
 */

export const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

const ruleKey = (r) => `${r.severity}|${r.category}`

export const workingDays = (n) => `${n} working day${n === 1 ? '' : 's'}`

/** "Sat, Sun" — Monday first, the way the week is read here. */
export function formatWeeklyOffs(offs) {
    if (!offs?.length) return 'None'
    return [...offs].sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7)).map(d => DAY_NAMES[d]).join(', ')
}

/** A fresh draft from a version and its Turnaround rows. Numbers are kept as typed text. */
export function draftFromVersion(version, turnaround) {
    return {
        acceptanceDays: String(version.acceptance_days),
        weeklyOffs: [...version.weekly_offs].sort(),
        turnaround: Object.fromEntries(turnaround.map(r => [ruleKey(r), String(r.sla_days)])),
        holidaysAdd: [],
        holidaysRemove: [],
    }
}

const isDays = (text) => /^\d+$/.test(String(text).trim()) && +text >= 1 && +text <= 365

/** What has to be fixed before the draft can be reviewed. Empty when it is fine. */
export function draftErrors(draft) {
    const errors = []
    if (!isDays(draft.acceptanceDays)) errors.push('Acceptance SLA Threshold must be a whole number from 1 to 365.')
    if (draft.weeklyOffs.length >= 7) errors.push('Weekly Offs must leave at least one working day.')
    if (Object.values(draft.turnaround).some(v => !isDays(v))) {
        errors.push('Every Turnaround Time must be a whole number from 1 to 365.')
    }
    return errors
}

/**
 * Old → new for every changed versioned setting, in page order. Empty when the version
 * would be unchanged.
 */
export function versionChanges(version, turnaround, draft) {
    const changes = []
    if (+draft.acceptanceDays !== version.acceptance_days) {
        changes.push({ label: 'Acceptance SLA Threshold', from: workingDays(version.acceptance_days), to: workingDays(+draft.acceptanceDays) })
    }
    if (formatWeeklyOffs(draft.weeklyOffs) !== formatWeeklyOffs(version.weekly_offs)) {
        changes.push({ label: 'Weekly Offs', from: formatWeeklyOffs(version.weekly_offs), to: formatWeeklyOffs(draft.weeklyOffs) })
    }
    for (const r of turnaround) {
        const next = +draft.turnaround[ruleKey(r)]
        if (next !== r.sla_days) {
            changes.push({
                label: `Turnaround Time — ${r.severity} ${r.category}`,
                from: workingDays(r.sla_days),
                to: workingDays(next),
            })
        }
    }
    return changes
}

/** Holiday adds and removes as review lines. */
export function holidayChanges(holidays, draft) {
    return [
        ...draft.holidaysAdd.map(h => ({ action: 'add', date: h.date, description: h.description })),
        ...draft.holidaysRemove.map(date => ({
            action: 'remove', date, description: holidays.find(h => h.date === date)?.description ?? '',
        })),
    ]
}

export function hasChanges(version, turnaround, draft) {
    return versionChanges(version, turnaround, draft).length > 0
        || draft.holidaysAdd.length > 0 || draft.holidaysRemove.length > 0
}

/**
 * The p_change payload. `startsAt` is an ISO instant or null (now); it only matters when
 * the version changed. `reason` is left out for the preview.
 */
export function buildChange(version, turnaround, draft, { reason, startsAt } = {}) {
    const versionChanged = versionChanges(version, turnaround, draft).length > 0
    return {
        base_version_id: version.id,
        ...(reason !== undefined && { reason }),
        starts_at: versionChanged ? (startsAt ?? null) : null,
        version: versionChanged ? {
            acceptance_days: +draft.acceptanceDays,
            weekly_offs: [...draft.weeklyOffs].sort(),
            turnaround: turnaround.map(r => ({
                category: r.category, severity: r.severity, sla_days: +draft.turnaround[ruleKey(r)],
            })),
        } : null,
        holidays_add: draft.holidaysAdd.map(h => ({ date: h.date, description: h.description || null })),
        holidays_remove: draft.holidaysRemove,
    }
}

/** "84.6%", or "—" when nothing was judged. */
export function onTimePercent(adhered, judged) {
    return judged ? `${((adhered / judged) * 100).toFixed(1)}%` : '—'
}

/**
 * The versions with their derived end: a version ends when the next non-cancelled one
 * (by start) starts. state: 'scheduled' | 'active' | 'ended' | 'cancelled'. Newest first.
 */
export function versionTimeline(versions, now = new Date()) {
    const live = versions.filter(v => !v.cancelled_at).sort((a, b) => new Date(a.starts_at) - new Date(b.starts_at))
    const endOf = new Map(live.map((v, i) => [v.id, live[i + 1]?.starts_at ?? null]))
    return [...versions]
        .sort((a, b) => b.version_number - a.version_number)
        .map(v => {
            const ends_at = v.cancelled_at ? null : endOf.get(v.id)
            let state = 'active'
            if (v.cancelled_at) state = 'cancelled'
            else if (new Date(v.starts_at) > now) state = 'scheduled'
            else if (ends_at && new Date(ends_at) <= now) state = 'ended'
            return { ...v, ends_at, state }
        })
}
