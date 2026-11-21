/**
 * Tests for MAIN-146 — the eye button on password boxes: hidden by default, and the
 * button toggles between showing and hiding without touching the value.
 */
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import PasswordInput from '../PasswordInput'

describe('PasswordInput', () => {
    it('starts hidden and toggles with the eye button', async () => {
        render(<PasswordInput aria-label="Password" defaultValue="Mango-River-47" />)
        const input = screen.getByLabelText('Password')
        expect(input).toHaveAttribute('type', 'password')

        await userEvent.click(screen.getByRole('button', { name: 'Show password' }))
        expect(input).toHaveAttribute('type', 'text')
        expect(input).toHaveValue('Mango-River-47')

        await userEvent.click(screen.getByRole('button', { name: 'Hide password' }))
        expect(input).toHaveAttribute('type', 'password')
    })

    it('is a button that never submits its form', () => {
        render(<form><PasswordInput aria-label="Password" /></form>)
        expect(screen.getByRole('button', { name: 'Show password' })).toHaveAttribute('type', 'button')
    })
})
