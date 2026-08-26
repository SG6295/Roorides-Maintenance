/**
 * The one place a site is turned into human-readable text.
 *
 * `sites.name` is the short code from the Roorides vehicle feed (CSS, MSDGS, TSB) —
 * unreadable to a supervisor who only knows their school by its real name. display_name
 * and corp_id come from the Roorides corporation mapping and may be absent, either
 * because the site predates the mapping or because the feed has no matching corporation,
 * so every extra part is appended only when present.
 *
 * Search relies on this too: SearchableSelect and FilterSelect substring-match the label,
 * so code, full name and corp id all become searchable purely by being in the string.
 *
 *   { name: 'CHIMES', display_name: 'Chimes Montessori', corp_id: 232 }
 *     → 'CHIMES — Chimes Montessori — 232'
 *   { name: 'CHIMES' } → 'CHIMES'
 */
export function formatSiteLabel(site) {
    if (!site) return ''

    const parts = [site.name]
    if (site.display_name) parts.push(site.display_name)
    if (site.corp_id !== null && site.corp_id !== undefined) parts.push(String(site.corp_id))

    return parts.join(' — ')
}
