import { format, parseISO } from 'date-fns'

/**
 * Parsing timestamps that come back from Postgres.
 *
 * The database runs with TimeZone = UTC, and most of our columns are
 * `timestamp without time zone`, so a value arrives as "2026-08-11 13:56:34" — an
 * instant in UTC, but with nothing in the string that says so. JavaScript parses an
 * offset-less string as *local* time, so that instant renders as 13:56 IST when it was
 * really 19:26 IST. Every naive column is silently 5.5 hours early for an Indian user.
 *
 * So: tag naive values as UTC before parsing, and let the browser render them in the
 * viewer's zone. Values that already carry an offset (our `timestamptz` columns) are
 * left alone — they are already correct, and appending anything would double-shift them.
 *
 * @param {string|Date|null|undefined} value
 * @returns {Date|null}
 */
export function toDate(value) {
    if (!value) return null
    if (value instanceof Date) return value

    const s = String(value).trim()

    // A bare date is a calendar date, not an instant — an invoice dated the 11th is the
    // 11th everywhere. Parsing it as local midnight keeps it on the right day; treating
    // it as UTC would drag it backwards for anyone west of Greenwich.
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return parseISO(s)

    const iso = s.includes('T') ? s : s.replace(' ', 'T')
    const hasZone = /([zZ]|[+-]\d{2}:?\d{2})$/.test(iso)
    return parseISO(hasZone ? iso : `${iso}Z`)
}

/** Date and time, e.g. "11 Aug 2026, 19:26". */
export function formatDateTime(value, fallback = '—') {
    const d = toDate(value)
    return d ? format(d, 'dd MMM yyyy, HH:mm') : fallback
}

/** Date only, e.g. "11 Aug 2026". */
export function formatDate(value, fallback = '—') {
    const d = toDate(value)
    return d ? format(d, 'dd MMM yyyy') : fallback
}

/** Any date-fns pattern, for the odd case that needs one. */
export function formatAs(value, pattern, fallback = '—') {
    const d = toDate(value)
    return d ? format(d, pattern) : fallback
}

/**
 * The local calendar date of an instant, as "yyyy-MM-dd".
 *
 * For date-range filters, which compare against `<input type="date">` values — those are
 * always local calendar dates. Bucketing a timestamp by its UTC date instead puts
 * anything logged after 18:30 IST into the following day, so a month filter quietly
 * includes and excludes the wrong rows at both ends.
 */
export function dateKey(value) {
    const d = toDate(value)
    return d ? format(d, 'yyyy-MM-dd') : ''
}

/**
 * Today as "yyyy-MM-dd" in the viewer's zone.
 *
 * `new Date().toISOString().slice(0, 10)` is the tempting one-liner and it is wrong: it
 * gives the UTC date, which between midnight and 05:30 IST is still yesterday.
 */
export function todayLocal() {
    return format(new Date(), 'yyyy-MM-dd')
}
