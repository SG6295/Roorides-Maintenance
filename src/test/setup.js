// Vitest setup — runs before every test file.
// Adds jest-dom matchers (toBeInTheDocument, toBeDisabled, …) and clears the
// DOM between tests so React Testing Library renders don't leak across cases.
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// jsdom implements neither of these, and Headless UI (CustomSelect, SearchableSelect)
// reaches for them when a Listbox opens or closes. Without the stubs the component
// still behaves correctly but throws an uncaught error that would hide real failures.
if (!globalThis.ResizeObserver) {
    globalThis.ResizeObserver = class {
        observe() {}
        unobserve() {}
        disconnect() {}
    }
}

if (!globalThis.IntersectionObserver) {
    globalThis.IntersectionObserver = class {
        observe() {}
        unobserve() {}
        disconnect() {}
        takeRecords() { return [] }
    }
}

afterEach(() => {
    cleanup()
})
