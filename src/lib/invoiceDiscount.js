// Shared discount math for purchase-invoice line items (MAIN-21).
// The discount applies to the taxable value BEFORE GST, mirroring the DB
// generated column: line_total = round((qty*price - discount) * (1 + gst/100), 2).
//
// Storage model (Option A): discount_amount is the single canonical value that
// gets persisted. The percentage is display-only and derived from the amount.
// Each line also carries a `discount_mode` ('amount' | 'pct') marking which the
// user last edited, so that changing qty/price keeps the intended anchor.

export const round2 = (v) => Math.round((Number(v) + Number.EPSILON) * 100) / 100
export const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v))

export function lineSubtotal(line) {
    const qty = parseFloat(line.quantity) || 0
    const price = parseFloat(line.unit_price) || 0
    return qty * price
}

export function lineDiscount(line) {
    return clamp(parseFloat(line.discount_amount) || 0, 0, lineSubtotal(line))
}

export function lineTotal(line) {
    const sub = lineSubtotal(line)
    const gst = parseFloat(line.gst_rate) || 0
    return round2((sub - lineDiscount(line)) * (1 + gst / 100))
}

export function invoiceTotal(lines) {
    return round2(lines.reduce((s, l) => s + lineTotal(l), 0))
}

export function totalDiscount(lines) {
    return round2(lines.reduce((s, l) => s + lineDiscount(l), 0))
}

// Re-sync a line's discount fields after `field` was edited. Only overwrites
// fields the user is NOT actively typing in, so the input never fights the cursor.
export function syncLineDiscount(line, field) {
    const sub = lineSubtotal(line)
    const next = { ...line }

    if (field === 'discount_pct') {
        next.discount_mode = 'pct'
        if (line.discount_pct === '') {
            next.discount_amount = ''
        } else {
            const pct = clamp(parseFloat(line.discount_pct) || 0, 0, 100)
            next.discount_amount = String(round2((sub * pct) / 100))
        }
    } else if (field === 'discount_amount') {
        next.discount_mode = 'amount'
        if (line.discount_amount === '') {
            next.discount_pct = ''
        } else {
            const amt = clamp(parseFloat(line.discount_amount) || 0, 0, sub)
            next.discount_pct = sub > 0 ? String(round2((amt / sub) * 100)) : '0'
        }
    } else {
        // qty / unit_price changed: preserve the anchor, recompute the derived field
        if ((line.discount_mode || 'amount') === 'pct' && line.discount_pct !== '') {
            const pct = clamp(parseFloat(line.discount_pct) || 0, 0, 100)
            next.discount_amount = String(round2((sub * pct) / 100))
        } else if (line.discount_amount !== '') {
            const amt = clamp(parseFloat(line.discount_amount) || 0, 0, sub)
            next.discount_pct = sub > 0 ? String(round2((amt / sub) * 100)) : '0'
        }
    }
    return next
}

// Distribute a total discount across lines proportionally to each line's
// subtotal. The last line with a positive subtotal absorbs the rounding
// remainder so the parts sum exactly to the (clamped) entered total.
export function distributeTotalDiscount(lines, total) {
    const subs = lines.map(lineSubtotal)
    const sumSub = subs.reduce((a, b) => a + b, 0)
    if (sumSub <= 0) return lines

    const capped = clamp(parseFloat(total) || 0, 0, sumSub)
    let lastIdx = -1
    subs.forEach((s, i) => { if (s > 0) lastIdx = i })

    let allocated = 0
    return lines.map((l, i) => {
        const sub = subs[i]
        if (sub <= 0) return { ...l, discount_amount: '', discount_pct: '', discount_mode: 'amount' }
        let amt
        if (i === lastIdx) {
            amt = round2(capped - allocated)
        } else {
            amt = round2((capped * sub) / sumSub)
            allocated = round2(allocated + amt)
        }
        const pct = sub > 0 ? round2((amt / sub) * 100) : 0
        return {
            ...l,
            discount_amount: amt ? String(amt) : '0',
            discount_pct: pct ? String(pct) : '0',
            discount_mode: 'amount',
        }
    })
}
