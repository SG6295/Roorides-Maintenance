/**
 * Line rules for recording a refurbishment (MAIN-123). The database enforces these too;
 * they are here so the form can say what is wrong before anything is sent.
 */

export const REFURBISHED_SUFFIX = ' (Refurbished)'

/** The catalog name the refurbished stock goes under. */
export function refurbishedName(name) {
    return name.endsWith(REFURBISHED_SUFFIX) ? name : `${name}${REFURBISHED_SUFFIX}`
}

const hasAtMostTwoDecimals = n => Math.abs(n * 100 - Math.round(n * 100)) < 1e-6

/**
 * The first thing wrong with these lines, or null.
 * @param lines form lines
 * @param scrapById scrap rows available at the invoice's workshop, keyed by id
 */
export function refurbishmentLinesError(lines, scrapById) {
    if (lines.length === 0) return 'Add at least one refurbished part.'

    for (const line of lines) {
        if (line.notFound) {
            if (!line.original_part_id) return 'Choose the original part for every line that is not in the scrap list.'
            if (!line.comment.trim()) return 'A comment is required for a part that is not in the scrap list.'
        } else if (!line.scrap_id) {
            return 'Choose a scrap item for every line, or say it could not be found.'
        }

        const quantity = Number(line.quantity)
        if (line.quantity === '' || !(quantity > 0)) return 'Enter a quantity above zero for every line.'
        if (!hasAtMostTwoDecimals(quantity)) return 'Quantities can have at most two decimal places.'

        const scrap = line.notFound ? null : scrapById[line.scrap_id]
        if (!line.notFound && !scrap) return 'One of those scrap items is no longer in storage. Choose it again.'
        if (scrap && quantity > Number(scrap.quantity_snapshot)) {
            return `Only ${Number(scrap.quantity_snapshot)} ${scrap.unit_snapshot} of "${scrap.part_name_snapshot}" is in scrap.`
        }

        if (line.unit_price === '' || !(Number(line.unit_price) >= 0)) return 'Enter a unit price for every line.'
    }

    return null
}

/** A form line as record_refurbishment expects it. */
export function toRefurbishmentLine(line) {
    return {
        ...(line.notFound
            ? { original_part_id: line.original_part_id, comment: line.comment.trim() }
            : { scrap_inventory_id: line.scrap_id }),
        quantity: Number(line.quantity),
        unit_price: Number(line.unit_price),
        gst_rate: Number(line.gst_rate) || 0,
    }
}
