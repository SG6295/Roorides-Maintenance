import { XMarkIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import { GST_RATES, gstRateOptions } from '../../constants/gstRates'
import { emptyGstRow, gstRowPaise, gstRowsInclPaise, breakdownLines } from '../../utils/gstBreakdown'
import { toPaise, paiseToInput } from '../../utils/settlement'
import { fmtPaise } from './format'

/**
 * The GST breakdown of a job card or multi-vehicle invoice (MAIN-166): one row per rate.
 * The exec types either Amount before GST or Amount incl. GST and the other two are
 * worked out (gstBreakdown.js). `rows` are form rows; `onChange` gets the new list.
 * With no rows yet, one row at the default rate is shown, so an untouched breakdown
 * leaves the form empty.
 */
export default function GstBreakdownFields({ rows, onChange, invoiceValue, error, showErrors, required = true }) {
    const shown = rows.length ? rows : [emptyGstRow()]
    const used = shown.map(r => Number(r.rate))
    const unused = GST_RATES.filter(r => !used.includes(r))

    const update = (i, patch) => onChange(shown.map((r, j) => (j === i ? { ...r, ...patch } : r)))
    const remove = i => onChange(shown.filter((_, j) => j !== i))
    const add = () => onChange([...shown, emptyGstRow(unused[0])])

    const total = gstRowsInclPaise(shown)
    const value = toPaise(invoiceValue)
    const left = Number.isNaN(value) || value <= 0 ? null : value - total

    const input = 'w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500'
    const border = showErrors && error ? 'border-red-400' : 'border-gray-300'

    return (
        <div className="space-y-2">
            <p className="block text-xs font-medium text-gray-600">
                GST breakdown {required && <span className="text-red-500">*</span>}
            </p>

            <div className="hidden sm:grid grid-cols-[6rem_1fr_1fr_1fr_1.25rem] gap-2 text-xs text-gray-500">
                <span>GST rate</span>
                <span>Amount before GST (₹)</span>
                <span>GST amount (₹)</span>
                <span>Amount incl. GST (₹)</span>
                <span />
            </div>

            {shown.map((row, i) => {
                const p = gstRowPaise(row)
                const valueOf = field => (row.entered === field ? row.amount : p ? paiseToInput(field === 'before' ? p.before : p.incl) : '')
                return (
                    <div key={i} className="grid grid-cols-2 sm:grid-cols-[6rem_1fr_1fr_1fr_1.25rem] gap-2 items-center">
                        <CustomSelect
                            value={row.rate}
                            onChange={rate => update(i, { rate })}
                            options={gstRateOptions(row.rate).filter(o => o.value === row.rate || !used.includes(Number(o.value)))}
                        />
                        <input
                            type="number"
                            min="0"
                            step="0.01"
                            aria-label="Amount before GST"
                            placeholder="Before GST"
                            value={valueOf('before')}
                            onChange={e => update(i, { amount: e.target.value, entered: 'before' })}
                            className={`${input} ${border}`}
                        />
                        <div aria-label="GST amount" className="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 text-gray-900 min-h-[38px]">
                            {p ? paiseToInput(p.gst) : <span className="text-gray-400">Auto</span>}
                        </div>
                        <input
                            type="number"
                            min="0"
                            step="0.01"
                            aria-label="Amount incl. GST"
                            placeholder="Incl. GST"
                            value={valueOf('incl')}
                            onChange={e => update(i, { amount: e.target.value, entered: 'incl' })}
                            className={`${input} ${border}`}
                        />
                        {shown.length > 1 ? (
                            <button type="button" onClick={() => remove(i)} aria-label="Remove this rate" className="text-gray-400 hover:text-red-600">
                                <XMarkIcon className="h-5 w-5" />
                            </button>
                        ) : <span />}
                    </div>
                )
            })}

            <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
                {unused.length > 0 ? (
                    <button type="button" onClick={add} className="text-blue-600 hover:underline">
                        + Add another rate
                    </button>
                ) : <span />}
                {left !== null && total > 0 && (
                    <span className={left === 0 ? 'text-green-700' : 'text-amber-700'}>
                        {left === 0
                            ? 'Adds up to the Invoice Value'
                            : left > 0
                                ? `${fmtPaise(left)} left to reach the Invoice Value`
                                : `${fmtPaise(-left)} more than the Invoice Value`}
                    </span>
                )}
            </div>

            {showErrors && error && <p className="text-xs text-red-600">{error}</p>}
        </div>
    )
}

/** A saved breakdown, read-only: one line per rate, or "Not recorded". */
export function GstBreakdownReadOnly({ breakdown }) {
    const lines = breakdownLines(breakdown)
    return (
        <div>
            <p className="text-xs text-gray-500 mb-0.5">GST breakdown</p>
            {lines.length
                ? lines.map(l => <p key={l} className="font-medium text-gray-900">{l}</p>)
                : <p className="font-medium text-gray-400">Not recorded</p>}
        </div>
    )
}
