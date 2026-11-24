import CustomSelect from '../shared/CustomSelect'
import { STOCK_COMPANIES, companyLabel } from '../../constants/vehicleCompanies'

/**
 * Billed to (MAIN-157): the company that pays for a purchase or refurbishment, and so
 * owns its stock. Required — it starts empty, and save_purchase_invoice /
 * record_refurbishment refuse a save without it. Shown as text when it can't change.
 *
 * @param {object} props
 * @param {string} props.value
 * @param {Function} [props.onChange]
 * @param {boolean} [props.readOnly]
 * @param {boolean} [props.showError]  show "Required" when empty
 * @param {string} [props.hint]
 */
export default function BilledToField({ value, onChange, readOnly = false, showError = false, hint }) {
    return (
        <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">
                Billed to {!readOnly && <span className="text-red-500">*</span>}
            </label>
            {readOnly ? (
                <p className="text-sm text-gray-900 py-2">{value ? companyLabel(value) : '—'}</p>
            ) : (
                <CustomSelect
                    value={value}
                    onChange={onChange}
                    options={STOCK_COMPANIES.map(c => ({ value: c.value, label: c.label }))}
                    placeholder="Select company"
                    compact
                />
            )}
            {showError && !value && !readOnly && <p className="text-xs text-red-600 mt-1">Required</p>}
            {hint && <p className="text-xs text-gray-400 mt-1">{hint}</p>}
        </div>
    )
}
