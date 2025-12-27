import { useState, useRef, useEffect } from 'react'
import { format, startOfDay, endOfDay, startOfWeek, endOfWeek, startOfMonth, endOfMonth, subDays, subWeeks, subMonths } from 'date-fns'

export default function DateRangeFilter({ dateRange, onDateRangeChange }) {
  const [isOpen, setIsOpen] = useState(false)
  const [customStart, setCustomStart] = useState('')
  const [customEnd, setCustomEnd] = useState('')
  const dropdownRef = useRef(null)

  useEffect(() => {
    function handleClickOutside(event) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        setIsOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const presets = [
    {
      label: 'Today',
      getValue: () => ({
        start: format(startOfDay(new Date()), 'yyyy-MM-dd'),
        end: format(endOfDay(new Date()), 'yyyy-MM-dd'),
      }),
    },
    {
      label: 'Yesterday',
      getValue: () => ({
        start: format(startOfDay(subDays(new Date(), 1)), 'yyyy-MM-dd'),
        end: format(endOfDay(subDays(new Date(), 1)), 'yyyy-MM-dd'),
      }),
    },
    {
      label: 'Current Week',
      getValue: () => ({
        start: format(startOfWeek(new Date(), { weekStartsOn: 1 }), 'yyyy-MM-dd'),
        end: format(endOfWeek(new Date(), { weekStartsOn: 1 }), 'yyyy-MM-dd'),
      }),
    },
    {
      label: 'Last Week',
      getValue: () => ({
        start: format(startOfWeek(subWeeks(new Date(), 1), { weekStartsOn: 1 }), 'yyyy-MM-dd'),
        end: format(endOfWeek(subWeeks(new Date(), 1), { weekStartsOn: 1 }), 'yyyy-MM-dd'),
      }),
    },
    {
      label: 'Current Month',
      getValue: () => ({
        start: format(startOfMonth(new Date()), 'yyyy-MM-dd'),
        end: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
      }),
    },
    {
      label: 'Last Month',
      getValue: () => ({
        start: format(startOfMonth(subMonths(new Date(), 1)), 'yyyy-MM-dd'),
        end: format(endOfMonth(subMonths(new Date(), 1)), 'yyyy-MM-dd'),
      }),
    },
    {
      label: 'Last 3 Months',
      getValue: () => ({
        start: format(startOfMonth(subMonths(new Date(), 2)), 'yyyy-MM-dd'),
        end: format(endOfMonth(new Date()), 'yyyy-MM-dd'),
      }),
    },
  ]

  const handlePresetClick = (preset) => {
    const range = preset.getValue()
    onDateRangeChange(range)
    setIsOpen(false)
  }

  const handleCustomApply = () => {
    if (customStart && customEnd) {
      onDateRangeChange({ start: customStart, end: customEnd })
      setIsOpen(false)
    }
  }

  const getDisplayText = () => {
    if (!dateRange.start || !dateRange.end) {
      return 'Current Month' // Default
    }

    const preset = presets.find((p) => {
      const range = p.getValue()
      return range.start === dateRange.start && range.end === dateRange.end
    })

    if (preset) {
      return preset.label
    }

    return `${format(new Date(dateRange.start), 'MMM d')} - ${format(new Date(dateRange.end), 'MMM d')}`
  }

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center gap-2 px-4 py-2.5 text-sm border border-gray-300 rounded-lg bg-white hover:bg-gray-50 min-h-[48px] whitespace-nowrap"
      >
        <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
        </svg>
        <span className="font-medium">{getDisplayText()}</span>
      </button>

      {isOpen && (
        <div className="absolute left-0 sm:right-0 sm:left-auto mt-2 w-64 bg-white rounded-lg shadow-lg border border-gray-200 z-20">
          <div className="p-2">
            {/* Presets */}
            <div className="space-y-1 mb-3">
              {presets.map((preset) => (
                <button
                  key={preset.label}
                  onClick={() => handlePresetClick(preset)}
                  className="w-full text-left px-3 py-2 text-sm rounded hover:bg-gray-100 transition-colors"
                >
                  {preset.label}
                </button>
              ))}
            </div>

            {/* Custom Range */}
            <div className="border-t pt-3">
              <p className="text-xs font-medium text-gray-700 mb-2 px-3">Custom Range</p>
              <div className="space-y-2 px-3">
                <input
                  type="date"
                  value={customStart}
                  onChange={(e) => setCustomStart(e.target.value)}
                  className="w-full px-3 py-2 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-blue-500"
                  placeholder="Start date"
                />
                <input
                  type="date"
                  value={customEnd}
                  onChange={(e) => setCustomEnd(e.target.value)}
                  className="w-full px-3 py-2 text-sm border border-gray-300 rounded focus:ring-2 focus:ring-blue-500"
                  placeholder="End date"
                />
                <button
                  onClick={handleCustomApply}
                  disabled={!customStart || !customEnd}
                  className="w-full px-3 py-2 text-sm font-medium text-white bg-blue-600 rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  Apply
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
