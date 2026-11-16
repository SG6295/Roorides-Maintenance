/**
 * Regression tests for MAIN-134.
 *
 * The bug: SLABadge counted down to final_sla_end_date for every status but New, so a
 * ticket finished on time read as overdue — a red countdown counting up — once its
 * deadline passed.
 *
 * The fix: only an unfinished ticket counts down. Resolved and Closed show the stored
 * verdict; Rejected shows nothing.
 */
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import TicketCard from '../TicketCard'

// The deadline has passed by now, which is exactly when the bug showed.
const NOW = new Date('2026-11-03T08:00:00.000Z')

const makeTicket = (overrides) => ({
    id: 'ticket-1',
    ticket_number: 3479,
    status: 'Resolved',
    site: 'TSAB',
    vehicle_number: 'KA51AH1234',
    initial_remarks: 'AdBlue',
    supervisor_name: 'Chandra',
    created_at: '2026-10-27T03:25:00.000Z',
    acceptance_sla_end_date: null,
    final_sla_end_date: '2026-11-02T08:03:02.000Z',
    overall_sla_status: 'Adhered',
    ...overrides,
})

const renderCard = (ticket) =>
    render(
        <MemoryRouter>
            <TicketCard ticket={ticket} currentDate={NOW} />
        </MemoryRouter>,
    )

// SLATimer labels its units d / h / m.
const countdownShown = () => screen.queryByText('d') !== null

describe('TicketCard SLA badge (MAIN-134)', () => {
    it.each(['Resolved', 'Closed'])('shows the verdict, not a countdown, on a %s ticket', (status) => {
        renderCard(makeTicket({ status }))

        expect(screen.getByText('SLA Adhered')).toBeInTheDocument()
        expect(countdownShown()).toBe(false)
    })

    it('shows Violated when the stored verdict is Violated', () => {
        renderCard(makeTicket({ overall_sla_status: 'Violated' }))

        expect(screen.getByText('SLA Violated')).toBeInTheDocument()
    })

    it.each(['Pending', 'NA'])('shows nothing on a finished ticket whose verdict is %s', (verdict) => {
        renderCard(makeTicket({ overall_sla_status: verdict }))

        expect(screen.queryByText(/^SLA /)).not.toBeInTheDocument()
        expect(countdownShown()).toBe(false)
    })

    it('shows nothing on a Rejected ticket', () => {
        renderCard(makeTicket({ status: 'Rejected', overall_sla_status: 'Violated' }))

        expect(screen.queryByText(/^SLA /)).not.toBeInTheDocument()
        expect(countdownShown()).toBe(false)
    })

    it('still counts down on an unfinished ticket', () => {
        renderCard(makeTicket({ status: 'Work In Progress', overall_sla_status: 'Pending' }))

        expect(countdownShown()).toBe(true)
        expect(screen.queryByText(/^SLA /)).not.toBeInTheDocument()
    })
})
