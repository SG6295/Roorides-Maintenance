import { useState, useRef, useEffect } from 'react'

/**
 * FilterSelect — custom-styled dropdown for filter bars.
 * Matches the visual style of DateRangeFilter.
 *
 * For form inputs inside modals/forms, use CustomSelect (HeadlessUI Listbox) instead.
 *
 * Props:
 *   options     — array of { value, label }
 *   value       — currently selected value ('' = show placeholder)
 *   onChange    — (value: string) => void
 *   placeholder — text when nothing selected, e.g. 'All Statuses'
 *   minWidth    — tailwind min-w class, default 'min-w-[140px]'
 */
export default function FilterSelect({ options = [], value, onChange, placeholder = 'All', minWidth = 'min-w-[140px]' }) {
  const [isOpen, setIsOpen] = useState(false)
  const ref = useRef(null)

  useEffect(() => {
    function handleClickOutside(e) {
      if (ref.current && !ref.current.contains(e.target)) setIsOpen(false)
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const selected = options.find(o => o.value === value)
  const displayText = selected ? selected.label : placeholder

  return (
    <div className={`relative ${minWidth}`} ref={ref}>
      <button
        type="button"
        onClick={() => setIsOpen(prev => !prev)}
        className="flex items-center justify-between gap-2 w-full px-4 py-2.5 text-sm border border-gray-300 rounded-lg bg-white hover:bg-gray-50 min-h-[48px] font-medium whitespace-nowrap"
      >
        <span className={selected ? 'text-gray-900' : 'text-gray-700'}>{displayText}</span>
        <svg
          className={`w-5 h-5 text-gray-600 flex-shrink-0 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none" stroke="currentColor" viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute left-0 mt-2 w-full min-w-[160px] bg-white rounded-lg shadow-lg border border-gray-200 z-30 max-h-72 overflow-y-auto">
          <div className="p-1">
            {options.map(option => (
              <button
                key={option.value}
                type="button"
                onClick={() => { onChange(option.value); setIsOpen(false) }}
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
