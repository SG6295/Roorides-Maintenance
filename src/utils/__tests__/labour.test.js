import { describe, it, expect } from 'vitest'
import { issueLabourHours, totalLabourHours, labourTechnicianNames, formatHours, initials } from '../labour'

describe('issueLabourHours', () => {
    it('sums per-technician rows and ignores the legacy value', () => {
        const issue = { labour_hours: 5, issue_labour: [{ hours: '2' }, { hours: '1.5' }] }
        expect(issueLabourHours(issue)).toEqual({ hours: 3.5, unattributed: 0 })
    })

    it('treats the legacy value as unattributed when nobody is recorded', () => {
        expect(issueLabourHours({ labour_hours: '0.5', issue_labour: [] })).toEqual({ hours: 0.5, unattributed: 0.5 })
    })

    it('is zero when nothing is recorded', () => {
        expect(issueLabourHours({ labour_hours: null })).toEqual({ hours: 0, unattributed: 0 })
        expect(issueLabourHours(undefined)).toEqual({ hours: 0, unattributed: 0 })
    })
})

describe('totalLabourHours', () => {
    it('adds attributed and legacy hours across work items', () => {
        const issues = [
            { issue_labour: [{ hours: 2 }, { hours: 1.5 }] },
            { labour_hours: 0.5 },
        ]
        expect(totalLabourHours(issues)).toBe(4)
    })
})

describe('labourTechnicianNames', () => {
    it('lists each technician once, in first-seen order', () => {
        const issues = [
            { issue_labour: [{ technician: { name: 'Manoj' } }, { technician: { name: 'Akbar' } }] },
            { issue_labour: [{ technician: { name: 'Manoj' } }] },
            { labour_hours: 1 },
        ]
        expect(labourTechnicianNames(issues)).toEqual(['Manoj', 'Akbar'])
    })
})

describe('formatting', () => {
    it('drops trailing zeros from hours', () => {
        expect(formatHours(2)).toBe('2')
        expect(formatHours(2.5)).toBe('2.5')
        expect(formatHours(0.1 + 0.2)).toBe('0.3')
    })

    it('takes the first two initials', () => {
        expect(initials('Mechanical Manoj')).toBe('MM')
        expect(initials('akbar pasha khan')).toBe('AP')
        expect(initials('')).toBe('')
    })
})
