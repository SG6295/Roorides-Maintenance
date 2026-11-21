/**
 * Tests for MAIN-144 — the in-app messages and confirm popup that replaced the browser's
 * alert()/confirm()/prompt(). These pin what every caller relies on: a success fades, an
 * error stays until closed, and confirm resolves true/false (or the reason / null).
 */
import { describe, it, expect, vi, afterEach } from 'vitest'
import { useState } from 'react'
import { render, screen, act } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { FeedbackProvider } from '../Feedback'
import { useToast, useConfirm } from '../../../hooks/useFeedback'

function Harness({ options, onResult }) {
    const toast = useToast()
    const confirm = useConfirm()
    const [result, setResult] = useState('none')
    return (
        <>
            <button onClick={() => toast.success('Saved!')}>success</button>
            <button onClick={() => toast.error('Failed to save: boom')}>error</button>
            <button onClick={async () => {
                const r = await confirm(options)
                setResult(String(r))
                onResult?.(r)
            }}>ask</button>
            <p data-testid="result">{result}</p>
        </>
    )
}

const renderHarness = (props = {}) => render(
    <FeedbackProvider>
        <Harness options={{ title: 'Reopen this Job Card?', message: 'Parts can be updated.', confirmLabel: 'Reopen' }} {...props} />
    </FeedbackProvider>,
)

afterEach(() => vi.useRealTimers())

describe('toasts', () => {
    it('fades a success message on its own', () => {
        vi.useFakeTimers()
        renderHarness()
        act(() => screen.getByText('success').click())
        expect(screen.getByRole('status')).toHaveTextContent('Saved!')
        act(() => vi.advanceTimersByTime(4100))
        expect(screen.queryByText('Saved!')).not.toBeInTheDocument()
    })

    it('keeps an error until it is closed', async () => {
        vi.useFakeTimers()
        renderHarness()
        act(() => screen.getByText('error').click())
        act(() => vi.advanceTimersByTime(60000))
        expect(screen.getByRole('alert')).toHaveTextContent('Failed to save: boom')
        vi.useRealTimers()
        await userEvent.click(screen.getByRole('button', { name: 'Close' }))
        expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    })
})

describe('confirm', () => {
    it('resolves true on Confirm', async () => {
        renderHarness()
        await userEvent.click(screen.getByText('ask'))
        expect(screen.getByRole('alertdialog')).toHaveTextContent('Parts can be updated.')
        await userEvent.click(screen.getByRole('button', { name: 'Reopen' }))
        expect(screen.getByTestId('result')).toHaveTextContent('true')
        expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    })

    it('resolves false on Cancel and on Esc', async () => {
        renderHarness()
        await userEvent.click(screen.getByText('ask'))
        await userEvent.click(screen.getByRole('button', { name: 'Cancel' }))
        expect(screen.getByTestId('result')).toHaveTextContent('false')

        await userEvent.click(screen.getByText('ask'))
        await userEvent.keyboard('{Escape}')
        expect(screen.getByTestId('result')).toHaveTextContent('false')
        expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
    })

    it('with a reason box, resolves the trimmed reason, or null when cancelled', async () => {
        const onResult = vi.fn()
        renderHarness({
            options: { title: 'Cancel this count?', reason: { label: 'Why?' }, confirmLabel: 'Cancel count', cancelLabel: 'Keep counting' },
            onResult,
        })
        await userEvent.click(screen.getByText('ask'))
        await userEvent.type(screen.getByLabelText(/Why\?/), '  miscounted  ')
        await userEvent.click(screen.getByRole('button', { name: 'Cancel count' }))
        expect(onResult).toHaveBeenLastCalledWith('miscounted')

        await userEvent.click(screen.getByText('ask'))
        await userEvent.click(screen.getByRole('button', { name: 'Cancel count' }))
        expect(onResult).toHaveBeenLastCalledWith('')

        await userEvent.click(screen.getByText('ask'))
        await userEvent.click(screen.getByRole('button', { name: 'Keep counting' }))
        expect(onResult).toHaveBeenLastCalledWith(null)
    })

    it('a required reason keeps Confirm disabled until one is typed', async () => {
        renderHarness({ options: { title: 'Why?', reason: { label: 'Reason', required: true }, confirmLabel: 'Go' } })
        await userEvent.click(screen.getByText('ask'))
        expect(screen.getByRole('button', { name: 'Go' })).toBeDisabled()
        await userEvent.type(screen.getByLabelText(/Reason/), 'x')
        expect(screen.getByRole('button', { name: 'Go' })).toBeEnabled()
    })
})
