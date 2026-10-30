import { describe, it, expect } from 'vitest'
import { workTypeLabel, workTypeSummary, vehicleCount } from '../batchWorkTypes'

describe('workTypeLabel', () => {
    it('names a standard type, or the text typed for Other', () => {
        expect(workTypeLabel({ work_type: 'Greasing' })).toBe('Greasing')
        expect(workTypeLabel({ work_type: 'Other', work_type_other: 'Seat repair' })).toBe('Seat repair')
        expect(workTypeLabel({ work_type: 'Other' })).toBe('Other')
        expect(workTypeLabel({})).toBe('—')
    })
})

describe('workTypeSummary', () => {
    it('counts lines per work, standard types in list order, then Other work by name', () => {
        const lines = [
            { work_type: 'Puncture' },
            { work_type: 'Greasing' },
            { work_type: 'Other', work_type_other: 'Seat repair' },
            { work_type: 'Greasing' },
            { work_type: 'Other', work_type_other: 'Door fix' },
        ]
        expect(workTypeSummary(lines)).toBe('Greasing ×2 · Puncture ×1 · Door fix ×1 · Seat repair ×1')
    })

    it('is empty for no lines', () => {
        expect(workTypeSummary([])).toBe('')
        expect(workTypeSummary(undefined)).toBe('')
    })
})

describe('vehicleCount', () => {
    it('counts a vehicle with two kinds of work once', () => {
        expect(vehicleCount([
            { vehicle_number: 'KA01' }, { vehicle_number: 'KA01' }, { vehicle_number: 'KA02' },
        ])).toBe(2)
    })
})
