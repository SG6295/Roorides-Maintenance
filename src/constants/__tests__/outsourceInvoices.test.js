/**
 * MAIN-118 — the finance status moves. The database's guard holds the same rules; this
 * keeps the dropdown's offer in step with them.
 */
import { describe, it, expect } from 'vitest'
import {
    FINANCE_STATUSES,
    FINANCE_STATUS_MOVES,
    FINANCE_LOCKED_STATUSES,
    isLockedByFinance,
    financeStatusMoves,
} from '../outsourceInvoices'

describe('FINANCE_STATUS_MOVES', () => {
    it('covers every status and moves only between real statuses', () => {
        expect(Object.keys(FINANCE_STATUS_MOVES).sort()).toEqual([...FINANCE_STATUSES].sort())
        for (const targets of Object.values(FINANCE_STATUS_MOVES)) {
            for (const t of targets) expect(FINANCE_STATUSES).toContain(t)
        }
    })

    it('makes Reject and both GST-closed statuses final', () => {
        expect(FINANCE_STATUS_MOVES['Reject']).toEqual([])
        expect(FINANCE_STATUS_MOVES['GST reconciled & closed']).toEqual([])
        expect(FINANCE_STATUS_MOVES['GST not applicable & closed']).toEqual([])
    })

    it('lets Hold go back to New, and Accepted back to Hold or on to Reject', () => {
        expect(FINANCE_STATUS_MOVES['Hold']).toContain('New')
        expect(FINANCE_STATUS_MOVES['Accepted']).toEqual(expect.arrayContaining(['Hold', 'Reject']))
        expect(FINANCE_STATUS_MOVES['Accepted']).not.toContain('New')
    })

    it('reaches a GST close only from Accepted', () => {
        for (const [from, targets] of Object.entries(FINANCE_STATUS_MOVES)) {
            if (from === 'Accepted') continue
            expect(targets.some(t => t.startsWith('GST'))).toBe(false)
        }
    })
})

describe('financeStatusMoves', () => {
    const purchase = (status, file) => ({
        finance_payment_status: status,
        purchase_invoice_id: 'pi1',
        purchase_invoice: { invoice_file_url: file },
    })

    it('never lets a purchase without its file reach New or Accepted (MAIN-129)', () => {
        expect(financeStatusMoves(purchase('New (invoice pending)', null))).toEqual(['Hold', 'Reject'])
        expect(financeStatusMoves(purchase('Hold', null))).toEqual(['New (invoice pending)', 'Reject'])
    })

    it('offers New (invoice pending) only to a purchase without its file', () => {
        expect(financeStatusMoves(purchase('Hold', 'https://drive/x'))).toEqual(['New', 'Reject', 'Accepted'])
        expect(financeStatusMoves({ finance_payment_status: 'Hold', job_card_id: 'jc1' })).toEqual(['New', 'Reject', 'Accepted'])
    })
})

describe('isLockedByFinance', () => {
    it('locks Accepted and the GST-closed statuses, and nothing else', () => {
        for (const status of FINANCE_STATUSES) {
            expect(isLockedByFinance({ finance_payment_status: status })).toBe(FINANCE_LOCKED_STATUSES.includes(status))
        }
        expect(FINANCE_LOCKED_STATUSES).toEqual(['Accepted', 'GST reconciled & closed', 'GST not applicable & closed'])
        expect(isLockedByFinance(null)).toBe(false)
    })
})
