/**
 * MAIN-148 — a part name is refused when it matches an existing part's ignoring capitals
 * and extra spaces. partNameKey must agree with public.part_name_key().
 */
import { describe, it, expect } from 'vitest'
import { partNameKey, findSameNamePart, isDuplicatePartNameError, duplicatePartMessage } from '../partName'

const parts = [
    { id: 'a', name: 'Piano Switch' },
    { id: 'b', name: 'Drag link assy' },
]

describe('partNameKey', () => {
    it('ignores capitals, end spaces and doubled spaces', () => {
        expect(partNameKey('  Piano   Switch ')).toBe('piano switch')
        expect(partNameKey('piano\tswitch')).toBe('piano switch')
    })

    it('keeps other differences', () => {
        expect(partNameKey('Piano-Switch')).not.toBe(partNameKey('Piano Switch'))
    })

    it('treats a missing name as blank', () => {
        expect(partNameKey(null)).toBe('')
    })
})

describe('findSameNamePart', () => {
    it('finds the existing part', () => {
        expect(findSameNamePart(parts, 'piano switch ')).toBe(parts[0])
    })

    it('ignores the part being renamed', () => {
        expect(findSameNamePart(parts, 'PIANO SWITCH', 'a')).toBeNull()
        expect(findSameNamePart(parts, 'drag link assy', 'a')).toBe(parts[1])
    })

    it('finds nothing for a blank or new name', () => {
        expect(findSameNamePart(parts, '   ')).toBeNull()
        expect(findSameNamePart(parts, 'Battery XP 1000')).toBeNull()
    })
})

describe('isDuplicatePartNameError', () => {
    it('recognises the unique name refusal only', () => {
        expect(isDuplicatePartNameError({ code: '23505', message: 'duplicate key value violates unique constraint "parts_name_key_key"' })).toBe(true)
        expect(isDuplicatePartNameError({ code: '23505', message: 'duplicate key value violates unique constraint "parts_pkey"' })).toBe(false)
        expect(isDuplicatePartNameError(new Error('network'))).toBe(false)
    })
})

describe('duplicatePartMessage', () => {
    it('names the existing part', () => {
        expect(duplicatePartMessage({ name: 'Terminal spray ' })).toBe("Already in the catalog as 'Terminal spray' — use that one")
        expect(duplicatePartMessage(null)).toBe('Already in the catalog — use that one')
    })
})
