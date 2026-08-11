import * as XLSX from 'xlsx'

/**
 * The stock-audit count sheet (MAIN-30).
 *
 * Finance downloads this, writes the physical count on it away from a screen, and uploads
 * it again. Everything here is about surviving that round trip through Excel and a
 * clipboard.
 *
 * audit_id and part_id are repeated on every row on purpose. A second metadata worksheet
 * would be tidier to look at but does not survive a save-as-CSV, and the machine keys are
 * what make "is this even the right sheet?" answerable without guessing.
 */

export const SHEET_COLUMNS = [
    'audit_id',
    'part_id',
    'part_name',
    'part_number',
    'unit',
    'system_qty',
    'counted_qty',
]

const COLUMN_WIDTHS = [38, 38, 34, 18, 8, 12, 12]

/** Blank rows at the foot of the sheet for stock found on the shelf but not listed. */
export const FOUND_ROW_COUNT = 20

// ─── Build ────────────────────────────────────────────────────────────────────

export function buildCountSheet({ audit, items, locationName }) {
    const header = [...SHEET_COLUMNS]

    const printed = items.map(item => [
        audit.id,
        item.part_id,
        item.part_name_snapshot,
        item.part_number_snapshot || '',
        item.unit_snapshot || '',
        Number(item.system_qty ?? 0),
        item.counted_qty === null || item.counted_qty === undefined ? '' : Number(item.counted_qty),
    ])

    // Found rows carry the audit id so an upload can still tell which audit they belong
    // to, and nothing else — the counter fills in part number, name and quantity.
    const found = Array.from({ length: FOUND_ROW_COUNT }, () => [audit.id, '', '', '', '', '', ''])

    const ws = XLSX.utils.aoa_to_sheet([header, ...printed, ...found])
    ws['!cols'] = COLUMN_WIDTHS.map(wch => ({ wch }))

    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, ws, 'Count Sheet')

    const ref = audit.audit_number ? `AUD-${audit.audit_number}_` : ''
    const slug = (locationName || 'workshop').toLowerCase().replace(/[^a-z0-9]+/g, '_')
    const dateSuffix = new Date().toISOString().slice(0, 10)
    XLSX.writeFile(wb, `${ref}stock_count_${slug}_${dateSuffix}.xlsx`)
}

// ─── Parse ────────────────────────────────────────────────────────────────────

export function parseCountSheet(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader()
        reader.onload = e => {
            try {
                const wb = XLSX.read(e.target.result, { type: 'array' })
                const ws = wb.Sheets[wb.SheetNames[0]]
                const rows = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' })
                resolve(rows)
            } catch {
                reject(new Error('Could not read that file. Upload the .xlsx count sheet that was downloaded for this audit.'))
            }
        }
        reader.onerror = () => reject(new Error('Failed to read the file.'))
        reader.readAsArrayBuffer(file)
    })
}

function rowsToRecords(rows) {
    if (rows.length < 2) return []
    const header = rows[0].map(h => String(h).trim().toLowerCase().replace(/\s+/g, '_'))
    return rows.slice(1).map((row, idx) => {
        const rec = {}
        header.forEach((h, i) => { rec[h] = row[i] ?? '' })
        rec._rowIndex = idx + 2 // 1-based, past the header
        return rec
    })
}

const str = v => String(v ?? '').trim()

function toNumber(v) {
    if (v === '' || v === null || v === undefined) return null
    const n = typeof v === 'number' ? v : Number(str(v))
    return Number.isFinite(n) ? n : NaN
}

/**
 * Turn raw sheet rows into something submittable, or into errors precise enough to fix.
 *
 * A printed row left blank is a hard error rather than a skip: a physical count that
 * quietly omits half the shelves would write off stock nobody actually looked for.
 * Untouched found rows at the foot of the sheet are ignored, since they are blank by
 * design.
 *
 * @param {Array} rows      raw arrays from parseCountSheet
 * @param {object} ctx
 * @param {object} ctx.audit  the open audit
 * @param {Array}  ctx.items  its stock_audit_items
 * @param {Array}  ctx.parts  the parts catalogue, for resolving found rows
 */
