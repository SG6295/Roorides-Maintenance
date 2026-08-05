import { PASSWORD_WORDS } from './wordlist'

export const ROLE_LABELS = {
    super_admin: 'Super Admin',
    maintenance_exec: 'Maintenance Exec',
    supervisor: 'Supervisor',
    mechanic: 'Mechanic',
    electrician: 'Electrician',
    finance: 'Finance',
}

export const ROLE_COLORS = {
    super_admin: 'bg-purple-100 text-purple-800',
    maintenance_exec: 'bg-indigo-100 text-indigo-800',
    supervisor: 'bg-blue-100 text-blue-800',
    mechanic: 'bg-gray-100 text-gray-800',
    electrician: 'bg-yellow-100 text-yellow-800',
    finance: 'bg-green-100 text-green-800',
}

// Which roles a given role may create or edit. Kept in step with the matrices in
// supabase/functions/create-user and update-user — the server checks are the ones
// that actually enforce this; these only shape the UI.
export const MANAGEABLE_BY = {
    super_admin: ['super_admin', 'maintenance_exec', 'finance', 'supervisor', 'mechanic', 'electrician'],
    maintenance_exec: ['supervisor', 'mechanic', 'electrician'],
}

/** Role options for CustomSelect, scoped to what the given role may assign. */
export function roleOptions(callerRole) {
    return (MANAGEABLE_BY[callerRole] || []).map(role => ({
        id: role,
        name: ROLE_LABELS[role],
        value: role,
    }))
}

export const MIN_PASSWORD_LENGTH = 8

/** Uniform random integer in [0, max), rejecting the biased tail of the range. */
function randomInt(max) {
    const limit = Math.floor(0xffffffff / max) * max
    const buf = new Uint32Array(1)
    let value
    do {
        crypto.getRandomValues(buf)
        value = buf[0]
    } while (value >= limit)
    return value % max
}

const capitalize = (word) => word.charAt(0).toUpperCase() + word.slice(1)

/**
 * Generates a temporary password that can be read out over the phone —
 * "Mango-River-47" rather than "k3f9x2q1ZM".
 *
 * Two words plus two digits from a ~400 word list is roughly 16M combinations:
 * weaker than a random string, and nothing forces a change at first login, so
 * these are only appropriate as admin-issued temporary credentials.
 */
export function generatePassword() {
    const first = capitalize(PASSWORD_WORDS[randomInt(PASSWORD_WORDS.length)])
    let second = capitalize(PASSWORD_WORDS[randomInt(PASSWORD_WORDS.length)])
    while (second === first) {
        second = capitalize(PASSWORD_WORDS[randomInt(PASSWORD_WORDS.length)])
    }
    const digits = String(randomInt(100)).padStart(2, '0')
    return `${first}-${second}-${digits}`
}
