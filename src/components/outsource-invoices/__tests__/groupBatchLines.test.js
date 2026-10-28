import { describe, it, expect } from 'vitest'
import { groupBatchLines } from '../historyEntries'

const T1 = '2026-10-28T10:00:00+00:00'
const T2 = '2026-10-28T11:00:00+00:00'

const line = (at, action, vehicle, who = 'Ravi') => ({
    performed_at: at, performed_by_name: who, source: 'batch_vehicle', action,
    new_data: { vehicle_number: vehicle, amount: 50 },
})
const invoice = at => ({ performed_at: at, performed_by_name: 'Ravi', source: 'invoice', action: 'INSERT' })

describe('groupBatchLines', () => {
    it('folds the lines of one save into a single entry', () => {
        const out = groupBatchLines([invoice(T1), line(T1, 'INSERT', 'A'), line(T1, 'INSERT', 'B'), line(T1, 'INSERT', 'C')])

        expect(out).toHaveLength(2)
        expect(out[1].source).toBe('batch_lines')
        expect(out[1].lines.map(l => l.new_data.vehicle_number)).toEqual(['A', 'B', 'C'])
    })

    it('keeps separate saves and separate people apart', () => {
        const out = groupBatchLines([line(T2, 'DELETE', 'A'), line(T1, 'INSERT', 'A'), line(T1, 'INSERT', 'B', 'Asha')])

        expect(out).toHaveLength(3)
        expect(out.every(e => e.source === 'batch_lines')).toBe(true)
        expect(out[0].performed_at).toBe(T2)
    })

    it('leaves job-card invoice history untouched', () => {
        const entries = [invoice(T2), invoice(T1)]
        expect(groupBatchLines(entries)).toEqual(entries)
    })
})
