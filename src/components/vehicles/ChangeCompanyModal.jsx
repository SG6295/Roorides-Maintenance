import { useState } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import { useToast, useConfirm } from '../../hooks/useFeedback'
import { useSetVehicleCompany } from '../../hooks/useVehicleCompany'
import {
    ASSIGNABLE_COMPANIES, UNKNOWN_COMPANY, changeKind, companyColor, companyLabel, saleErrors,
} from '../../constants/vehicleCompanies'

const rupees = v => `₹${Number(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

/**
 * Finance assigns an Unknown vehicle to a company, or moves one between the companies as a
 * sale (MAIN-155). The rules are set_vehicle_company's: an assignment takes no sale value; a
 * sale needs its value (incl. GST) and GST %, and is refused while the vehicle has an open
 * ticket or job card — that refusal comes back as "Close … first".
 */
export default function ChangeCompanyModal({ vehicle, onClose }) {
    const toast = useToast()
    const confirm = useConfirm()
    const setCompany = useSetVehicleCompany()

    const current = vehicle.company
    const options = ASSIGNABLE_COMPANIES
        .filter(c => c.value !== current)
        .map(c => ({ value: c.value, label: c.label }))

    // With one company left to choose there is nothing to pick.
    const [company, setCompanyValue] = useState(options.length === 1 ? options[0].value : '')
    const [saleValue, setSaleValue] = useState('')
    const [gstPercent, setGstPercent] = useState('')
    const [errors, setErrors] = useState({})

    const kind = changeKind(current, company)

    async function handleSubmit(e) {
        e.preventDefault()
        const fieldErrors = {
            ...(company ? {} : { company: 'Choose a company.' }),
            ...(kind === 'sale' ? saleErrors({ saleValue, gstPercent }) : {}),
        }
        setErrors(fieldErrors)
        if (Object.keys(fieldErrors).length > 0) return

        const reg = vehicle.registration_number
        const ok = await confirm(kind === 'assignment'
            ? {
                title: `Assign ${reg} to ${companyLabel(company)}?`,
                message: `This records that ${reg} has always belonged to ${companyLabel(company)}. It is not a sale, and the vehicle can't be changed back to Unknown afterwards.`,
                confirmLabel: 'Assign',
                tone: 'primary',
            }
            : {
                title: `Sell ${reg} to ${companyLabel(company)}?`,
                message: `${companyLabel(current)} sells ${reg} to ${companyLabel(company)} for ${rupees(saleValue)} including GST at ${Number(gstPercent)}%. Records from now on belong to ${companyLabel(company)}; its history stays with ${companyLabel(current)}.`,
                confirmLabel: 'Record sale',
                tone: 'primary',
            })
        if (!ok) return

        try {
            await setCompany.mutateAsync({
                vehicleId: vehicle.id,
                change: kind === 'sale'
                    ? { company, sale_value: saleValue.trim(), gst_percent: gstPercent.trim() }
                    : { company },
            })
            toast.success(kind === 'sale'
                ? `${reg} moved to ${companyLabel(company)}.`
                : `${reg} assigned to ${companyLabel(company)}.`)
            onClose()
        } catch (err) {
            toast.error(`Could not change ${reg}'s company: ${err.message}`)
        }
    }

    const inputClass = hasError =>
        `w-full border rounded-lg px-3 py-2 text-sm focus:ring-2 ${hasError ? 'border-red-300 focus:ring-red-500' : 'border-gray-300 focus:ring-blue-500'}`

    return (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
            <div className="bg-white rounded-xl shadow-2xl w-full max-w-md">
                <div className="flex items-center justify-between px-6 py-4 border-b">
                    <div>
                        <h2 className="text-base font-semibold text-gray-900">Change company</h2>
                        <p className="text-xs text-gray-500 font-mono mt-0.5">{vehicle.registration_number}</p>
                    </div>
                    <button type="button" onClick={onClose} className="text-gray-400 hover:text-gray-600" aria-label="Close">
                        <XMarkIcon className="w-5 h-5" />
                    </button>
                </div>

                <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4" noValidate>
                    <div className="flex items-center justify-between text-sm bg-gray-50 rounded-lg px-3 py-2.5">
                        <span className="text-gray-500">Current company</span>
                        <span className={`px-2 py-0.5 text-xs rounded-full ${companyColor(current)}`}>{companyLabel(current)}</span>
                    </div>

                    <CustomSelect
                        label="New company"
                        value={company}
                        onChange={v => { setCompanyValue(v); setErrors({}) }}
                        options={options}
                        placeholder="Choose a company"
                        error={errors.company ? { message: errors.company } : undefined}
                    />

                    {kind === 'assignment' && (
                        <p className="text-xs text-gray-600 bg-blue-50 border border-blue-100 rounded-lg px-3 py-2">
                            First assignment — not a sale. The vehicle is recorded as always having belonged to{' '}
                            {companyLabel(company)}, and can&apos;t be changed back to Unknown.
                        </p>
                    )}

                    {kind === 'sale' && (
                        <>
                            <p className="text-xs text-gray-600 bg-blue-50 border border-blue-100 rounded-lg px-3 py-2">
                                A move between the companies is a sale. Only records from now on belong to{' '}
                                {companyLabel(company)}. Not allowed while the vehicle has an open ticket or job card.
                            </p>
                            <div className="grid grid-cols-2 gap-3">
                                <div>
                                    <label htmlFor="sale-value" className="block text-xs font-medium text-gray-600 mb-1">
                                        Sale value incl. GST (₹) <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        id="sale-value"
                                        type="text"
                                        inputMode="decimal"
                                        className={inputClass(errors.saleValue)}
                                        value={saleValue}
                                        onChange={e => { setSaleValue(e.target.value); setErrors(p => ({ ...p, saleValue: undefined })) }}
                                        placeholder="e.g. 850000"
                                    />
                                    {errors.saleValue && <p className="mt-1 text-xs text-red-600">{errors.saleValue}</p>}
                                </div>
                                <div>
                                    <label htmlFor="gst-percent" className="block text-xs font-medium text-gray-600 mb-1">
                                        GST % <span className="text-red-500">*</span>
                                    </label>
                                    <input
                                        id="gst-percent"
                                        type="text"
                                        inputMode="decimal"
                                        className={inputClass(errors.gstPercent)}
                                        value={gstPercent}
                                        onChange={e => { setGstPercent(e.target.value); setErrors(p => ({ ...p, gstPercent: undefined })) }}
                                        placeholder="e.g. 28"
                                    />
                                    {errors.gstPercent && <p className="mt-1 text-xs text-red-600">{errors.gstPercent}</p>}
                                </div>
                            </div>
                        </>
                    )}

                    <div className="flex justify-end gap-3 pt-2">
                        <button
                            type="button"
                            onClick={onClose}
                            className="px-4 py-2 text-sm text-gray-700 border rounded-lg hover:bg-gray-100"
                        >
                            Cancel
                        </button>
                        <button
                            type="submit"
                            disabled={setCompany.isPending}
                            className="px-5 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
                        >
                            {setCompany.isPending ? 'Saving…' : current === UNKNOWN_COMPANY ? 'Assign' : 'Record sale'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    )
}
