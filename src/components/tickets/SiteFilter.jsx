import { useState, useRef, useEffect } from 'react'

export default function SiteFilter({ sites, selectedSite, onSiteChange }) {
  const [isOpen, setIsOpen] = useState(false)
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

  const handleSiteSelect = (siteName) => {
    onSiteChange(siteName)
    setIsOpen(false)
  }

  const getDisplayText = () => {
    return selectedSite || 'All Sites'
  }

  return (
    <div className="relative" ref={dropdownRef}>
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center justify-between gap-2 px-4 py-2.5 text-sm border border-gray-300 rounded-lg bg-white hover:bg-gray-50 min-h-[48px] whitespace-nowrap font-medium min-w-[140px]"
      >
        <span>{getDisplayText()}</span>
        <svg
          className={`w-5 h-5 text-gray-600 transition-transform ${isOpen ? 'rotate-180' : ''}`}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute left-0 mt-2 w-full min-w-[200px] bg-white rounded-lg shadow-lg border border-gray-300 z-20 max-h-[300px] overflow-y-auto">
          <div className="p-1">
            <button
              onClick={() => handleSiteSelect('')}
              className={`w-full text-left px-3 py-2.5 text-sm rounded hover:bg-gray-100 transition-colors ${
                !selectedSite ? 'bg-blue-50 text-blue-700 font-medium' : ''
              }`}
            >
              All Sites
            </button>
            {sites.map((site) => (
              <button
                key={site.id}
                onClick={() => handleSiteSelect(site.name)}
                className={`w-full text-left px-3 py-2.5 text-sm rounded hover:bg-gray-100 transition-colors ${
                  selectedSite === site.name ? 'bg-blue-50 text-blue-700 font-medium' : ''
                }`}
              >
                {site.name}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
