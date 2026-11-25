/**
 * The GST rates the app offers (MAIN-166), mirrored by public.gst_rates() — change both
 * together. One list for the GST breakdown of job card and multi-vehicle invoices and for
 * the lines of Record Purchase, Edit Purchase and Record Refurbishment.
 */
export const GST_RATES = [0, 5, 12, 18, 28, 40]

export const DEFAULT_GST_RATE = 18

/**
 * The rates as dropdown options. CustomSelect can't show a selected value of 0 (it reads
 * `opt.value || …`), so the values are strings and callers convert on change. A saved
 * rate that is no longer offered (`current`) is added back so an old line still shows it.
 */
export function gstRateOptions(current) {
    const rates = [...GST_RATES]
    const saved = current === '' || current == null ? NaN : Number(current)
    if (!Number.isNaN(saved) && !rates.includes(saved)) {
        rates.push(saved)
        rates.sort((a, b) => a - b)
    }
    return rates.map(r => ({ label: `${r}%`, value: String(r) }))
}
