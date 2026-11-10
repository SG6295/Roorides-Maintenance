import { useState } from 'react'
import { createPortal } from 'react-dom'
import SearchableSelect from '../shared/SearchableSelect'
import QuickAddSupplierModal from './QuickAddSupplierModal'
import { useApprovedSuppliers } from '../../hooks/useSuppliers'

const QUICK_ADD_SENTINEL = '__QUICK_ADD__'

/**
 * Approved suppliers, with a pinned "+ Add supplier…" that opens Quick Add with the
 * typed name filled in; the added supplier is approved and picked straight away.
 *
 * `current` ({ id, name }) keeps an invoice's existing supplier listed when it is
 * no longer approved, so an edit still shows who it was recorded against.
 *
 * Quick Add is a form of its own and the picker sits inside the invoice form, so it
 * is portalled out of the DOM and its submit is stopped before it bubbles up the
 * React tree, where it would otherwise also submit the invoice.
 */
export default function SupplierPicker({ value, onChange, current = null, error = null, disabled = false }) {
    const { data: suppliers = [] } = useApprovedSuppliers()
    // The name typed before choosing "+ Add supplier", or null while Quick Add is closed.
    const [quickAddName, setQuickAddName] = useState(null)

    const options = suppliers.map(sp => ({ value: sp.id, label: sp.entity_name }))
    if (current?.id && !options.some(o => o.value === current.id)) {
        options.unshift({ value: current.id, label: current.name })
    }

    function choose(picked, typed) {
        if (picked === QUICK_ADD_SENTINEL) {
            setQuickAddName(typed ?? '')
        } else {
            onChange(picked)
        }
    }

    return (
        <>
            <SearchableSelect
                value={value}
                onChange={choose}
                options={options}
                placeholder="Search suppliers…"
                showAllOnFocus={true}
                pinnedOption={{ value: QUICK_ADD_SENTINEL, label: '+ Add supplier…' }}
                error={error}
                disabled={disabled}
            />
            {quickAddName !== null && createPortal(
                <div onSubmit={e => e.stopPropagation()}>
                    <QuickAddSupplierModal
                        isOpen
                        initialName={quickAddName}
                        onClose={() => setQuickAddName(null)}
                        onSuccess={supplier => onChange(supplier.id)}
                    />
                </div>,
                document.body
            )}
        </>
    )
}
