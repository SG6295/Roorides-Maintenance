import { useState, useRef, useEffect, useMemo } from 'react'
import { MagnifyingGlassIcon, CheckIcon } from '@heroicons/react/24/outline'

/**
 * MultiFilterSelect — the multi-choice sibling of FilterSelect, for filter bars.
 * Same trigger, panel, search box and reset row; rows carry a checkbox instead and the
 * panel stays open while you tick, so picking five sites is not five round trips.
 *
 * `[]` is the no-filter value — an empty selection means "all", never "none". The
 * reset row carries the placeholder text, clears every tick, and sits outside the
 * search results so a query can never hide the way back (see FilterSelect).
 *
 * The trigger summarises rather than lists: one pick shows its label, more show
 * "N <noun>" — a joined list of `CODE — Full Name — corp id` labels is unreadable.
 *
 * Props:
 *   options     — array of { value, label }
 *   value       — array of selected values ([] = show placeholder)
 *   onChange    — (values: string[]) => void, in the order of `options`
 *   placeholder — text when nothing selected, e.g. 'All Sites'
 *   noun        — plural for the summary, e.g. 'sites' → "3 sites"
 *   minWidth    — tailwind min-w class, default 'min-w-[140px]'
 *   searchable  — override the automatic threshold (true/false)
 */
const SEARCH_THRESHOLD = 10

export default function MultiFilterSelect({ options = [], value = [], onChange, placeholder = 'All', noun = 'selected', minWidth = 'min-w-[140px]', searchable }) {
  const [isOpen, setIsOpen] = useState(false)
  const [query, setQuery] = useState('')
  const ref = useRef(null)
  const searchRef = useRef(null)

  const showSearch = searchable ?? options.length > SEARCH_THRESHOLD
  const selectedSet = useMemo(() => new Set(value), [value])

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

  const close = () => {
    setIsOpen(false)
    setQuery('')
  }

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return options
    return options.filter(o => String(o.label).toLowerCase().includes(q))
  }, [options, query])

  // Rebuilt from `options` so the emitted order is stable and a value can never repeat.
  const toggle = (optionValue) => {
    const next = new Set(selectedSet)
    if (next.has(optionValue)) next.delete(optionValue)
    else next.add(optionValue)
    onChange(options.filter(o => next.has(o.value)).map(o => o.value))
  }

  const selectedOptions = options.filter(o => selectedSet.has(o.value))
  const displayText = selectedOptions.length === 0
    ? placeholder
    : selectedOptions.length === 1
      ? selectedOptions[0].label
      : `${selectedOptions.length} ${noun}`

  return (
    <div className={`relative ${minWidth}`} ref={ref}>
      <button
        type="button"
        onClick={() => (isOpen ? close() : setIsOpen(true))}
        className="flex items-center justify-between gap-2 w-full max-w-[16rem] px-4 py-2.5 text-sm border border-gray-300 rounded-lg bg-white hover:bg-gray-50 min-h-[48px] font-medium whitespace-nowrap"
      >
        <span className={`truncate ${selectedOptions.length ? 'text-gray-900' : 'text-gray-700'}`}>{displayText}</span>
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
            {/* Outside `filtered` on purpose — a search query must never hide the way back. */}
            <button
              type="button"
              onClick={() => { onChange([]); close() }}
              className={`w-full text-left px-3 py-2.5 text-sm rounded hover:bg-gray-100 transition-colors ${
                selectedOptions.length === 0 ? 'bg-blue-50 text-blue-700 font-medium' : 'text-gray-700'
              }`}
            >
              {placeholder}
            </button>
            {filtered.length === 0 && (
              <p className="px-3 py-2.5 text-sm text-gray-500">No matches.</p>
            )}
            {filtered.map(option => {
              const checked = selectedSet.has(option.value)
              return (
                <button
                  key={option.value}
                  type="button"
                  role="menuitemcheckbox"
                  aria-checked={checked}
                  onClick={() => toggle(option.value)}
                  className={`w-full flex items-center gap-3 text-left px-3 py-2.5 text-sm rounded hover:bg-gray-100 transition-colors ${
                    checked ? 'text-blue-700 font-medium' : 'text-gray-700'
                  }`}
                >
                  <span className={`flex h-4 w-4 flex-shrink-0 items-center justify-center rounded border ${
                    checked ? 'border-blue-600 bg-blue-600' : 'border-gray-300 bg-white'
                  }`}>
                    {checked && <CheckIcon className="h-3 w-3 text-white" strokeWidth={3} />}
                  </span>
                  {option.label}
                </button>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}
