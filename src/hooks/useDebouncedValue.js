import { useEffect, useState } from 'react'

/**
 * A copy of `value` that only catches up once `value` has stopped changing for `delay` ms.
 *
 * Every search box in the app puts its term straight into a TanStack query key, so each
 * character was its own database query: typing a registration number fired ten, nine of
 * them for terms nobody wanted, and each new key had no cached rows so the table blanked
 * to a skeleton between characters. Feed the box itself the raw state and the query the
 * debounced copy, and typing stays instant while the server is asked once, at the pause.
 *
 * 300ms is the point where a pause between characters reads as "finished typing" without
 * the results feeling like they lag the keyboard; it is a starting number, not a law.
 *
 *   const [filters, setFilters] = useState({ search: '' })
 *   const search = useDebouncedValue(filters.search)
 *   const { data } = useVehicles({ ...filters, search })
 */
export function useDebouncedValue(value, delay = 300) {
    const [debounced, setDebounced] = useState(value)

    useEffect(() => {
        const timer = setTimeout(() => setDebounced(value), delay)
        return () => clearTimeout(timer)
    }, [value, delay])

    return debounced
}
