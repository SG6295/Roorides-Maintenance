import { describe, it, expect } from 'vitest'
import { refurbishedName, refurbishmentLinesError, toRefurbishmentLine, approvedAmountError, refurbishmentSource } from '../refurbishment'

const scrapById = {
    s1: { quantity_snapshot: 4, unit_snapshot: 'pcs', part_name_snapshot: 'Alternator' },
}

const fromScrap = over => ({
    notFound: false, scrap_id: 's1', original_part_id: '', quantity: '2', unit_price: '100', gst_rate: '18', comment: '', ...over,
})

const notInList = over => ({
    notFound: true, scrap_id: '', original_part_id: 'p1', quantity: '1', unit_price: '50', gst_rate: '0', comment: 'in the scrap room', ...over,
})

describe('refurbishedName', () => {
    it('adds the suffix once', () => {
        expect(refurbishedName('Alternator')).toBe('Alternator (Refurbished)')
        expect(refurbishedName('Alternator (Refurbished)')).toBe('Alternator (Refurbished)')
    })
})

describe('refurbishmentLinesError', () => {
    it('accepts part of a scrap row, all of it, and a part not in the list', () => {
        expect(refurbishmentLinesError([fromScrap(), notInList()], scrapById)).toBeNull()
        expect(refurbishmentLinesError([fromScrap({ quantity: '4' })], scrapById)).toBeNull()
    })

    it('refuses more than is in scrap', () => {
        expect(refurbishmentLinesError([fromScrap({ quantity: '5' })], scrapById)).toMatch(/Only 4 pcs of "Alternator"/)
    })

    it('needs a typed quantity above zero', () => {
        expect(refurbishmentLinesError([fromScrap({ quantity: '' })], scrapById)).toMatch(/quantity/)
        expect(refurbishmentLinesError([fromScrap({ quantity: '0' })], scrapById)).toMatch(/quantity/)
    })

    it('refuses three decimal places', () => {
        expect(refurbishmentLinesError([fromScrap({ quantity: '1.005' })], scrapById)).toMatch(/two decimal/)
    })

    it('needs a comment and an original part when not in the list', () => {
        expect(refurbishmentLinesError([notInList({ comment: '  ' })], scrapById)).toMatch(/comment/)
        expect(refurbishmentLinesError([notInList({ original_part_id: '' })], scrapById)).toMatch(/original part/)
    })

    it('needs a scrap item otherwise', () => {
        expect(refurbishmentLinesError([fromScrap({ scrap_id: '' })], scrapById)).toMatch(/scrap item/)
    })

    it('notices a scrap item that has gone', () => {
        expect(refurbishmentLinesError([fromScrap({ scrap_id: 'gone' })], scrapById)).toMatch(/no longer in storage/)
    })

    it('accepts a zero price but not a blank one', () => {
        expect(refurbishmentLinesError([fromScrap({ unit_price: '0' })], scrapById)).toBeNull()
        expect(refurbishmentLinesError([fromScrap({ unit_price: '' })], scrapById)).toMatch(/unit price/)
    })
})

describe('toRefurbishmentLine', () => {
    it('sends the scrap item for a picked line', () => {
        expect(toRefurbishmentLine(fromScrap())).toEqual({
            scrap_inventory_id: 's1', quantity: 2, unit_price: 100, gst_rate: 18,
        })
    })

    it('sends the part and comment for a line not in the list', () => {
        expect(toRefurbishmentLine(notInList())).toEqual({
            original_part_id: 'p1', comment: 'in the scrap room', quantity: 1, unit_price: 50, gst_rate: 0,
        })
    })
})

describe('approvedAmountError', () => {
    // 2 × 100 + 18% = 236.00, and 1 × 50 = 50.00
    const lines = [fromScrap(), notInList()]

    it('accepts an approved amount equal to the parts total, to the paisa', () => {
        expect(approvedAmountError(lines, '286')).toBeNull()
        expect(approvedAmountError(lines, '286.00')).toBeNull()
    })

    it('names both figures when they differ', () => {
        expect(approvedAmountError(lines, '286.01')).toBe('The parts add up to ₹286.00; the approved amount is ₹286.01.')
    })

    it('leaves a blank or malformed amount to the invoice form', () => {
        expect(approvedAmountError(lines, '')).toBeNull()
        expect(approvedAmountError(lines, '12.345')).toBeNull()
    })
})

describe('refurbishmentSource', () => {
    it('names the job card a scrap row came from', () => {
        expect(refurbishmentSource({ scrap_inventory_id: 's1', scrap: { job_card: { job_card_number: 3101 } } }))
            .toEqual({ kind: 'job_card', label: 'Job card #3101', jobCardNumber: 3101 })
    })

    it('names the stock audit a scrap row came from', () => {
        const scrap = { job_card: null, audit_line: { audit_item: { audit: { audit_number: 7 } } } }
        expect(refurbishmentSource({ scrap_inventory_id: 's1', scrap }))
            .toEqual({ kind: 'audit', label: 'Stock audit AUD-7' })
    })

    it('says when the part was never in the scrap list', () => {
        expect(refurbishmentSource({ scrap_inventory_id: null, comment: 'found in the yard' }).kind).toBe('not_in_scrap')
        expect(refurbishmentSource(undefined).kind).toBe('not_in_scrap')
    })

    it('falls back when the scrap row cannot be read', () => {
        expect(refurbishmentSource({ scrap_inventory_id: 's1', scrap: null }).kind).toBe('unknown')
    })
})
