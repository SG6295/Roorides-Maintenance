import { describe, it, expect } from 'vitest'
import { formatBatchNumber, batchPath, parseBatchNumber } from '../batchNumber'

describe('batch number', () => {
    it('formats and links as MVI-n', () => {
        expect(formatBatchNumber(12)).toBe('MVI-12')
        expect(batchPath(12)).toBe('/multi-vehicle-invoices/MVI-12')
    })

    it('parses MVI-n in any case, or a bare number', () => {
        expect(parseBatchNumber('MVI-12')).toBe(12)
        expect(parseBatchNumber('mvi-12')).toBe(12)
        expect(parseBatchNumber('12')).toBe(12)
    })

    it('rejects anything else', () => {
        expect(parseBatchNumber('new')).toBeNull()
        expect(parseBatchNumber('MVI-')).toBeNull()
        expect(parseBatchNumber('af7b1010-7080-4964-af5a-e155705ed485')).toBeNull()
        expect(parseBatchNumber(undefined)).toBeNull()
    })
})
