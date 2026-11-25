import { describe, it, expect } from 'vitest'
import {
    describeEntry, owedWording, ledgerTotals, linesInRange,
    companyFromSlug, companyLedgerPath, otherCompany,
} from '../companyLedger'

// MAIN-156 — how company ledger lines read, from get_company_ledger rows.

const purchase = {
    kind: 'purchase', entry_at: '2026-11-20T06:00:00+00:00', doc_date: '2026-11-18',
    spend: 1180, owed: 0, gst: 180, gst_status: 'claimed',
    detail: { purchase_number: 257, invoice_no: 'INV-9', supplier: 'Sri Ram Auto', finance_status: 'GST reconciled & closed' },
}
const oldPurchase = {
    kind: 'purchase', entry_at: '2026-03-01 10:00:00', doc_date: '2026-03-01',
    spend: 500.5, owed: 0, gst: 76.35, gst_status: 'unknown',
    detail: { purchase_number: 12, invoice_no: 'B-1', supplier: 'Lakshmi Tyres', finance_status: null },
}
const jobCard = {
    kind: 'job_card', entry_at: '2026-11-21T06:00:00+00:00', doc_date: '2026-11-19',
    spend: 4500, owed: 0, gst: null, gst_status: 'not_reconciled',
    detail: { invoice_no: 'A-77', supplier: 'HKGN', job_card_number: 3412, vehicle: 'KA51AL5240' },
}
const mvi = {
    kind: 'multi_vehicle', entry_at: '2026-11-22T06:00:00+00:00', doc_date: '2026-11-22',
    spend: 300, owed: 0, gst: null, gst_status: 'no_gst',
    detail: { invoice_no: 'P-3', supplier: 'Puncher shop', batch_number: 3, vehicle_count: 2 },
}
const sold = {
    kind: 'vehicle_sold', entry_at: '2026-11-24T22:38:00+00:00', doc_date: '2026-11-25',
    spend: 0, owed: 1200000, gst: 183050.85, gst_status: 'inter_company',
    detail: { vehicle: 'KA01AU2250', other_company: 'nvs_travel_solutions', gst_percent: 18, performed_by: 'Finance One' },
}
const bought = {
    kind: 'vehicle_bought', entry_at: '2026-11-24T22:33:00+00:00', doc_date: '2026-11-25',
    spend: 0, owed: -1250000.5, gst: 273437.61, gst_status: 'inter_company',
    detail: { vehicle: 'KA01AU2250', other_company: 'nvs_travels', gst_percent: 28, performed_by: 'Finance One' },
}

describe('describeEntry', () => {
    it('links a purchase to its PI page and gives the bill date', () => {
        expect(describeEntry(purchase)).toEqual({
            title: 'INV-9 · Sri Ram Auto',
            sub: 'Bill dated 18 Nov 2026',
            link: { to: '/inventory?tab=history&invoice=PI-257', label: 'PI-257' },
        })
    })

    it('says an old purchase never went to finance', () => {
        expect(describeEntry(oldPurchase).sub).toBe('Bill dated 01 Mar 2026 · Recorded before purchases went to finance')
    })

    it('links a job card invoice to its job card', () => {
        const d = describeEntry(jobCard)
        expect(d.link).toEqual({ to: '/job-cards/3412', label: 'Job card 3412' })
        expect(d.sub).toBe('KA51AL5240 · Work on 19 Nov 2026')
    })

    it('links a multi-vehicle invoice to its MVI page', () => {
        const d = describeEntry(mvi)
        expect(d.link).toEqual({ to: '/multi-vehicle-invoices/MVI-3', label: 'MVI-3' })
        expect(d.sub).toBe('2 vehicles · Work on 22 Nov 2026')
    })

    it('names the other company on a vehicle sale, either way round', () => {
        expect(describeEntry(sold).title).toBe('KA01AU2250 sold to NVS Travel Solutions Pvt Ltd')
        expect(describeEntry(bought).title).toBe('KA01AU2250 bought from NVS Travels')
        expect(describeEntry(sold).sub).toBe('GST 18% included · Recorded by Finance One')
    })
})

describe('owedWording', () => {
    it('reads from the ledger company’s side', () => {
        expect(owedWording(50000.5, 'nvs_travels')).toBe('Pvt Ltd owes NVS Travels')
        expect(owedWording(-50000.5, 'nvs_travel_solutions')).toBe('Pvt Ltd owes NVS Travels')
        expect(owedWording(-10, 'nvs_travels')).toBe('NVS Travels owes Pvt Ltd')
    })

    it('treats less than a paisa as nothing owed', () => {
        expect(owedWording(0.001, 'nvs_travels')).toBe('Nothing owed')
        expect(owedWording(null, 'nvs_travels')).toBe('Nothing owed')
    })
})

describe('ledgerTotals', () => {
    it('keeps spend and owed apart — a vehicle bought is owed, not spent', () => {
        const t = ledgerTotals([bought, sold])
        expect(t.spent).toBe(0)
        expect(t.owed).toBe(-50000.5)
    })

    it('adds money exactly, in paise', () => {
        const t = ledgerTotals([{ ...purchase, spend: 0.1, gst: 0.1 }, { ...purchase, spend: 0.2, gst: 0.2 }])
        expect(t.spent).toBe(0.3)
        expect(t.gst).toBe(0.3)
    })

    it('splits GST by status and counts the invoices whose GST is not recorded', () => {
        const t = ledgerTotals([purchase, oldPurchase, jobCard, mvi, sold])
        expect(t.spent).toBe(6480.5)
        expect(t.gst).toBe(183307.2)
        expect(t.spendGst).toBe(256.35)
        expect(t.gstByStatus).toEqual({
            claimed: 180, no_gst: 0, not_reconciled: 0, unknown: 76.35, inter_company: 183050.85,
        })
        expect(t.gstNotRecorded).toBe(2)
        expect(t.gstNotRecordedAmount).toBe(4800)
        expect(t.count).toBe(5)
    })
})

describe('linesInRange', () => {
    // Mid-day timestamps, so the day is the same in IST and in UTC (where CI runs).
    it('keeps entries recorded between the two days, either end optional', () => {
        expect(linesInRange([purchase, jobCard, mvi], '2026-11-21', '2026-11-21')).toEqual([jobCard])
        expect(linesInRange([purchase, jobCard, mvi], '', '2026-11-20')).toEqual([purchase])
        expect(linesInRange([purchase, jobCard, mvi], '2026-11-21', '')).toEqual([jobCard, mvi])
        expect(linesInRange([purchase, jobCard], '', '')).toHaveLength(2)
    })
})

describe('addresses', () => {
    it('maps slugs to companies and back', () => {
        expect(companyFromSlug('nvs-travel-solutions')).toBe('nvs_travel_solutions')
        expect(companyFromSlug('unknown')).toBeNull()
        expect(companyLedgerPath('nvs_travels')).toBe('/company-ledger/nvs-travels')
        expect(otherCompany('nvs_travels')).toBe('nvs_travel_solutions')
    })
})
