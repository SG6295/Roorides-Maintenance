import { describe, it, expect } from 'vitest'
import {
    canSeeCosts,
    rupees,
    jobCardValueLabel,
    jobCardValueBasis,
    needsPriceError,
    priceFormError,
} from '../jobCardValue'

describe('canSeeCosts', () => {
    it('is exec, super_admin and finance only', () => {
        expect(canSeeCosts('maintenance_exec')).toBe(true)
        expect(canSeeCosts('super_admin')).toBe(true)
        expect(canSeeCosts('finance')).toBe(true)
        expect(canSeeCosts('mechanic')).toBe(false)
        expect(canSeeCosts('supervisor')).toBe(false)
        expect(canSeeCosts(undefined)).toBe(false)
    })
})

describe('jobCardValueLabel', () => {
    it('shows the value, including zero', () => {
        expect(jobCardValueLabel({ type: 'InHouse', value: 1234.5 })).toEqual({ text: '₹1,234.50', muted: false })
        expect(jobCardValueLabel({ type: 'InHouse', value: 0 })).toEqual({ text: '₹0.00', muted: false })
        expect(jobCardValueLabel({ type: 'Outsource', value: '4500.00' })).toEqual({ text: '₹4,500.00', muted: false })
    })

    it('says why there is no value', () => {
        expect(jobCardValueLabel({ type: 'Outsource', value: null }).text).toBe('Invoice pending')
        expect(jobCardValueLabel({ type: 'InHouse', value: null }).text).toBe('Price missing')
    })

    it('groups lakhs the Indian way', () => {
        expect(rupees(1234567.8)).toBe('₹12,34,567.80')
    })
})

describe('jobCardValueBasis', () => {
    it('names what the value is', () => {
        expect(jobCardValueBasis({ type: 'Outsource' })).toMatch(/Approved Amount/)
        expect(jobCardValueBasis({ type: 'InHouse' })).toMatch(/first-in-first-out/)
    })
})

describe('needsPriceError', () => {
    it('reads the part from the refusal', () => {
        const error = {
            message: 'No price is recorded for Jack (NVS Travels): …',
            hint: 'PART_NEEDS_PRICE',
            details: '{"part_id" : "p1", "part_name" : "Jack", "unit" : "pcs", "company" : "nvs_travels", "quantity" : 1.00}',
        }
        expect(needsPriceError(error)).toEqual({
            partId: 'p1', partName: 'Jack', unit: 'pcs', company: 'nvs_travels', quantity: 1,
        })
    })

    it('ignores every other error', () => {
        expect(needsPriceError({ message: 'Not enough stock', hint: null })).toBeNull()
        expect(needsPriceError(undefined)).toBeNull()
    })
})

describe('priceFormError', () => {
    it('needs a price of 0 or more and a GST %', () => {
        expect(priceFormError({ unitPrice: '', gstRate: '18' })).toMatch(/price/)
        expect(priceFormError({ unitPrice: '-1', gstRate: '18' })).toMatch(/0 or more/)
        expect(priceFormError({ unitPrice: 'abc', gstRate: '18' })).toMatch(/0 or more/)
        expect(priceFormError({ unitPrice: '10', gstRate: '' })).toMatch(/GST/)
        expect(priceFormError({ unitPrice: '0', gstRate: '0' })).toBeNull()
        expect(priceFormError({ unitPrice: '2205', gstRate: '18' })).toBeNull()
    })
})
