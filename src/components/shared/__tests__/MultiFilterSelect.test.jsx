/**
 * Tests for MAIN-86 — the multi-site picker on Analytics.
 *
 * The SLA figures are only as right as the list this component hands up, so these pin
 * the contract the page relies on: `[]` means all, a value never appears twice, the
 * order follows `options` (stable query keys), and the reset row survives a search.
 */
import { describe, it, expect, vi } from 'vitest'
import { useState } from 'react'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import MultiFilterSelect from '../MultiFilterSelect'

const OPTIONS = [
    { value: 'AECS', label: 'AECS — AECS Magnolia Maaruti Public School — 137' },
    { value: 'AGRATA', label: 'AGRATA — Agratas Energy Storage Solutions Pvt Ltd — 215' },
    { value: 'TSAB', label: 'TSAB' },
]

function Harness({ initial = [], onChange = () => {}, options = OPTIONS, groups }) {
    const [value, setValue] = useState(initial)
    return (
        <MultiFilterSelect
            options={options}
            value={value}
            onChange={v => { setValue(v); onChange(v) }}
            placeholder="All Sites"
            noun="sites"
            groups={groups}
        />
    )
}

const trigger = () => screen.getAllByRole('button')[0]

describe('MultiFilterSelect', () => {
    it('shows the placeholder when nothing is ticked', () => {
        render(<Harness />)
        expect(trigger()).toHaveTextContent('All Sites')
    })

    it('stays open while ticking and emits values in option order', async () => {
        const onChange = vi.fn()
        render(<Harness onChange={onChange} />)
        await userEvent.click(trigger())
        await userEvent.click(screen.getByRole('menuitemcheckbox', { name: /TSAB/ }))
        await userEvent.click(screen.getByRole('menuitemcheckbox', { name: /AECS/ }))
        expect(onChange).toHaveBeenLastCalledWith(['AECS', 'TSAB'])
        expect(screen.getByRole('menuitemcheckbox', { name: /AGRATA/ })).toBeInTheDocument()
    })

    it('summarises one pick by its label and several by count', async () => {
        render(<Harness />)
        await userEvent.click(trigger())
        await userEvent.click(screen.getByRole('menuitemcheckbox', { name: /AGRATA/ }))
        expect(trigger()).toHaveTextContent('AGRATA — Agratas Energy Storage Solutions Pvt Ltd — 215')
        await userEvent.click(screen.getByRole('menuitemcheckbox', { name: /TSAB/ }))
        expect(trigger()).toHaveTextContent('2 sites')
    })

    it('unticking removes the value rather than duplicating it', async () => {
        const onChange = vi.fn()
        render(<Harness initial={['TSAB']} onChange={onChange} />)
        await userEvent.click(trigger())
        const tsab = screen.getByRole('menuitemcheckbox', { name: /TSAB/ })
        expect(tsab).toHaveAttribute('aria-checked', 'true')
        await userEvent.click(tsab)
        expect(onChange).toHaveBeenLastCalledWith([])
    })

    it('the reset row clears every tick back to [] (all sites)', async () => {
        const onChange = vi.fn()
        render(<Harness initial={['AECS', 'TSAB']} onChange={onChange} />)
        await userEvent.click(trigger())
        await userEvent.click(screen.getByRole('button', { name: 'All Sites' }))
        expect(onChange).toHaveBeenLastCalledWith([])
        expect(trigger()).toHaveTextContent('All Sites')
    })

    it('keeps the reset row visible while a search hides every option', async () => {
        const many = Array.from({ length: 12 }, (_, i) => ({ value: `S${i}`, label: `Site ${i}` }))
        render(<Harness options={many} initial={['S1']} />)
        await userEvent.click(trigger())
        await userEvent.type(screen.getByPlaceholderText('Search...'), 'zzz')
        expect(screen.getByText('No matches.')).toBeInTheDocument()
        expect(screen.getByRole('button', { name: 'All Sites' })).toBeInTheDocument()
    })

    describe('workshop groups (MAIN-131)', () => {
        const GROUPS = [
            { key: 'b', label: 'Bannerghatta', values: ['AECS', 'TSAB', 'GONE'] },
            { key: 'm', label: 'Mahadevpura', values: [] },
        ]
        const group = name => screen.getByRole('menuitemcheckbox', { name: new RegExp(`^${name}`) })

        it('ticking a workshop ticks its sites, ignoring values that are not options', async () => {
            const onChange = vi.fn()
            render(<Harness groups={GROUPS} onChange={onChange} />)
            await userEvent.click(trigger())
            expect(group('Bannerghatta')).toHaveTextContent('2 sites')
            await userEvent.click(group('Bannerghatta'))
            expect(onChange).toHaveBeenLastCalledWith(['AECS', 'TSAB'])
            expect(trigger()).toHaveTextContent('Bannerghatta')
        })

        it('adds to the existing selection and unticks only its own sites', async () => {
            const onChange = vi.fn()
            render(<Harness groups={GROUPS} initial={['AGRATA']} onChange={onChange} />)
            await userEvent.click(trigger())
            await userEvent.click(group('Bannerghatta'))
            expect(onChange).toHaveBeenLastCalledWith(['AECS', 'AGRATA', 'TSAB'])
            expect(trigger()).toHaveTextContent('3 sites')
            await userEvent.click(group('Bannerghatta'))
            expect(onChange).toHaveBeenLastCalledWith(['AGRATA'])
        })

        it('shows partly ticked when some of its sites are ticked, and completes them on click', async () => {
            const onChange = vi.fn()
            render(<Harness groups={GROUPS} initial={['AECS']} onChange={onChange} />)
            await userEvent.click(trigger())
            expect(group('Bannerghatta')).toHaveAttribute('aria-checked', 'mixed')
            await userEvent.click(group('Bannerghatta'))
            expect(onChange).toHaveBeenLastCalledWith(['AECS', 'TSAB'])
        })

        it('greys out a workshop with no sites', async () => {
            render(<Harness groups={GROUPS} />)
            await userEvent.click(trigger())
            expect(group('Mahadevpura')).toBeDisabled()
            expect(group('Mahadevpura')).toHaveTextContent('no sites')
        })

        it('keeps workshop rows visible while a search filters the sites', async () => {
            const many = Array.from({ length: 12 }, (_, i) => ({ value: `S${i}`, label: `Site ${i}` }))
            render(<Harness options={many} groups={[{ key: 'b', label: 'Bannerghatta', values: ['S1'] }]} />)
            await userEvent.click(trigger())
            await userEvent.type(screen.getByPlaceholderText('Search...'), 'zzz')
            expect(group('Bannerghatta')).toBeInTheDocument()
        })
    })
})
