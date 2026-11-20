/**
 * MAIN-142 — Outsource Invoices became Invoices at /invoices. An old link still opens
 * it, with the filters its query string carries.
 */
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom'

vi.mock('../../lib/supabase', () => ({ supabase: {} }))

import { LegacyInvoicesRedirect } from '../OutsourceInvoices'

function Landed() {
    const { pathname, search } = useLocation()
    return <p>{pathname + search}</p>
}

describe('LegacyInvoicesRedirect', () => {
    it('forwards /outsource-invoices to /invoices with its filters', () => {
        render(
            <MemoryRouter initialEntries={['/outsource-invoices?fs=New&fs=Hold&pb=PCN&p=2']}>
                <Routes>
                    <Route path="/outsource-invoices" element={<LegacyInvoicesRedirect />} />
                    <Route path="/invoices" element={<Landed />} />
                </Routes>
            </MemoryRouter>
        )
        expect(screen.getByText('/invoices?fs=New&fs=Hold&pb=PCN&p=2')).toBeInTheDocument()
    })
})
