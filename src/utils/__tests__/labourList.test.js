import { describe, it, expect } from 'vitest'
import {
    peopleLabel, peopleValueLabel, itemShades, activeShortcut, PEOPLE_SHORTCUTS,
    labourHref, buildLabourExportRows,
} from '../labourList'
import { parseAnalytics, describeDrill } from '../analyticsDrill'
import { parseListState, toServerQuery, sortLabels } from '../listQuery'

const paramsOf = href => new URLSearchParams(href.split('?')[1])
const nov = { start: '2026-11-01', end: '2026-11-30' }

describe('peopleLabel', () => {
    it('names nobody, one person, and several with the item total', () => {
        expect(peopleLabel(0, '2')).toBe('Nobody recorded')
        expect(peopleLabel(1, '3')).toBe('1 person')
        expect(peopleLabel(3, '15.00')).toBe('3 people · 15 h')
        expect(peopleLabel(2, '0.1')).toBe('2 people · 0.1 h')
    })
    it('words the filter values', () => {
        expect(['0', '1', '4'].map(peopleValueLabel)).toEqual(['Nobody recorded', '1 person', '4 people'])
    })
})

describe('itemShades', () => {
    it('keeps one shade per work item and switches when the item changes', () => {
        const rows = ['a', 'a', 'b', 'b', 'b', 'c', 'a'].map(issue_id => ({ issue_id }))
        expect(itemShades(rows)).toEqual([false, false, true, true, true, false, true])
    })
    it('copes with nothing', () => {
        expect(itemShades(undefined)).toEqual([])
    })
})

describe('activeShortcut', () => {
    it('recognises each tile\'s filter and nothing else', () => {
        expect(activeShortcut(PEOPLE_SHORTCUTS.many)).toBe('many')
        expect(activeShortcut(PEOPLE_SHORTCUTS.one)).toBe('one')
        expect(activeShortcut(PEOPLE_SHORTCUTS.nobody)).toBe('nobody')
        expect(activeShortcut({ values: ['1', '2'] })).toBeNull()
        expect(activeShortcut({ min: '2', max: '3' })).toBeNull()
        expect(activeShortcut(undefined)).toBeNull()
    })
})

describe('labourHref', () => {
    it('opens the Labour list with the report\'s period and sites and what was clicked', () => {
        const href = labourHref(nov, { sites: ['BWIS', 'KUNS'] }, { technician_id: 'u1', completed_on: '2026-11-22' })
        expect(href.startsWith('/labour?')).toBe(true)
        expect(parseAnalytics(paramsOf(href))).toEqual({
            from: '2026-11-01', to: '2026-11-30', sites: ['BWIS', 'KUNS'],
            where: { technician_id: 'u1', completed_on: '2026-11-22' },
        })
    })

    it('carries the trade and technician chosen on the report as row conditions', () => {
        const drill = parseAnalytics(paramsOf(labourHref(nov, { trade: 'electrician', technicianId: 'u9' }, {})))
        expect(drill.where).toEqual({ technician_role: 'electrician', technician_id: 'u9' })
    })

    it('opens a clicked site as the only site', () => {
        const drill = parseAnalytics(paramsOf(labourHref(nov, { sites: ['BWIS', 'TSB'], trade: 'mechanic' }, { site: 'TSB' })))
        expect(drill.sites).toEqual(['TSB'])
        expect(drill.where).toEqual({ technician_role: 'mechanic' })
    })

    it('sends the unattributed tile as attributed = false, which the database compares as text', () => {
        const state = parseListState(paramsOf(labourHref(nov, {}, { attributed: false })), { sort: 'completed_on', dir: 'desc' })
        expect(toServerQuery(state).analytics).toEqual({
            from: '2026-11-01', to: '2026-11-30', sites: [], where: { attributed: 'false' },
        })
    })

    it('leaves out empty choices', () => {
        expect(parseAnalytics(paramsOf(labourHref(nov, { trade: '', technicianId: '' }, {}))).where).toEqual({})
    })
})

describe('describeDrill for labour', () => {
    it('says what was clicked, the activity complete period and the sites', () => {
        expect(describeDrill('labour', { from: '2026-11-01', to: '2026-11-30', sites: [], where: {} }))
            .toEqual(['All labour hours', 'completed 1 Nov – 30 Nov 2026', 'all sites'])
        expect(describeDrill('labour', { from: '2026-11-01', to: '2026-11-30', sites: ['BWIS'], where: { attributed: 'false' } }))
            .toEqual(['Unattributed hours', 'completed 1 Nov – 30 Nov 2026', 'site BWIS'])
    })

    it('names a technician and a single day instead of the period', () => {
        const drill = { from: '2026-11-01', to: '2026-11-30', sites: [], where: { technician_id: 'u1', completed_on: '2026-11-22' } }
        expect(describeDrill('labour', drill, { technician_id: { u1: 'Ravi Kumar' } }))
            .toEqual(['Ravi Kumar', 'Completed 22 Nov 2026', 'all sites'])
    })

    it('words a trade', () => {
        expect(describeDrill('labour', { from: '', to: '', sites: [], where: { technician_role: 'mechanic' } })[0]).toBe('Trade: Mechanic')
    })
})

describe('buildLabourExportRows', () => {
    it('writes one row per entry, with Not yet done and Unattributed spelled out', () => {
        const rows = buildLabourExportRows([
            { completed_on: '2026-11-22', technician: 'Ravi Kumar', technician_employee_id: 'NVS 1', trade: 'mechanic', hours: '3.50', people_on_item: 2, item_hours: '6', issue_number: 'T-1-01', category: 'Brakes', description: 'Drum', job_card_number: 34, vehicle_number: 'KA01', ticket_number: 1, site: 'BWIS' },
            { completed_on: null, technician: 'Unattributed', trade: null, hours: '2', people_on_item: 0, item_hours: '2' },
        ])
        expect(rows[0]).toMatchObject({ 'Activity Complete': '2026-11-22', 'Technician': 'Ravi Kumar', 'Trade': 'Mechanic', 'Hours': 3.5, 'People on Item': 2 })
        expect(rows[1]).toMatchObject({ 'Activity Complete': 'Not yet done', 'Technician': 'Unattributed', 'Trade': '', 'Hours': 2, 'People on Item': 0 })
    })
})

describe('sortLabels', () => {
    it('lets a column word its own sort', () => {
        expect(sortLabels({ filter: 'values', sortLabels: ['Fewest people first', 'Most people first'] }))
            .toEqual(['Fewest people first', 'Most people first'])
        expect(sortLabels({ filter: 'number' })).toEqual(['Smallest first', 'Largest first'])
    })
})
