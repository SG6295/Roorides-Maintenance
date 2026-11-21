/**
 * Tests for MAIN-145 — the GST dropdown on Record / Edit Purchase lines. CustomSelect
 * treats a value of 0 as "nothing selected", so the purchase forms hand it string values
 * and turn the pick back into a number. These pin that "None" shows and saves as 0.
 */
import { describe, it, expect, vi } from 'vitest'
import { useState } from 'react'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import CustomSelect from '../CustomSelect'

const GST_RATES = [
    { label: 'None', value: 0 },
    { label: '5%', value: 5 },
    { label: '18%', value: 18 },
]
const GST_OPTIONS = GST_RATES.map(r => ({ label: r.label, value: String(r.value) }))

function GstHarness({ initial, onSave }) {
    const [rate, setRate] = useState(initial)
    return (
        <CustomSelect
            compact
            value={String(rate)}
            onChange={v => { setRate(Number(v)); onSave(Number(v)) }}
            options={GST_OPTIONS}
        />
    )
}

describe('CustomSelect — purchase GST', () => {
    it('shows None for a saved rate of 0', () => {
        render(<GstHarness initial={0} onSave={() => {}} />)
        expect(screen.getByRole('button')).toHaveTextContent('None')
    })

    it('saves the rate as a number, None included', async () => {
        const onSave = vi.fn()
        render(<GstHarness initial={0} onSave={onSave} />)
        await userEvent.click(screen.getByRole('button'))
        await userEvent.click(screen.getByRole('option', { name: '18%' }))
        expect(onSave).toHaveBeenLastCalledWith(18)
        expect(screen.getByRole('button')).toHaveTextContent('18%')

        await userEvent.click(screen.getByRole('button'))
        await userEvent.click(screen.getByRole('option', { name: 'None' }))
        expect(onSave).toHaveBeenLastCalledWith(0)
    })
})
