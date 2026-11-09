/**
 * MAIN-123: one mismatch can be explained by several lines, which must add up before the
 * audit can complete.
 */
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

const saveReasons = vi.fn().mockResolvedValue(null)

vi.mock('../../../../hooks/useStockAudits', () => ({
    AUDIT_REASONS: [
        { value: 'missing', label: 'Missing' },
        { value: 'stolen', label: 'Stolen' },
        { value: 'damaged', label: 'Damaged' },
        { value: 'found', label: 'Found / excess' },
        { value: 'other', label: 'Other' },
    ],
    useStockAuditMovements: () => ({ data: {} }),
    useSetStockAuditReasons: () => ({ mutateAsync: saveReasons, isPending: false }),
    useCompleteStockAudit: () => ({ mutateAsync: vi.fn(), isPending: false }),
}))

import AuditReviewTable from '../AuditReviewTable'

const item = over => ({
    id: 'item-1',
    part_id: 'part-1',
    part_name_snapshot: 'Alternator',
    part_number_snapshot: null,
    unit_snapshot: 'pcs',
    system_qty: 20,
    counted_qty: 10,
    variance: -10,
    was_found_row: false,
    part: { default_exclude_from_scrap: false },
    reason_lines: [],
    ...over,
})

const savedLine = (quantity, reason, sort_order = 0, notes = null) => ({ id: `l${sort_order}`, quantity, reason, notes, sort_order })

const renderTable = items => render(<AuditReviewTable audit={{ id: 'audit-1' }} items={items} />)
const completeButton = () => screen.getByRole('button', { name: /Accept losses/ })
const quantities = () => screen.getAllByLabelText('Quantity')

describe('AuditReviewTable reason lines', () => {
    beforeEach(() => saveReasons.mockClear())

    it('starts with one line for the whole difference and cannot complete', () => {
        renderTable([item()])
        expect(quantities()).toHaveLength(1)
        expect(quantities()[0]).toHaveValue(10)
        expect(completeButton()).toBeDisabled()
    })

    it('can complete once saved lines add up', () => {
        renderTable([item({ reason_lines: [savedLine(4, 'missing'), savedLine(6, 'stolen', 1)] })])
        expect(completeButton()).toBeEnabled()
    })

    it('shows what is left, offers it on a new line and saves only finished lines', async () => {
        const user = userEvent.setup()
        renderTable([item({ reason_lines: [savedLine(10, 'missing')] })])

        await user.clear(quantities()[0])
        await user.type(quantities()[0], '4')
        expect(screen.getByText('6 still to explain')).toBeInTheDocument()
        expect(completeButton()).toBeDisabled()

        await user.click(screen.getByRole('button', { name: /Add another reason/ }))
        expect(quantities()[1]).toHaveValue(6)

        await user.click(screen.getByRole('button', { name: /Save progress/ }))
        expect(saveReasons).toHaveBeenCalledWith({
            auditId: 'audit-1',
            items: [{ part_id: 'part-1', lines: [{ quantity: 4, reason: 'missing', notes: null }] }],
        })
    })

    it('warns when the lines cover more than the difference', async () => {
        const user = userEvent.setup()
        renderTable([item({ reason_lines: [savedLine(10, 'missing')] })])

        await user.clear(quantities()[0])
        await user.type(quantities()[0], '12')
        expect(screen.getByText('2 more than the difference')).toBeInTheDocument()
        expect(completeButton()).toBeDisabled()
    })

    it('says whether a damaged line reaches scrap', () => {
        const { unmount } = renderTable([item({ reason_lines: [savedLine(10, 'damaged')] })])
        expect(screen.getByText(/Will go to scrap/)).toBeInTheDocument()
        unmount()

        renderTable([item({
            part: { default_exclude_from_scrap: true },
            reason_lines: [savedLine(10, 'damaged')],
        })])
        expect(screen.getByText(/Will not go to scrap/)).toBeInTheDocument()
    })
})
