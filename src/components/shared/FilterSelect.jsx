import { useState, useRef, useEffect, useMemo } from 'react'
import { MagnifyingGlassIcon } from '@heroicons/react/24/outline'

/**
 * FilterSelect — custom-styled dropdown for filter bars.
 * Matches the visual style of DateRangeFilter.
 *
 * For form inputs inside modals/forms, use CustomSelect (HeadlessUI Listbox) instead.
 *
 * Long lists get a search box automatically. Site filters run to ~68 unreadable short
 * codes; a three-option Status filter would be worse with a search box on it, hence the
 * threshold rather than always-on. Search lives here rather than swapping these call
 * sites to SearchableSelect, which would break the CustomSelect/FilterSelect convention.
 *
 * The panel sizes to its own content (`w-max`), not to the trigger: a site label is
 * `CODE — Full Name — corp id` and wrapped over four lines at button width. It stays at
 * least as wide as the trigger and is capped so it cannot leave the viewport on a phone;
 * beyond that cap options wrap, which beats truncating the name you are picking by.
 * The trigger caps in the other direction — an untruncated long label stretched the
 * button across the filter bar and reflowed the controls beside it.
 *
 * Props:
 *   options     — array of { value, label }
 *   value       — currently selected value ('' = show placeholder)
 *   onChange    — (value: string) => void
 *   placeholder — text when nothing selected, e.g. 'All Statuses'
 *   minWidth    — tailwind min-w class, default 'min-w-[140px]'
 *   searchable  — override the automatic threshold (true/false)
 */
const SEARCH_THRESHOLD = 10

export default function FilterSelect({ options = [], value, onChange, placeholder = 'All', minWidth = 'min-w-[140px]', searchable }) {
  const [isOpen, setIsOpen] = useState(false)
  const [query, setQuery] = useState('')
  const ref = useRef(null)
  const searchRef = useRef(null)

  const showSearch = searchable ?? options.length > SEARCH_THRESHOLD

  useEffect(() => {
    function handleClickOutside(e) {
      if (ref.current && !ref.current.contains(e.target)) {
        setIsOpen(false)
        setQuery('')
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  useEffect(() => {
    if (isOpen && showSearch) searchRef.current?.focus()
  }, [isOpen, showSearch])

  // Reopening should start from the full list, not the last search. Cleared on every
  // close rather than on open, so the reset never happens during a render pass.
  const close = () => {
    setIsOpen(false)
    setQuery('')
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return options
    return options.filter(o => String(o.label).toLowerCase().includes(q))
  }, [options, query])

  const selected = options.find(o => o.value === value)
  const displayText = selected ? selected.label : placeholder

  return (
    <div className={`relative ${minWidth}`} ref={ref}>
      <button
        type="button"
        onClick={() => (isOpen ? close() : setIsOpen(true))}
        className="flex items-center justify-between gap-2 w-full max-w-[16rem] px-4 py-2.5 text-sm border border-gray-300 rounded-lg bg-white hover:bg-gray-50 min-h-[48px] font-medium whitespace-nowrap"
      >
        <span className={`truncate ${selected ? 'text-gray-900' : 'text-gray-700'}`}>{displayText}</span>
        <svg
          className={`w-5 h-5 text-gray-600 flex-shrink-0 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none" stroke="currentColor" viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute left-0 mt-2 min-w-full w-max max-w-[calc(100vw-2rem)] sm:max-w-md bg-white rounded-lg shadow-lg border border-gray-200 z-30">
          {showSearch && (
            <div className="relative border-b border-gray-100 p-2">
              <MagnifyingGlassIcon className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" />
              <input
                ref={searchRef}
                type="text"
                value={query}
                onChange={e => setQuery(e.target.value)}
                placeholder="Search..."
                autoComplete="off"
                className="w-full rounded border border-gray-300 py-1.5 pl-8 pr-2 text-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
              />
            </div>
          )}
          <div className="p-1 max-h-72 overflow-y-auto">
            {filtered.length === 0 && (
              <p className="px-3 py-2.5 text-sm text-gray-500">No matches.</p>
            )}
            {filtered.map(option => (
              <button
                key={option.value}
                type="button"
                onClick={() => { onChange(option.value); close() }}
                className={`w-full text-left px-3 py-2.5 text-sm rounded hover:bg-gray-100 transition-colors ${
                  value === option.value ? 'bg-blue-50 text-blue-700 font-medium' : 'text-gray-700'
                }`}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