export function validateCountSheet(rows, { audit, items, parts }) {
    const records = rowsToRecords(rows)
    const fatal = []

    if (records.length === 0) {
        return { records: [], counts: [], fatal: ['That sheet has no rows below the header.'], missing: [] }
    }

    const itemsByPartId = new Map(items.map(i => [i.part_id, i]))
    const byNumber = new Map(
        parts.filter(p => p.part_number).map(p => [str(p.part_number).toLowerCase(), p])
    )
    const byName = new Map(parts.map(p => [str(p.name).toLowerCase(), p]))

    // A sheet from a different audit is the one mistake worth stopping on before
    // looking at any row: every quantity on it would be measured against the wrong
    // snapshot.
    const sheetAuditIds = new Set(records.map(r => str(r.audit_id)).filter(Boolean))
    if (sheetAuditIds.size === 0) {
        fatal.push('That file is missing the audit_id column. Upload the count sheet downloaded for this audit.')
    } else if (sheetAuditIds.size > 1 || !sheetAuditIds.has(audit.id)) {
        fatal.push('That sheet belongs to a different audit. Download a fresh count sheet for this one.')
    }

    const seen = new Set()

    const validated = records.map(rec => {
        const errors = []
        const partId = str(rec.part_id)
        const partNumber = str(rec.part_number)
        const partName = str(rec.part_name)
        const rawCount = rec.counted_qty

        const isPrinted = !!partId && itemsByPartId.has(partId)
        const untouchedFoundRow =
            !partId && !partNumber && !partName && str(rawCount) === ''

        if (untouchedFoundRow) return { ...rec, _skip: true, _errors: [] }

        // Resolve the part. Printed rows already know it; found rows are matched on part
        // number first, then name — the same order BulkUploadModal uses.
        let resolved = null
        if (isPrinted) {
            resolved = { id: partId, name: itemsByPartId.get(partId).part_name_snapshot }
        } else if (partId) {
            errors.push('This part is not on this audit’s sheet')
        } else {
            const match =
                (partNumber && byNumber.get(partNumber.toLowerCase())) ||
                (partName && byName.get(partName.toLowerCase())) ||
                null
            if (match) {
                resolved = match
                if (itemsByPartId.has(match.id)) {
                    errors.push('Already listed higher up the sheet — write the count on that row instead')
                    resolved = null
                }
            } else {
                errors.push(
                    `"${partNumber || partName}" is not in the parts catalogue. Add it under Parts Catalog first, then upload again`
                )
            }
        }

        const qty = toNumber(rawCount)
        if (qty === null) {
            errors.push(isPrinted ? 'Counted quantity is blank' : 'Counted quantity is blank on a found row')
        } else if (Number.isNaN(qty)) {
            errors.push('Counted quantity is not a number')
        } else if (qty < 0) {
            errors.push('Counted quantity cannot be negative')
        }

        if (resolved) {
            if (seen.has(resolved.id)) {
                errors.push('This part appears twice on the sheet')
            } else {
                seen.add(resolved.id)
            }
        }

        const item = isPrinted ? itemsByPartId.get(partId) : null
        const systemQty = item ? Number(item.system_qty) : 0

        return {
            ...rec,
            _rowIndex: rec._rowIndex,
            _skip: false,
            _errors: errors,
            _isFound: !isPrinted,
            _partId: resolved?.id ?? null,
            _partLabel: resolved?.name || partName || partNumber || '—',
            _systemQty: systemQty,
            _countedQty: Number.isFinite(qty) ? qty : null,
            _variance: Number.isFinite(qty) ? qty - systemQty : null,
        }
    })

    const usable = validated.filter(r => !r._skip)

    // Every printed row has to come back. Anything absent was never counted.
    const missing = items
        .filter(i => !seen.has(i.part_id))
        .map(i => i.part_name_snapshot)

    if (missing.length > 0) {
        fatal.push(
            `${missing.length} part${missing.length === 1 ? '' : 's'} from the sheet ${missing.length === 1 ? 'is' : 'are'} not in the uploaded file: ` +
            missing.slice(0, 5).join(', ') +
            (missing.length > 5 ? `, and ${missing.length - 5} more` : '') +
            '. Every printed row must be counted.'
        )
    }

    const counts = usable
        .filter(r => r._errors.length === 0 && r._partId)
        .map(r => ({ part_id: r._partId, counted_qty: r._countedQty }))

    return { records: usable, counts, fatal, missing }
}
