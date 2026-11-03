import { useState } from 'react'
import LedgerModal, { PrimaryButton, SecondaryButton } from './LedgerModal'
import { useCancelSupplierPayment } from '../../hooks/useSupplierLedger'

/**
 * Cancels a supplier payment whose transaction failed and was refunded (MAIN-119). The
 * payment stays on the statement, struck through, and drops out of every total.
 */
export default function CancelPaymentModal({ payment, description, onClose }) {
    const cancel = useCancelSupplierPayment()
    const [reason, setReason] = useState('')

    return (
        <LedgerModal
            title="Cancel payment"
            subtitle={description}
            onClose={onClose}
            footer={<>
                <SecondaryButton onClick={onClose}>Keep payment</SecondaryButton>
                <PrimaryButton
                    tone="red"
                    disabled={!reason.trim() || cancel.isPending}
                    onClick={() => cancel.mutate({ paymentId: payment.line_id, reason: reason.trim() }, { onSuccess: onClose })}
                >
                    {cancel.isPending ? 'Cancelling…' : 'Cancel payment'}
                </PrimaryButton>
            </>}
        >
            <p className="text-sm text-gray-600">For a transaction that failed and was refunded. The payment is kept on the statement, marked cancelled.</p>
            <div>
                <label htmlFor="cp-reason" className="block text-xs font-medium text-gray-600 mb-1">Reason <span className="text-red-500">*</span></label>
                <textarea
                    id="cp-reason"
                    autoFocus
                    rows={3}
                    value={reason}
                    onChange={e => setReason(e.target.value)}
                    className="w-full text-sm border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-red-500"
                />
            </div>
            {cancel.error && <p className="text-sm text-red-600">{cancel.error.message}</p>}
        </LedgerModal>
    )
}
