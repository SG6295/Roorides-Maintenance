import { describe, it, expect } from 'vitest'
import {
    initialAuditLines,
    unallocatedQty,
    isMismatchExplained,
    savableAuditLines,
} from '../auditReasons'

const line = (quantity, reason = 'missing', notes = '') => ({ quantity, reason, notes })

describe('initialAuditLines', () => {
    it('offers one blank line for the whole difference when nothing is saved', () => {
        expect(initialAuditLines({ variance: -10, reason_lines: [] })).toEqual([
            { quantity: '10', reason: '', notes: '' },
        ])
    })

    it('returns saved lines in their saved order', () => {
        const item = {
            variance: -4,
            reason_lines: [
                { quantity: 1, reason: 'damaged', notes: 'by Mr. Ram', sort_order: 1 },
                { quantity: 3, reason: 'missing', notes: null, sort_order: 0 },
            ],
        }
        expect(initialAuditLines(item)).toEqual([
            { quantity: '3', reason: 'missing', notes: '' },
            { quantity: '1', reason: 'damaged', notes: 'by Mr. Ram' },
        ])
    })
})

describe('unallocatedQty', () => {
    it('measures against the size of the difference, whichever way it goes', () => {
        expect(unallocatedQty(-10, [line('3')])).toBe(7)
        expect(unallocatedQty(10, [line('3', 'found')])).toBe(7)
    })

    it('does not drift on decimal quantities', () => {
        expect(unallocatedQty(-0.3, [line('0.1'), line('0.2')])).toBe(0)
    })

    it('is negative when the lines cover too much', () => {
        expect(unallocatedQty(-2, [line('3')])).toBe(-1)
    })
})

describe('isMismatchExplained', () => {
    it('accepts the ticket example', () => {
        const lines = [
            line('3'),
            line('1', 'damaged', 'damaged by Mr. Ram'),
            line('1', 'damaged', 'damaged by Mr. Sham'),
            line('5', 'stolen', 'night of 5th Oct 2026'),
        ]
        expect(isMismatchExplained(-10, lines)).toBe(true)
    })

    it('refuses lines that do not add up', () => {
        expect(isMismatchExplained(-10, [line('9')])).toBe(false)
        expect(isMismatchExplained(-10, [line('11')])).toBe(false)
    })

    it('refuses a line with no reason', () => {
        expect(isMismatchExplained(-1, [line('1', '')])).toBe(false)
    })

    it('needs a note for Other', () => {
        expect(isMismatchExplained(-1, [line('1', 'other', '  ')])).toBe(false)
        expect(isMismatchExplained(-1, [line('1', 'other', 'fell in the pit')])).toBe(true)
    })
})

describe('savableAuditLines', () => {
    it('drops half-filled lines and tidies the rest', () => {
        expect(savableAuditLines([line('2', 'missing', ' lost '), line('1', ''), line('', 'stolen')])).toEqual([
            { quantity: 2, reason: 'missing', notes: 'lost' },
        ])
    })
})
