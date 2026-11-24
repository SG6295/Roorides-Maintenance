import { describe, it, expect } from 'vitest'
import { wrongCompanyLines } from '../batchCompany'

const companyOf = new Map([
    ['PVT1', 'nvs_travel_solutions'],
    ['TRV1', 'nvs_travels'],
    ['UNK1', 'unknown'],
])

describe('wrongCompanyLines', () => {
    it('flags nothing until Billed to is chosen', () => {
        const lines = [{ key: 'a', id: null, vehicle_number: 'TRV1' }]
        expect(wrongCompanyLines({ lines, billedTo: '', savedVehicles: new Map(), companyOf }).size).toBe(0)
    })

    it('flags a new line whose vehicle belongs to the other company', () => {
        const lines = [
            { key: 'a', id: null, vehicle_number: 'PVT1' },
            { key: 'b', id: null, vehicle_number: 'TRV1' },
        ]
        const wrong = wrongCompanyLines({ lines, billedTo: 'nvs_travel_solutions', savedVehicles: new Map(), companyOf })
        expect([...wrong]).toEqual(['b'])
    })

    it('leaves Unknown vehicles to their own message', () => {
        const lines = [{ key: 'a', id: null, vehicle_number: 'UNK1' }]
        expect(wrongCompanyLines({ lines, billedTo: 'nvs_travels', savedVehicles: new Map(), companyOf }).size).toBe(0)
    })

    it('keeps an unchanged saved line whose vehicle was sold since', () => {
        const lines = [{ key: 'a', id: 'l1', vehicle_number: 'TRV1' }]
        const wrong = wrongCompanyLines({
            lines, billedTo: 'nvs_travel_solutions', savedBilledTo: 'nvs_travel_solutions',
            savedVehicles: new Map([['l1', 'TRV1']]), companyOf,
        })
        expect(wrong.size).toBe(0)
    })

    it('checks a saved line again when its vehicle changes', () => {
        const lines = [{ key: 'a', id: 'l1', vehicle_number: 'TRV1' }]
        const wrong = wrongCompanyLines({
            lines, billedTo: 'nvs_travel_solutions', savedBilledTo: 'nvs_travel_solutions',
            savedVehicles: new Map([['l1', 'PVT1']]), companyOf,
        })
        expect([...wrong]).toEqual(['a'])
    })

    it('checks every line when Billed to changes', () => {
        const lines = [{ key: 'a', id: 'l1', vehicle_number: 'PVT1' }]
        const wrong = wrongCompanyLines({
            lines, billedTo: 'nvs_travels', savedBilledTo: 'nvs_travel_solutions',
            savedVehicles: new Map([['l1', 'PVT1']]), companyOf,
        })
        expect([...wrong]).toEqual(['a'])
    })
})
