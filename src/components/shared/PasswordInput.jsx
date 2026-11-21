import { useState } from 'react'
import { EyeIcon, EyeSlashIcon } from '@heroicons/react/24/outline'

/**
 * A password box with a show/hide eye button at its right end, hidden by default
 * (MAIN-146) — the same icons as Add User / Edit User. Every other prop goes to the
 * <input>, so each screen keeps its own styling; `wrapperClassName` styles the wrapper.
 */
export default function PasswordInput({ className = '', wrapperClassName = '', ...props }) {
    const [visible, setVisible] = useState(false)
    const Icon = visible ? EyeSlashIcon : EyeIcon

    return (
        <div className={`relative ${wrapperClassName}`}>
            <input {...props} type={visible ? 'text' : 'password'} className={`${className} pr-10`} />
            <button
                type="button"
                onClick={() => setVisible(v => !v)}
                aria-label={visible ? 'Hide password' : 'Show password'}
                className="absolute inset-y-0 right-0 z-20 flex items-center px-3 text-gray-400 hover:text-gray-600"
            >
                <Icon className="h-5 w-5" />
            </button>
        </div>
    )
}
