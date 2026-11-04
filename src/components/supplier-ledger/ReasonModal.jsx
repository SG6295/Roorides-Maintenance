import { useState } from 'react'
import LedgerModal, { PrimaryButton, SecondaryButton } from './LedgerModal'

/**
 * Asks for a reason before voiding a ledger line (MAIN-119): cancelling a payment or
 * repayment, or reversing a reconciliation adjustment. The line stays on the statement,
 * struck through, and drops out of every total. `mutation` is the hook's result;
 * `onConfirm(reason)` calls it.
 */
export default function ReasonModal({ title, subtitle, intro, keepLabel, confirmLabel, mutation, onConfirm, onClose }) {
    const [reason, setReason] = useState('')

    return (
        <LedgerModal
            title={title}
            subtitle={subtitle}
            onClose={onClose}
            footer={<>
                <SecondaryButton onClick={onClose}>{keepLabel}</SecondaryButton>
                <PrimaryButton tone="red" disabled={!reason.trim() || mutation.isPending} onClick={() => onConfirm(reason.trim())}>
                    {mutation.isPending ? 'Saving…' : confirmLabel}
                </PrimaryButton>
            </>}
        >
            <p className="text-sm text-gray-600">{intro}</p>
            <div>
                <label htmlFor="reason-modal-text" className="block text-xs font-medium text-gray-600 mb-1">Reason <span className="text-red-500">*</span></label>
                <textarea
                    id="reason-modal-text"
                    autoFocus
                    rows={3}
                    value={reason}
                    onChange={e => setReason(e.target.value)}
                    className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-red-500"
                />
            </div>
            {mutation.error && <p className="text-sm text-red-600">{mutation.error.message}</p>}
        </LedgerModal>
    )
}
