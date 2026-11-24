import { describe, it, expect } from 'vitest'
import {
    ASSIGNABLE_COMPANIES, changeKind, companyLabel, isUnassignedVehicle, saleErrors,
    unassignedVehicleMessage,
} from '../vehicleCompanies'

describe('vehicle companies (MAIN-155)', () => {
    it('labels each company and never offers Unknown as a target', () => {
        expect(companyLabel('nvs_travels')).toBe('NVS Travels')
        expect(companyLabel('nvs_travel_solutions')).toBe('NVS Travel Solutions Pvt Ltd')
        expect(companyLabel('unknown')).toBe('Unknown')
        expect(ASSIGNABLE_COMPANIES.map(c => c.value)).toEqual(['nvs_travels', 'nvs_travel_solutions'])
    })

    it('uses the database message word for word', () => {
        expect(unassignedVehicleMessage('KA51B5997'))
            .toBe('Kindly contact finance to assign vehicle KA51B5997 in order to proceed.')
    })

    it('blocks only a vehicle known to be Unknown', () => {
        expect(isUnassignedVehicle({ company: 'unknown' })).toBe(true)
        expect(isUnassignedVehicle({ company: 'nvs_travels' })).toBe(false)
        expect(isUnassignedVehicle(null)).toBe(false)
    })

    it('tells an assignment from a sale', () => {
        expect(changeKind('unknown', 'nvs_travels')).toBe('assignment')
        expect(changeKind('nvs_travels', 'nvs_travel_solutions')).toBe('sale')
        expect(changeKind('nvs_travels', 'nvs_travels')).toBeNull()
        expect(changeKind('nvs_travels', '')).toBeNull()
    })

    it('checks a sale value and GST % as the database does', () => {
        expect(saleErrors({ saleValue: '500000', gstPercent: '28' })).toEqual({})
        expect(saleErrors({ saleValue: '1200.50', gstPercent: '0' })).toEqual({})
        expect(Object.keys(saleErrors({ saleValue: '', gstPercent: '' }))).toEqual(['saleValue', 'gstPercent'])
        expect(Object.keys(saleErrors({ saleValue: '0', gstPercent: '18' }))).toEqual(['saleValue'])
        expect(Object.keys(saleErrors({ saleValue: '10.555', gstPercent: '18' }))).toEqual(['saleValue'])
        expect(Object.keys(saleErrors({ saleValue: '100', gstPercent: '101' }))).toEqual(['gstPercent'])
        expect(Object.keys(saleErrors({ saleValue: '100', gstPercent: '-1' }))).toEqual(['gstPercent'])
    })
})
