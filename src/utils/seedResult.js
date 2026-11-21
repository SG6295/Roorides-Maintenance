// Reads the seed-staging-from-prod response (MAIN-139). A seed succeeded only when nothing
// failed — a table or login that failed must never be shown under "Sync complete".
// Falls back to the per-table list for a response from before `failures` existed.
export function seedFailures(result) {
    if (!result) return []
    if (Array.isArray(result.failures)) return result.failures
    return (result.public ?? [])
        .filter(t => t.status === 'error')
        .map(t => ({ phase: 'table', item: t.table, error: t.error }))
}
