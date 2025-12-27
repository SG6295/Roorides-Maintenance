import { useState } from 'react'

export default function FilterModal({ isOpen, onClose, filters, onApplyFilters }) {
  const [localFilters, setLocalFilters] = useState(filters)

  const handleApply = () => {
    onApplyFilters(localFilters)
    onClose()
  }

  const handleReset = () => {
    const emptyFilters = {
      work_type: '',
      impact: '',
      category: '',
    }
    setLocalFilters(emptyFilters)
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black bg-opacity-50 transition-opacity"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
        <div className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-lg transform transition-all">
          {/* Header */}
          <div className="flex items-center justify-between p-5 border-b">
            <h3 className="text-lg font-semibold text-gray-900">Filters</h3>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-600 p-1"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          {/* Content - Scrollable */}
          <div className="p-5 space-y-6 max-h-[60vh] overflow-y-auto">
            {/* Work Type */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-3">
                Work Type
              </label>
              <div className="space-y-2">
                {['All', 'In House', 'Outsource'].map((type) => (
                  <label key={type} className="flex items-center p-3 border rounded-lg cursor-pointer hover:bg-gray-50">
                    <input
                      type="radio"
                      name="work_type"
                      value={type === 'All' ? '' : type}
                      checked={localFilters.work_type === (type === 'All' ? '' : type)}
                      onChange={(e) => setLocalFilters({ ...localFilters, work_type: e.target.value })}
                      className="w-4 h-4 text-blue-600 focus:ring-2 focus:ring-blue-500"
                    />
                    <span className="ml-3 text-sm text-gray-900">{type}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Impact */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-3">
                Impact
              </label>
              <div className="space-y-2">
                {['All', 'Minor', 'Major'].map((impact) => (
                  <label key={impact} className="flex items-center p-3 border rounded-lg cursor-pointer hover:bg-gray-50">
                    <input
                      type="radio"
                      name="impact"
                      value={impact === 'All' ? '' : impact}
                      checked={localFilters.impact === (impact === 'All' ? '' : impact)}
                      onChange={(e) => setLocalFilters({ ...localFilters, impact: e.target.value })}
                      className="w-4 h-4 text-blue-600 focus:ring-2 focus:ring-blue-500"
                    />
                    <span className="ml-3 text-sm text-gray-900">{impact}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Category */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-3">
                Category
              </label>
              <div className="space-y-2">
                {['All', 'Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS/Camera', 'Other'].map((cat) => (
                  <label key={cat} className="flex items-center p-3 border rounded-lg cursor-pointer hover:bg-gray-50">
                    <input
                      type="radio"
                      name="category"
                      value={cat === 'All' ? '' : cat}
                      checked={localFilters.category === (cat === 'All' ? '' : cat)}
                      onChange={(e) => setLocalFilters({ ...localFilters, category: e.target.value })}
                      className="w-4 h-4 text-blue-600 focus:ring-2 focus:ring-blue-500"
                    />
                    <span className="ml-3 text-sm text-gray-900">{cat}</span>
                  </label>
                ))}
              </div>
            </div>
          </div>

          {/* Footer - Sticky */}
          <div className="sticky bottom-0 flex gap-3 p-5 border-t bg-gray-50 rounded-b-2xl">
            <button
              onClick={handleReset}
              className="flex-1 px-4 py-3 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 min-h-[48px]"
            >
              Reset
            </button>
            <button
              onClick={handleApply}
              className="flex-1 px-4 py-3 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 min-h-[48px]"
            >
              Apply Filters
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
