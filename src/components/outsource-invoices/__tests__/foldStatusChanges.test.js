import { describe, it, expect } from 'vitest'
import { foldStatusChanges } from '../historyEntries'

const T1 = '2026-10-26T10:00:00+00:00'
const T2 = '2026-10-26T11:00:00+00:00'

const payment = (at, who = 'Vijay') => ({
    performed_at: at, performed_by_name: who, source: 'payment', action: 'INSERT', new_data: { amount_paid: 2000 },
})
const statusChange = (at, from, to, who = 'Vijay') => ({
    performed_at: at, performed_by_name: who, source: 'invoice', action: 'UPDATE',
    changed_fields: ['finance_payment_status'],
    old_data: { finance_payment_status: from }, new_data: { finance_payment_status: to },
})

describe('foldStatusChanges', () => {
    it('attaches the recalculated status to the payment that caused it', () => {
        const out = foldStatusChanges([statusChange(T1, 'Due', 'Partly Paid'), payment(T1)])

        expect(out).toHaveLength(1)
        expect(out[0].source).toBe('payment')
        expect(out[0].statusChange.new_data.finance_payment_status).toBe('Partly Paid')
    })

    it('keeps a status change made by hand as its own entry', () => {
        const out = foldStatusChanges([statusChange(T2, 'Due', 'Hold - on request'), payment(T1)])

        expect(out).toHaveLength(2)
        expect(out[0].source).toBe('invoice')
        expect(out[1].statusChange).toBeUndefined()
    })

    it('does not fold another person\'s change made at the same moment', () => {
        const out = foldStatusChanges([statusChange(T1, 'Due', 'Hold - on request', 'Manjunath'), payment(T1)])
        expect(out).toHaveLength(2)
    })

    it('leaves multi-field changes alone and sorts newest first', () => {
        const multi = { ...statusChange(T1, 'Due', 'Hold - on request'), changed_fields: ['finance_payment_status', 'finance_remark'] }
        const out = foldStatusChanges([multi, payment(T2)])

        expect(out.map(e => e.performed_at)).toEqual([T2, T1])
        expect(out[1].changed_fields).toHaveLength(2)
    })
})
