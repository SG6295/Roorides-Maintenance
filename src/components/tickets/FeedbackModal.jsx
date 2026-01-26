import { useState, useEffect } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'

// Rating options matching database enum: 'Good', 'Ok', 'Bad'
const RATING_OPTIONS = [
    { value: 'Good', emoji: '😊', label: 'Good', color: 'text-green-500', bgColor: 'bg-green-50', borderColor: 'border-green-500' },
    { value: 'Ok', emoji: '😐', label: 'Ok', color: 'text-yellow-500', bgColor: 'bg-yellow-50', borderColor: 'border-yellow-500' },
    { value: 'Bad', emoji: '☹️', label: 'Bad', color: 'text-red-500', bgColor: 'bg-red-50', borderColor: 'border-red-500' }
]

export default function FeedbackModal({
    isOpen,
    onClose,
    onSubmit,
    isLoading,
    issueDescription,
    initialRating = null,
    initialRemarks = ''
}) {
    const [selectedRating, setSelectedRating] = useState(initialRating)
    const [remarks, setRemarks] = useState(initialRemarks || '')

    // Reset form when modal opens with new initial values
    useEffect(() => {
        if (isOpen) {
            setSelectedRating(initialRating)
            setRemarks(initialRemarks || '')
        }
    }, [isOpen, initialRating, initialRemarks])

    const handleSubmit = () => {
        if (selectedRating === null) return
        onSubmit({
            rating: selectedRating,
            rating_remarks: remarks.trim() || null
        })
    }

    const handleClose = () => {
        onClose()
    }

    if (!isOpen) return null

    const isEditing = initialRating !== null

    return (
        <div className="fixed inset-0 z-50 overflow-y-auto">
            {/* Backdrop */}
            <div
                className="fixed inset-0 bg-black bg-opacity-50 transition-opacity"
                onClick={handleClose}
            />

            {/* Modal */}
            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-md transform transition-all">
                    {/* Header */}
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 className="text-lg font-semibold text-gray-900">
                            {isEditing ? 'Edit Rating' : 'Rate Work Quality'}
                        </h3>
                        <button
                            onClick={handleClose}
                            className="text-gray-400 hover:text-gray-600 p-1"
                        >
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    {/* Content */}
                    <div className="p-5 space-y-6">
                        {/* Issue Context */}
                        <div className="bg-gray-50 rounded-lg p-3">
                            <p className="text-sm text-gray-500">Rating work on:</p>
                            <p className="text-sm font-medium text-gray-900">{issueDescription}</p>
                        </div>

                        {/* Rating Selection */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-3">
                                How was the work quality?
                            </label>
                            <div className="flex justify-center gap-4">
                                {RATING_OPTIONS.map((option) => (
                                    <button
                                        key={option.value}
                                        onClick={() => setSelectedRating(option.value)}
                                        className={`flex flex-col items-center p-4 rounded-xl border-2 transition-all ${selectedRating === option.value
                                            ? `${option.bgColor} ${option.borderColor}`
                                            : 'border-gray-200 hover:border-gray-300 hover:bg-gray-50'
                                            }`}
                                    >
                                        <span className={`text-4xl mb-2 ${selectedRating === option.value ? '' : 'grayscale'}`}>
                                            {option.emoji}
                                        </span>
                                        <span className={`text-sm font-medium ${selectedRating === option.value ? option.color : 'text-gray-500'
                                            }`}>
                                            {option.label}
                                        </span>
                                    </button>
                                ))}
                            </div>
                        </div>

                        {/* Comment/Remarks */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                Add a comment (optional)
                            </label>
                            <textarea
                                value={remarks}
                                onChange={(e) => setRemarks(e.target.value)}
                                placeholder="Share details about the work..."
                                rows={3}
                                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 resize-none"
                            />
                        </div>
                    </div>

                    {/* Footer */}
                    <div className="flex gap-3 p-5 border-t bg-gray-50 rounded-b-2xl">
                        <button
                            onClick={handleClose}
                            className="flex-1 px-4 py-3 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 min-h-[48px]"
                        >
                            Cancel
                        </button>
                        <button
                            onClick={handleSubmit}
                            disabled={selectedRating === null || isLoading}
                            className="flex-1 px-4 py-3 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed min-h-[48px]"
                        >
                            {isLoading ? 'Submitting...' : isEditing ? 'Update Rating' : 'Submit Rating'}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    )
}
