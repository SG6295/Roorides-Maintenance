/**
 * Regression tests for MAIN-82.
 *
 * The bug: Tickets.jsx passed StatusAccordion two different sets — rows from
 * `filteredTickets` (date + site + vehicle) and badge numbers from a `statusCounts`
 * memo that applied the date range only. Selecting a site narrowed the rows and the
 * header's "N tickets found" but left every stage badge showing the month-wide total.
 *
 * The fix removed the second set: the badge is now the length of the list the rows are
 * drawn from. These tests pin that — the badge counts only the tickets handed in, and
 * it agrees with the cards actually rendered beneath it.
 */
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import StatusAccordion from '../StatusAccordion'

let nextId = 0

const makeTicket = (status, site) => {
    nextId += 1
    return {
        id: `ticket-${nextId}`,
        ticket_number: 1000 + nextId,
        status,
        site,
        vehicle_number: `KA51AH${1000 + nextId}`,
        initial_remarks: 'Adblue',
        supervisor_name: 'Nagendra',
        created_at: '2026-09-30T11:26:00.000Z',
        acceptance_sla_end_date: null,
        final_sla_end_date: null,
    }
}

const renderAccordion = (tickets) =>
    render(
        <MemoryRouter>
            <StatusAccordion tickets={tickets} currentDate={new Date('2026-10-01T07:26:00.000Z')} />
        </MemoryRouter>
    )

// The stage header is a button containing the label and the count badge, so its text
// reads "New2". Strip the label to get at the number the user sees.
const badgeCount = (label) => {
    const header = screen.getByRole('button', { name: new RegExp(`^${label}\\b`) })
    return Number(header.textContent.replace(label, '').trim())
}

describe('StatusAccordion badge counts', () => {
    it('counts only the tickets it was given, not some wider set', () => {
        // What a site filter leaves behind: one school's slice of a much larger month.
        renderAccordion([
            makeTicket('New', 'TSAB'),
            makeTicket('New', 'TSAB'),
            makeTicket('Resolved', 'TSAB'),
        ])

        expect(badgeCount('New')).toBe(2)
        expect(badgeCount('Resolved')).toBe(1)
        expect(badgeCount('Accepted')).toBe(0)
        expect(badgeCount('Work In Progress')).toBe(0)
        expect(badgeCount('Closed')).toBe(0)
        expect(badgeCount('Rejected')).toBe(0)
    })

    it('agrees with the number of cards rendered in the open stage', () => {
        renderAccordion([
            makeTicket('New', 'TSAB'),
            makeTicket('New', 'TSAB'),
            makeTicket('New', 'TSAB'),
            makeTicket('Rejected', 'TSAB'),
        ])

        // 'New' is the only stage open by default, so every rendered card belongs to it.
        expect(screen.getAllByRole('link')).toHaveLength(badgeCount('New'))
    })

    it('still agrees once a second stage is expanded', async () => {
        const user = userEvent.setup()
        renderAccordion([
            makeTicket('New', 'TSAB'),
            makeTicket('Resolved', 'TSAB'),
            makeTicket('Resolved', 'TSAB'),
        ])

        await user.click(screen.getByRole('button', { name: /^Resolved\b/ }))

        expect(screen.getAllByRole('link')).toHaveLength(
            badgeCount('New') + badgeCount('Resolved')
        )
    })

    it('narrows the badges when the filtered list narrows', () => {
        const samhita = [makeTicket('New', 'TSAB'), makeTicket('New', 'TSAB')]
        const other = [makeTicket('New', 'AGRATA')]

        const { rerender } = renderAccordion([...samhita, ...other])
        expect(badgeCount('New')).toBe(3)

        // The parent re-filters to a single site and re-renders with the smaller list.
        rerender(
            <MemoryRouter>
                <StatusAccordion tickets={samhita} currentDate={new Date('2026-10-01T07:26:00.000Z')} />
            </MemoryRouter>
        )
        expect(badgeCount('New')).toBe(2)
    })
})
