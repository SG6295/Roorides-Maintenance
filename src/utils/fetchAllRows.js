/** Rows per request. Must not exceed the API's Max rows — see fetchAllRows. */
export const PAGE_SIZE = 1000

/**
 * Every row a query matches, fetched in batches.
 *
 * The Supabase API answers any single request with at most 1,000 rows (the project's
 * "Max rows" setting) and says nothing about the rest — a plain `await query` on a bigger
 * table quietly returns the first 1,000 in sort order. That is how the Issues page came to
 * show nothing after early August, and the Tickets page nothing before mid-August (MAIN-83).
 *
 * `buildQuery` must return a fresh query each time it is called, so no batch inherits
 * another's range. Its order must be stable — tie-break on `id` after any non-unique
 * sort — or a row can slip between two batches.
 *
 * A row inserted while the batches are loading shifts everything after it by one, which
 * would show the boundary row twice, so rows are de-duplicated by `id`.
 *
 * PAGE_SIZE must not exceed Max rows: a short batch is read as the end, so a lower server
 * cap would end the loop after the first batch and bring the silent truncation back.
 *
 * @param {() => import('@supabase/postgrest-js').PostgrestFilterBuilder} buildQuery
 * @returns {Promise<object[]>}
 */
export async function fetchAllRows(buildQuery) {
    const rows = []
    const seen = new Set()

    for (let from = 0; ; from += PAGE_SIZE) {
        const { data, error } = await buildQuery().range(from, from + PAGE_SIZE - 1)
        if (error) throw error

        for (const row of data || []) {
            if (seen.has(row.id)) continue
            seen.add(row.id)
            rows.push(row)
        }

        if (!data || data.length < PAGE_SIZE) return rows
    }
}
