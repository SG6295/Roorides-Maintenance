import { describe, it, expect } from 'vitest'
import {
    buildChange, draftErrors, draftFromVersion, formatWeeklyOffs, hasChanges, holidayChanges,
    onTimePercent, versionChanges, versionTimeline,
} from '../slaDraft'

const version = { id: 'v1', version_number: 1, acceptance_days: 2, weekly_offs: [0, 6] }
const turnaround = [
    { category: 'Mechanical', severity: 'Major', sla_days: 15 },
    { category: 'Tyre', severity: 'Minor', sla_days: 3 },
]

describe('formatWeeklyOffs', () => {
    it('reads Monday first', () => {
        expect(formatWeeklyOffs([0, 6])).toBe('Sat, Sun')
        expect(formatWeeklyOffs([])).toBe('None')
    })
})

describe('draftErrors', () => {
    it('accepts whole numbers 1-365 only, and at least one working day', () => {
        const draft = draftFromVersion(version, turnaround)
        expect(draftErrors(draft)).toEqual([])
        expect(draftErrors({ ...draft, acceptanceDays: '' })).toHaveLength(1)
        expect(draftErrors({ ...draft, acceptanceDays: '1.5' })).toHaveLength(1)
        expect(draftErrors({ ...draft, turnaround: { ...draft.turnaround, 'Minor|Tyre': '0' } })).toHaveLength(1)
        expect(draftErrors({ ...draft, weeklyOffs: [0, 1, 2, 3, 4, 5, 6] })).toHaveLength(1)
    })
})

describe('versionChanges', () => {
    it('is empty for an untouched draft, even mid-typing back to the same value', () => {
        const draft = draftFromVersion(version, turnaround)
        expect(versionChanges(version, turnaround, draft)).toEqual([])
        expect(hasChanges(version, turnaround, { ...draft, acceptanceDays: '02' })).toBe(false)
    })

    it('lists each changed setting old → new', () => {
        const draft = {
            ...draftFromVersion(version, turnaround),
            acceptanceDays: '1',
            weeklyOffs: [0],
            turnaround: { 'Major|Mechanical': '10', 'Minor|Tyre': '3' },
        }
        expect(versionChanges(version, turnaround, draft)).toEqual([
            { label: 'Acceptance SLA Threshold', from: '2 working days', to: '1 working day' },
            { label: 'Weekly Offs', from: 'Sat, Sun', to: 'Sun' },
            { label: 'Turnaround Time — Major Mechanical', from: '15 working days', to: '10 working days' },
        ])
    })
})

describe('buildChange', () => {
    it('sends the whole version only when it changed, and a start only then', () => {
        const draft = draftFromVersion(version, turnaround)
        draft.holidaysAdd = [{ date: '2026-12-25', description: '' }]
        expect(buildChange(version, turnaround, draft, { startsAt: '2026-12-01T00:00:00.000Z' })).toEqual({
            base_version_id: 'v1',
            starts_at: null,
            version: null,
            holidays_add: [{ date: '2026-12-25', description: null }],
            holidays_remove: [],
        })

        draft.turnaround['Minor|Tyre'] = '5'
        const change = buildChange(version, turnaround, draft, { reason: 'Tyres take longer', startsAt: null })
        expect(change.reason).toBe('Tyres take longer')
        expect(change.version).toEqual({
            acceptance_days: 2,
            weekly_offs: [0, 6],
            turnaround: [
                { category: 'Mechanical', severity: 'Major', sla_days: 15 },
                { category: 'Tyre', severity: 'Minor', sla_days: 5 },
            ],
        })
    })
})

describe('holidayChanges', () => {
    it('names removed holidays from the calendar', () => {
        const draft = { ...draftFromVersion(version, turnaround), holidaysRemove: ['2026-12-25'] }
        expect(holidayChanges([{ date: '2026-12-25', description: 'Christmas' }], draft))
            .toEqual([{ action: 'remove', date: '2026-12-25', description: 'Christmas' }])
    })
})

describe('onTimePercent', () => {
    it('shows a dash when nothing was judged', () => {
        expect(onTimePercent(633, 738)).toBe('85.8%')
        expect(onTimePercent(0, 0)).toBe('—')
    })
})

describe('versionTimeline', () => {
    const now = new Date('2026-11-20T00:00:00Z')
    const versions = [
        { id: 'a', version_number: 1, starts_at: '2026-08-13T18:30:00Z', cancelled_at: null },
        { id: 'b', version_number: 2, starts_at: '2026-11-18T00:00:00Z', cancelled_at: null },
        { id: 'c', version_number: 3, starts_at: '2026-12-01T00:00:00Z', cancelled_at: '2026-11-19T00:00:00Z' },
        { id: 'd', version_number: 4, starts_at: '2026-12-05T00:00:00Z', cancelled_at: null },
    ]

    it('ends a version when the next live one starts, skipping cancelled ones', () => {
        const byNumber = Object.fromEntries(versionTimeline(versions, now).map(v => [v.version_number, v]))
        expect(byNumber[1]).toMatchObject({ state: 'ended', ends_at: '2026-11-18T00:00:00Z' })
        expect(byNumber[2]).toMatchObject({ state: 'active', ends_at: '2026-12-05T00:00:00Z' })
        expect(byNumber[3]).toMatchObject({ state: 'cancelled', ends_at: null })
        expect(byNumber[4]).toMatchObject({ state: 'scheduled', ends_at: null })
        expect(versionTimeline(versions, now).map(v => v.version_number)).toEqual([4, 3, 2, 1])
    })
})
