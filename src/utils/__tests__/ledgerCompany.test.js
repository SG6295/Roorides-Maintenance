import { describe, it, expect } from 'vitest'
import {
    ledgerCompanyFrom, withLedgerCompany, supplierLedgerHome, advanceStatementPath,
} from '../ledgerCompany'
import { supplierLedgerPath } from '../supplierNumber'

const params = q => new URLSearchParams(q)

describe('ledgerCompanyFrom (MAIN-162)', () => {
    it('reads the company from ?co=', () => {
        expect(ledgerCompanyFrom(params('co=nvs-travels'))).toBe('nvs_travels')
        expect(ledgerCompanyFrom(params('co=nvs-travel-solutions'))).toBe('nvs_travel_solutions')
    })

    it('is NVS Travels when there is no co, so links from before the split still open', () => {
        expect(ledgerCompanyFrom(params(''))).toBe('nvs_travels')
        expect(ledgerCompanyFrom(undefined)).toBe('nvs_travels')
    })

    it('is NVS Travels for anything that is not a company', () => {
        expect(ledgerCompanyFrom(params('co=unknown'))).toBe('nvs_travels')
        expect(ledgerCompanyFrom(params('co=nvs_travel_solutions'))).toBe('nvs_travels')
    })
})

describe('ledger addresses', () => {
    it('puts the company before any #section', () => {
        expect(withLedgerCompany('/supplier-ledger#advances', 'nvs_travel_solutions'))
            .toBe('/supplier-ledger?co=nvs-travel-solutions#advances')
        expect(supplierLedgerHome('nvs_travels')).toBe('/supplier-ledger?co=nvs-travels')
    })

    it('builds a person’s statement address with their ledger name encoded', () => {
        expect(advanceStatementPath('NVS 659 Manjunath', 'nvs_travel_solutions'))
            .toBe('/supplier-ledger/advances/NVS%20659%20Manjunath?co=nvs-travel-solutions')
    })

    it('builds a supplier statement address, with or without a company', () => {
        expect(supplierLedgerPath(5)).toBe('/supplier-ledger/SUP-5')
        expect(supplierLedgerPath(5, 'nvs_travel_solutions')).toBe('/supplier-ledger/SUP-5?co=nvs-travel-solutions')
    })
})

describe('possessive', () => {
    it('reads naturally for both company names', async () => {
        const { possessive } = await import('../ledgerCompany')
        expect(possessive('NVS Travels')).toBe("NVS Travels'")
        expect(possessive('NVS Travel Solutions Pvt Ltd')).toBe("NVS Travel Solutions Pvt Ltd's")
    })
})
