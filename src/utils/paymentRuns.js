import { addDays, format, getDay, parseISO } from 'date-fns'

/**
 * Finance releases supplier payments every Wednesday (MAIN-119) — fixed by decision,
 * not a setting. An amount due on a day goes out in the first Wednesday run on or
 * after it, and is overdue once that run has passed.
 *
 * The database's payment_run_for() makes the ledger figures; this only labels them.
 * Dates are ISO 'yyyy-MM-dd' strings, as Postgres returns them.
 */
const WEDNESDAY = 3

export function paymentRunFor(isoDate) {
    const d = parseISO(isoDate)
    return format(addDays(d, (WEDNESDAY - getDay(d) + 7) % 7), 'yyyy-MM-dd')
}

/** This week's run (today, if today is a Wednesday) and the one after. */
export function upcomingRuns(todayIso) {
    const thisRun = paymentRunFor(todayIso)
    return { thisRun, nextRun: format(addDays(parseISO(thisRun), 7), 'yyyy-MM-dd') }
}
