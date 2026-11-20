import { describe, it, expect } from 'vitest'
import { formatPurchaseNumber, purchaseInvoicePath, parsePurchaseNumber } from '../purchaseInvoice'
import { formatSupplierNumber, supplierPath, supplierLedgerPath, parseSupplierNumber } from '../supplierNumber'
import { employeeKey, mechanicPath } from '../employeeId'

describe('purchase invoice number', () => {
    it('formats and links as PI-n', () => {
        expect(formatPurchaseNumber(257)).toBe('PI-257')
        expect(purchaseInvoicePath(257)).toBe('/inventory?tab=history&invoice=PI-257')
    })

    it('parses PI-n in any case, or a bare number, and rejects a long ID', () => {
        expect(parsePurchaseNumber('PI-257')).toBe(257)
        expect(parsePurchaseNumber('pi-257')).toBe(257)
        expect(parsePurchaseNumber('257')).toBe(257)
        expect(parsePurchaseNumber('af7b1010-7080-4964-af5a-e155705ed485')).toBeNull()
        expect(parsePurchaseNumber(null)).toBeNull()
    })
})

describe('supplier number', () => {
    it('formats and links as SUP-n', () => {
        expect(formatSupplierNumber(5)).toBe('SUP-5')
        expect(supplierPath(5)).toBe('/suppliers/SUP-5')
        expect(supplierLedgerPath(5)).toBe('/supplier-ledger/SUP-5')
    })

    it('parses SUP-n in any case, or a bare number, and rejects a long ID', () => {
        expect(parseSupplierNumber('SUP-5')).toBe(5)
        expect(parseSupplierNumber('sup-5')).toBe(5)
        expect(parseSupplierNumber('5')).toBe(5)
        expect(parseSupplierNumber('MVI-5')).toBeNull()
        expect(parseSupplierNumber('af7b1010-7080-4964-af5a-e155705ed485')).toBeNull()
    })
})

describe('employee ID', () => {
    it('treats case, spaces and hyphens as the same ID', () => {
        expect(employeeKey('NVS 1234')).toBe('nvs1234')
        expect(employeeKey('nvs-1234')).toBe('nvs1234')
        expect(employeeKey('\tNVS1234 ')).toBe('nvs1234')
    })

    it('addresses a mechanic with hyphens for spaces', () => {
        expect(mechanicPath('NVS 1234')).toBe('/mechanics/NVS-1234')
        expect(mechanicPath('NVS2723')).toBe('/mechanics/NVS2723')
        expect(mechanicPath('AUTO-3')).toBe('/mechanics/AUTO-3')
    })

    it('the address resolves back to the same key', () => {
        const id = 'NVS 1234'
        expect(employeeKey(decodeURIComponent(mechanicPath(id).split('/').pop()))).toBe(employeeKey(id))
    })
})
