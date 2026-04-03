import { useState } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'

const REJECTION_REASONS = [
    { value: 'duplicate_ticket', label: 'Duplicate Ticket' },
    { value: 'wrong_info', label: 'Wrong Info on Ticket' },
    { value: 'request_denied', label: 'Request Denied' }
]

export default function RejectTicketModal({ isOpen, onClose, onConfirm, isLoading }) {
    const [selectedReason, setSelectedReason] = useState(null)
    const [comment, setComment] = useState('')

    const handleConfirm = () => {
        if (!selectedReason) return
        onConfirm({
            rejection_reason: selectedReason,
            rejection_comment: comment.trim() || null
        })
    }

    const handleClose = () => {
        setSelectedReason(null)
        setComment('')
        onClose()
    }

    if (!isOpen) return null

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
                        <h3 className="text-lg font-semibold text-gray-900">Reject Ticket</h3>
                        <button
                            onClick={handleClose}
                            className="text-gray-500 hover:text-gray-600 p-1"
                        >
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    {/* Content */}
                    <div className="p-5 space-y-6">
                        {/* Rejection Reason */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-3">
                                Reason for Rejection <span className="text-red-500">*</span>
                            </label>
                            <div className="space-y-2">
                                {REJECTION_REASONS.map((reason) => (
                                    <label
                                        key={reason.value}
                                        className={`flex items-center p-3 border rounded-lg cursor-pointer transition-colors ${selectedReason === reason.value
                                                ? 'border-red-500 bg-red-50'
                                                : 'hover:bg-gray-50'
                                            }`}
                                    >
                                        <input
                                            type="radio"
                                            name="rejection_reason"
                                            value={reason.value}
                                            checked={selectedReason === reason.value}
                                            onChange={(e) => setSelectedReason(e.target.value)}
                                            className="w-4 h-4 text-red-600 focus:ring-2 focus:ring-red-500"
                                        />
                                        <span className="ml-3 text-sm text-gray-900">{reason.label}</span>
                                    </label>
                                ))}
                            </div>
                        </div>

                        {/* Comment */}
                        <div>
                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                Additional Comment (Optional)
                            </label>
                            <textarea
                                value={comment}
                                onChange={(e) => setComment(e.target.value)}
                                placeholder="Add any additional details..."
                                rows={3}
                                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-red-500 resize-none"
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
                            onClick={handleConfirm}
                            disabled={!selectedReason || isLoading}
                            className="flex-1 px-4 py-3 text-sm font-medium text-white bg-red-600 rounded-lg hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed min-h-[48px]"
                        >
                            {isLoading ? 'Rejecting...' : 'Confirm Rejection'}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    )
}
