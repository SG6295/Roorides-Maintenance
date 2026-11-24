/**
 * MAIN-157: the count sheet's Belongs to column — one line per part per company, and only
 * the two company names are accepted.
 */
import { describe, it, expect } from 'vitest'
import { validateCountSheet, parseBelongsTo, SHEET_COLUMNS } from '../auditSheet'

const audit = { id: 'audit-1' }
const items = [
    { part_id: 'p1', company: 'nvs_travels', part_name_snapshot: 'Alternator', system_qty: 5 },
    { part_id: 'p1', company: 'nvs_travel_solutions', part_name_snapshot: 'Alternator', system_qty: 2 },
]
const parts = [
    { id: 'p1', name: 'Alternator', part_number: 'ALT-1' },
    { id: 'p2', name: 'Brake Pad', part_number: 'BP-9' },
]

// A sheet row in SHEET_COLUMNS order.
const row = ({ partId = '', name = '', number = '', belongsTo = '', counted = '' }) =>
    ['audit-1', partId, name, number, 'pcs', belongsTo, '', counted]
const sheet = (...rows) => [SHEET_COLUMNS, ...rows]
const printed = (belongsTo, counted) => row({ partId: 'p1', name: 'Alternator', belongsTo, counted })
const both = [printed('NVS Travels', 5), printed('NVS Travel Solutions Pvt Ltd', 1)]

describe('parseBelongsTo', () => {
    it('accepts the two company names, ignoring case and extra spaces', () => {
        expect(parseBelongsTo('NVS Travels')).toBe('nvs_travels')
        expect(parseBelongsTo('  nvs   travel solutions pvt ltd ')).toBe('nvs_travel_solutions')
    })

    it('refuses anything else', () => {
        expect(parseBelongsTo('Pvt Ltd')).toBeNull()
        expect(parseBelongsTo('')).toBeNull()
    })
})

describe('validateCountSheet with Belongs to', () => {
    it('counts each company line separately', () => {
        const { fatal, counts, records } = validateCountSheet(sheet(...both), { audit, items, parts })
        expect(fatal).toEqual([])
        expect(counts).toEqual([
            { part_id: 'p1', company: 'nvs_travels', counted_qty: 5 },
            { part_id: 'p1', company: 'nvs_travel_solutions', counted_qty: 1 },
        ])
        expect(records[1]._variance).toBe(-1)
    })

    it('requires Belongs to on a found row, and only the two names', () => {
        const { records, counts } = validateCountSheet(
            sheet(...both, row({ number: 'BP-9', counted: 3 }), row({ name: 'Brake Pad', belongsTo: 'Pvt Ltd', counted: 1 })),
            { audit, items, parts },
        )
        expect(records[2]._errors[0]).toMatch(/Belongs to is blank/)
        expect(records[3]._errors[0]).toMatch(/"Pvt Ltd" is not NVS Travels or NVS Travel Solutions Pvt Ltd/)
        expect(counts).toHaveLength(2)
    })

    it('takes a found row of a printed part for a company it was not printed for', () => {
        const only = [items[0]]
        const { counts, records } = validateCountSheet(
            sheet(printed('NVS Travels', 5), row({ number: 'ALT-1', belongsTo: 'NVS Travel Solutions Pvt Ltd', counted: 2 })),
            { audit, items: only, parts },
        )
        expect(records[1]._isFound).toBe(true)
        expect(counts[1]).toEqual({ part_id: 'p1', company: 'nvs_travel_solutions', counted_qty: 2 })
    })

    it('refuses a found row for a line already printed for that company', () => {
        const { records } = validateCountSheet(
            sheet(...both, row({ number: 'ALT-1', belongsTo: 'NVS Travels', counted: 1 })),
            { audit, items, parts },
        )
        expect(records[2]._errors[0]).toMatch(/Already listed higher up the sheet for this company/)
    })

    it('refuses a printed row whose Belongs to was changed', () => {
        const only = [items[0]]
        const { records, fatal } = validateCountSheet(
            sheet(printed('NVS Travel Solutions Pvt Ltd', 5)),
            { audit, items: only, parts },
        )
        expect(records[0]._errors[0]).toMatch(/printed for another company/)
        expect(fatal[0]).toMatch(/Alternator \(NVS Travels\)/)
    })

    it('stops on a sheet from before the column existed', () => {
        const old = [['audit_id', 'part_id', 'part_name', 'part_number', 'unit', 'system_qty', 'counted_qty'],
            ['audit-1', 'p1', 'Alternator', '', 'pcs', 5, 5]]
        const { fatal } = validateCountSheet(old, { audit, items: [items[0]], parts })
        expect(fatal).toContain('That sheet has no Belongs to column. Download a fresh count sheet for this audit.')
    })
})
