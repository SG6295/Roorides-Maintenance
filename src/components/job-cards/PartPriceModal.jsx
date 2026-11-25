import { useState } from 'react'
import { createPortal } from 'react-dom'
import { XMarkIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import { gstRateOptions, DEFAULT_GST_RATE } from '../../constants/gstRates'
import { companyLabel } from '../../constants/vehicleCompanies'
import { priceFormError } from '../../utils/jobCardValue'

/**
 * Asks for a part's price when a spare finds stock that never came in on a recorded
 * purchase (MAIN-158). Spares are costed first in, first out, so that stock needs a price
 * before it can be used. The price is saved once for the part, as opening stock; the
 * spare is then added.
 */
export default function PartPriceModal({ part, onConfirm, onCancel, isSaving, error }) {
    const [unitPrice, setUnitPrice] = useState('')
    const [gstRate, setGstRate] = useState(String(DEFAULT_GST_RATE))
    const [formError, setFormError] = useState(null)

    const submit = () => {
        const problem = priceFormError({ unitPrice, gstRate })
        if (problem) {
            setFormError(problem)
            return
        }
        onConfirm({ unitPrice, gstRate })
    }

    return createPortal(
        <div className="fixed inset-0 z-50 overflow-y-auto">
            <div className="fixed inset-0 bg-black bg-opacity-50" onClick={onCancel} />

            <div className="flex min-h-full items-end justify-center sm:items-center sm:p-4">
                <div role="dialog" aria-labelledby="part-price-title" className="relative bg-white rounded-t-2xl sm:rounded-2xl shadow-xl w-full max-w-md">
                    <div className="flex items-center justify-between p-5 border-b">
                        <h3 id="part-price-title" className="text-lg font-semibold text-gray-900">
                            Price for {part.partName || 'this part'}
                        </h3>
                        <button type="button" onClick={onCancel} aria-label="Close" className="text-gray-500 hover:text-gray-600 p-1">
                            <XMarkIcon className="w-6 h-6" />
                        </button>
                    </div>

                    <div className="p-5 space-y-4">
                        <p className="text-sm text-gray-700">
                            Some of this part's {part.company ? `${companyLabel(part.company)} ` : ''}stock
                            never came in on a recorded purchase, so it has no price. Enter what one
                            unit cost. It is saved once for the part, and the spare is added.
                        </p>
                        <div className="grid grid-cols-2 gap-3">
                            <div>
                                <label htmlFor="part-price-unit" className="block text-sm font-medium text-gray-700 mb-1">
                                    Price per {part.unit || 'unit'}, before GST <span className="text-red-500">*</span>
                                </label>
                                <input
                                    id="part-price-unit"
                                    type="number"
                                    min="0"
                                    step="0.01"
                                    autoFocus
                                    value={unitPrice}
                                    onChange={e => { setUnitPrice(e.target.value); setFormError(null) }}
                                    className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                />
                            </div>
                            <div>
                                <CustomSelect
                                    label="GST %"
                                    value={gstRate}
                                    onChange={v => { setGstRate(v); setFormError(null) }}
                                    options={gstRateOptions(gstRate)}
                                />
                            </div>
                        </div>
                        {formError && <p className="text-sm text-red-600">{formError}</p>}
                        {error && <p className="text-sm text-red-600">{error.message}</p>}
                    </div>

                    <div className="flex justify-end gap-3 p-5 border-t">
                        <button
                            type="button"
                            onClick={onCancel}
                            className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50"
                        >
                            Cancel
                        </button>
                        <button
                            type="button"
                            onClick={submit}
                            disabled={isSaving}
                            className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {isSaving ? 'Saving…' : 'Save price and add spare'}
                        </button>
                    </div>
                </div>
            </div>
        </div>,
        document.body,
    )
}
