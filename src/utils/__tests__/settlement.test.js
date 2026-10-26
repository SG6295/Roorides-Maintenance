import { describe, it, expect } from 'vitest'
import { toPaise, paiseToInput, invoiceSettlement, roundOffOffer } from '../settlement'

describe('toPaise', () => {
    it('converts typed and stored amounts exactly', () => {
        expect(toPaise('4200')).toBe(420000)
        expect(toPaise('4191.33')).toBe(419133)
        expect(toPaise('0.5')).toBe(50)
        expect(toPaise(2178.5)).toBe(217850)
        expect(toPaise('4200.00')).toBe(420000)
    })

    it('treats blank as zero', () => {
        expect(toPaise('')).toBe(0)
        expect(toPaise(null)).toBe(0)
    })

    it('rejects more than two decimals, negatives and junk instead of rounding', () => {
        expect(toPaise('42.333')).toBeNaN()
        expect(toPaise('-5')).toBeNaN()
        expect(toPaise('1,000')).toBeNaN()
        expect(toPaise('abc')).toBeNaN()
    })

    it('adds without float drift', () => {
        expect(toPaise('0.1') + toPaise('0.2')).toBe(toPaise('0.3'))
    })
})

describe('paiseToInput', () => {
    it('formats paise as a two-decimal input value', () => {
        expect(paiseToInput(419100)).toBe('4191.00')
        expect(paiseToInput(5)).toBe('0.05')
        expect(paiseToInput(-80000)).toBe('-800.00')
    })
})

describe('invoiceSettlement', () => {
    const invoice = { approved_amount: '4233.33', advance_amount: '0.00' }

    it('sums active payments and ignores cancelled ones', () => {
        const payments = [
            { amount_paid: '2000', tds_amount: '0', round_off: '0', status: 'Cancelled' },
            { amount_paid: '4191', tds_amount: '42.33', round_off: '0', status: 'Active' },
        ]
        expect(invoiceSettlement(invoice, payments)).toEqual({
            payable: 423333, paid: 419100, tds: 4233, roundOff: 0, settled: 423333, balance: 0,
        })
    })

    it('subtracts the advance from the payable', () => {
        expect(invoiceSettlement({ approved_amount: 5000, advance_amount: 1000 }).payable).toBe(400000)
    })

    it('reports overpayment as a negative balance', () => {
        const payments = [{ amount_paid: '2200', tds_amount: '0', round_off: '0', status: 'Active' }]
        expect(invoiceSettlement({ approved_amount: 2000, advance_amount: 0 }, payments).balance).toBe(-20000)
    })
})

describe('roundOffOffer', () => {
    it('offers a sub-rupee remainder', () => {
        // ₹4,191.33 due, ₹4,191 paid: 33 paise left
        expect(roundOffOffer(419133, 419100, 0)).toBe(33)
    })

    it('offers nothing when the payment settles exactly, overpays, or leaves ₹1 or more', () => {
        expect(roundOffOffer(419133, 419133, 0)).toBe(0)
        expect(roundOffOffer(419133, 419200, 0)).toBe(0)
        expect(roundOffOffer(419133, 419033, 0)).toBe(0)
    })
})
