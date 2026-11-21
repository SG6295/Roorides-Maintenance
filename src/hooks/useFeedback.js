import { createContext, useContext } from 'react'

/**
 * In-app messages and "are you sure?" popups (MAIN-144). The app used the browser's own
 * alert()/confirm()/prompt(), which freeze the whole page — and automated testing on
 * staging — until someone clicks OK. Don't reintroduce them.
 *
 *   const toast = useToast()
 *   toast.success('Ticket submitted successfully!')   // fades on its own
 *   toast.error('Failed to save: ' + e.message)        // stays until closed
 *
 *   const confirm = useConfirm()
 *   if (!(await confirm({ title: 'Reopen job card?', message: '…', confirmLabel: 'Reopen' }))) return
 *
 * With `reason: { label }` the popup also asks for a reason and resolves to the trimmed
 * text ('' when left blank, unless `required`), or null when cancelled.
 *
 * The provider and its UI are FeedbackProvider in src/components/shared/Feedback.jsx,
 * mounted once in App.jsx.
 *
 * Form checks don't belong here — show them next to their field.
 */

export const FeedbackContext = createContext(null)

function useFeedback() {
    const ctx = useContext(FeedbackContext)
    if (!ctx) throw new Error('useToast/useConfirm must be used inside <FeedbackProvider>')
    return ctx
}

export const useToast = () => useFeedback().toast
export const useConfirm = () => useFeedback().confirm
