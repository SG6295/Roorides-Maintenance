/* global process */
/**
 * Tests for the MAIN-84 ticket export.
 *
 * The time column is the one that can go quietly wrong: `tickets.created_at` is naive UTC,
 * and SheetJS's own Date conversion lands ten seconds late in IST. So the sheet is written
 * and read back, the way Excel would see it.
 */
import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest'
import * as XLSX from 'xlsx'

// ticketExport imports the app's Supabase client, which throws at load time without the
// .env.local settings — present locally, absent in CI. These tests never touch it.
vi.mock('../../lib/supabase', () => ({ supabase: {} }))

import { buildTicketExportRows, buildTicketWorksheet } from '../ticketExport'

let originalTz

beforeAll(() => {
    originalTz = process.env.TZ
    process.env.TZ = 'Asia/Kolkata'
})

afterAll(() => {
    process.env.TZ = originalTz
})

const ticket = (overrides = {}) => ({
    ticket_number: 4352,
    // 00:15 IST on 1 Sep, stored as naive UTC the way Postgres returns it.
    created_at: '2026-08-31 18:45:00',
    created_by_user_id: 'user-1',
    site: 'SJR',
    vehicle_number: 'KA51D3687',
    status: 'Work In Progress',
    ...overrides,
})

const EMAILS = { 'user-1': 'nvsts.maintenance1@gmail.com' }

function roundTrip(rows) {
    const wb = XLSX.utils.book_new()
    XLSX.utils.book_append_sheet(wb, buildTicketWorksheet(rows), 'Tickets')
    const back = XLSX.read(XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' }), { type: 'buffer' })
    return back.Sheets.Tickets
}

describe('buildTicketExportRows', () => {
    it('produces the six columns in the specified order', () => {
        const [row] = buildTicketExportRows([ticket()], EMAILS)
        expect(Object.keys(row)).toEqual([
            'Ticket ID',
            'Ticket Creation Time',
            'Email Address of Creator',
            'Site',
            'Vehicle Number',
            'Status',
        ])
    })

    it('keeps the ticket ID a number and maps each field', () => {
        const [row] = buildTicketExportRows([ticket()], EMAILS)
        expect(row['Ticket ID']).toBe(4352)
        expect(row['Email Address of Creator']).toBe('nvsts.maintenance1@gmail.com')
        expect(row['Site']).toBe('SJR')
        expect(row['Vehicle Number']).toBe('KA51D3687')
        expect(row['Status']).toBe('Work In Progress')
    })

    it('leaves the email blank when the creator has none on record', () => {
        const [row] = buildTicketExportRows([ticket({ created_by_user_id: 'unknown' })], EMAILS)
        expect(row['Email Address of Creator']).toBe('')
    })

    it('keeps the rows in the order given', () => {
        const rows = buildTicketExportRows([ticket({ ticket_number: 2 }), ticket({ ticket_number: 1 })], EMAILS)
        expect(rows.map(r => r['Ticket ID'])).toEqual([2, 1])
    })
})

describe('buildTicketWorksheet', () => {
    it('stores the creation time as an exact IST date-time, not as text', () => {
        const sheet = roundTrip(buildTicketExportRows([ticket()], EMAILS))
        const cell = sheet.B2

        expect(cell.t).toBe('n')
        expect(cell.w).toBe('01-Sep-2026 00:15')
        // Exactly 00:15:00 — SheetJS's own Date conversion gives 00:15:10 in IST.
        const seconds = Math.round((cell.v % 1) * 86_400)
        expect(seconds).toBe(15 * 60)
    })

    it('stores the ticket ID as a number', () => {
        const sheet = roundTrip(buildTicketExportRows([ticket()], EMAILS))
        expect(sheet.A2.t).toBe('n')
        expect(sheet.A2.v).toBe(4352)
    })

    it('writes a header row for the columns', () => {
        const sheet = roundTrip(buildTicketExportRows([ticket()], EMAILS))
        expect(['A1', 'B1', 'C1', 'D1', 'E1', 'F1'].map(c => sheet[c].v)).toEqual([
            'Ticket ID',
            'Ticket Creation Time',
            'Email Address of Creator',
            'Site',
            'Vehicle Number',
            'Status',
        ])
    })
})
