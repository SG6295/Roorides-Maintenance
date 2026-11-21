/**
 * No two catalog parts may share a name, ignoring capitals and extra spaces (MAIN-148):
 * "Piano Switch", "piano switch " and "Piano  Switch" are one part. The key mirrors
 * public.part_name_key(), which the unique parts.name_key column is built from — the
 * whitespace class is POSIX [[:space:]], not JS \s, so the two agree.
 */
export function partNameKey(name) {
    return String(name ?? '').replace(/[ \t\n\r\f\v]+/g, ' ').trim().toLowerCase()
}

/** The catalog part already carrying this name, other than the part being renamed. */
export function findSameNamePart(parts, name, exceptId = null) {
    const key = partNameKey(name)
    if (!key) return null
    return parts.find(p => p.id !== exceptId && partNameKey(p.name) === key) ?? null
}

/** The database refused the name because another part has it (e.g. typed at the same time). */
export function isDuplicatePartNameError(err) {
    return err?.code === '23505' && String(err?.message ?? '').includes('parts_name_key_key')
}

export function duplicatePartMessage(part) {
    return part
        ? `Already in the catalog as '${part.name.trim()}' — use that one`
        : 'Already in the catalog — use that one'
}
