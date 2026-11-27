/**
 * The status buttons above the Tickets table (MAIN-151; replaces the MAIN-82 accordion tests).
 *
 * MAIN-82: a status badge once counted a wider set than the list showed. The buttons now
 * show the Status column's values as the database counts them under every other filter,
 * so they narrow with the list; these tests pin how the buttons read and set that filter.
 */
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

vi.mock('../../../hooks/useServerList', () => ({
    useListFacet: () => ({
        data: [
            { value: 'Resolved', n: 57 },
            { value: 'Rejected', n: 30 },
            { value: 'Accepted', n: 18 },
        ],
    }),
}))

import StatusShortcuts from '../StatusShortcuts'

const makeList = (filters = {}) => ({
    rpc: 'get_ticket_list',
    keyBase: 'tickets',
    state: { filters, search: '', sort: 'created_at', dir: 'desc', page: 1, from: '', to: '' },
    setFilter: vi.fn(),
})

describe('StatusShortcuts', () => {
    it('shows each status count and their sum on All', () => {
        render(<StatusShortcuts list={makeList()} />)
        expect(screen.getByRole('button', { name: /^All 105$/ })).toHaveAttribute('aria-pressed', 'true')
        expect(screen.getByRole('button', { name: /^Resolved 57$/ })).toBeInTheDocument()
        expect(screen.getByRole('button', { name: /^New 0$/ })).toBeInTheDocument()
    })

    it('one click filters the Status column to that status', async () => {
        const list = makeList()
        render(<StatusShortcuts list={list} />)
        await userEvent.click(screen.getByRole('button', { name: /^Rejected/ }))
        expect(list.setFilter).toHaveBeenCalledWith('status', { values: ['Rejected'] })
    })

    it('marks the chosen status and All clears it', async () => {
        const list = makeList({ status: { values: ['Accepted'] } })
        render(<StatusShortcuts list={list} />)
        expect(screen.getByRole('button', { name: /^Accepted/ })).toHaveAttribute('aria-pressed', 'true')
        expect(screen.getByRole('button', { name: /^All/ })).toHaveAttribute('aria-pressed', 'false')
        await userEvent.click(screen.getByRole('button', { name: /^All/ }))
        expect(list.setFilter).toHaveBeenCalledWith('status', null)
    })
})
