
import { useState, Fragment } from 'react'
import { Dialog, Transition } from '@headlessui/react'
import { XMarkIcon, EyeIcon, EyeSlashIcon, ArrowPathIcon, ClipboardDocumentIcon, CheckIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import { supabase } from '../../lib/supabase'
import { useSites } from '../../hooks/useSites'

function SiteSelect({ value, onChange }) {
    const { data: sites, isLoading } = useSites()

    if (isLoading) return <div className="text-sm text-gray-500">Loading sites...</div>

    const siteOptions = sites?.map(site => ({
        id: site.id,
        name: site.name,
        value: site.name // Changed to name based on SiteFilter usage
    })) || []

    return (
        <CustomSelect
            value={value}
            onChange={onChange}
            options={siteOptions}
            placeholder="Select Site"
        />
    )
}

export default function AddUserModal({ isOpen, onClose, onSuccess }) {
    const [formData, setFormData] = useState({
        name: '',
        email: '',
        role: 'supervisor',
        site: '',
        employee_id: '',
        contact: '',
        password: generatePassword()
    })
    const [loading, setLoading] = useState(false)
    const [showPassword, setShowPassword] = useState(true)
    const [isCopied, setIsCopied] = useState(false)
    const [error, setError] = useState(null)

    function generatePassword() {
        return Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-2).toUpperCase();
    }

    const copyToClipboard = () => {
        navigator.clipboard.writeText(formData.password)
        setIsCopied(true)
        setTimeout(() => setIsCopied(false), 2000)
    }

    const handleSubmit = async (e) => {
        e.preventDefault()
        setLoading(true)
        setError(null)

        try {
            const { data, error } = await supabase.functions.invoke('create-user', {
                body: formData
            })

            if (error) throw error

            // If the function returns a custom error message
            if (data?.error) throw new Error(data.error)

            onSuccess()
            onClose()
            // Reset form
            setFormData({
                name: '',
                email: '',
                role: 'supervisor',
                site: '',
                employee_id: '',
                contact: '',
                password: generatePassword()
            })
            alert(`User created! Credentials:\nEmail: ${formData.email}\nPassword: ${formData.password}`)

        } catch (err) {
            console.error('Error creating user:', err)
            setError(err.message || 'Failed to create user')
        } finally {
            setLoading(false)
        }
    }

    // Pre-defined sites (In real app, fetch from DB)
    const SITES = [
        'Depot 1', 'Depot 2', 'Workshop A', 'Site B', 'Head Office'
    ]

    return (
        <Transition appear show={isOpen} as={Fragment}>
            <Dialog as="div" className="relative z-50" onClose={onClose}>
                <Transition.Child
                    as={Fragment}
                    enter="ease-out duration-300"
                    enterFrom="opacity-0"
                    enterTo="opacity-100"
                    leave="ease-in duration-200"
                    leaveFrom="opacity-100"
                    leaveTo="opacity-0"
                >
                    <div className="fixed inset-0 bg-black bg-opacity-25" />
                </Transition.Child>

                <div className="fixed inset-0 overflow-y-auto">
                    <div className="flex min-h-full items-center justify-center p-4 text-center">
                        <Transition.Child
                            as={Fragment}
                            enter="ease-out duration-300"
                            enterFrom="opacity-0 scale-95"
                            enterTo="opacity-100 scale-100"
                            leave="ease-in duration-200"
                            leaveFrom="opacity-100 scale-100"
                            leaveTo="opacity-0 scale-95"
                        >
                            <Dialog.Panel className="w-full max-w-md transform overflow-hidden rounded-2xl bg-white p-6 text-left align-middle shadow-xl transition-all">
                                <div className="flex justify-between items-center mb-4">
                                    <Dialog.Title as="h3" className="text-lg font-medium leading-6 text-gray-900">
                                        Add New User
                                    </Dialog.Title>
                                    <button onClick={onClose} className="text-gray-400 hover:text-gray-500">
                                        <XMarkIcon className="h-6 w-6" />
                                    </button>
                                </div>

                                <form onSubmit={handleSubmit} className="space-y-4">
                                    {error && (
                                        <div className="bg-red-50 text-red-600 p-3 rounded-lg text-sm">
                                            {error}
                                        </div>
                                    )}

                                    <div>
                                        <label className="block text-sm font-medium text-gray-700 mb-2">Full Name</label>
                                        <input
                                            type="text"
                                            required
                                            className="block w-full rounded-lg border-gray-300 py-3 px-4 text-left shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                                            placeholder="e.g. John Doe"
                                            value={formData.name}
                                            onChange={e => setFormData({ ...formData, name: e.target.value })}
                                        />
                                    </div>

                                    <div>
                                        <label className="block text-sm font-medium text-gray-700 mb-2">Email</label>
                                        <input
                                            type="email"
                                            required
                                            className="block w-full rounded-lg border-gray-300 py-3 px-4 text-left shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                                            placeholder="e.g. john@example.com"
                                            value={formData.email}
                                            onChange={e => setFormData({ ...formData, email: e.target.value })}
                                        />
                                    </div>

                                    <div className="grid grid-cols-2 gap-4">
                                        <div>
                                            <CustomSelect
                                                label="Role"
                                                value={formData.role}
                                                onChange={val => setFormData({ ...formData, role: val })}
                                                options={[
                                                    { id: 'supervisor', name: 'Supervisor', value: 'supervisor' },
                                                    { id: 'maintenance_exec', name: 'Maintenance Exec', value: 'maintenance_exec' },
                                                    { id: 'mechanic', name: 'Mechanic', value: 'mechanic' },
                                                    { id: 'finance', name: 'Finance', value: 'finance' }
                                                ]}
                                            />
                                        </div>
                                        <div>
                                            <label className="block text-sm font-medium text-gray-700 mb-2">Employee ID</label>
                                            <input
                                                type="text"
                                                className="block w-full rounded-lg border-gray-300 py-3 px-4 text-left shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                                                placeholder="e.g. EMP-001"
                                                value={formData.employee_id}
                                                onChange={e => setFormData({ ...formData, employee_id: e.target.value })}
                                            />
                                        </div>
                                    </div>

                                    {formData.role === 'supervisor' && (
                                        <div>
                                            <label className="block text-sm font-medium text-gray-700 mb-2">Assigned Site</label>
                                            <SiteSelect
                                                value={formData.site}
                                                onChange={val => setFormData({ ...formData, site: val })}
                                            />
                                        </div>
                                    )}

                                    <div>
                                        <label className="block text-sm font-medium text-gray-700 mb-2">Temporary Password</label>
                                        <div className="relative">
                                            <div className="absolute inset-y-0 left-0 flex items-center pl-3">
                                                <button
                                                    type="button"
                                                    onClick={copyToClipboard}
                                                    className="p-1 text-gray-400 hover:text-blue-600 transition-colors"
                                                    title="Copy to clipboard"
                                                >
                                                    {isCopied ?
                                                        <CheckIcon className="h-5 w-5 text-green-500" /> :
                                                        <ClipboardDocumentIcon className="h-5 w-5" />
                                                    }
                                                </button>
                                            </div>
                                            <input
                                                type={showPassword ? "text" : "password"}
                                                readOnly
                                                className="block w-full rounded-lg border-gray-300 bg-gray-50 py-3 pl-10 pr-24 text-left shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm font-mono text-gray-600"
                                                value={formData.password}
                                            />
                                            <div className="absolute inset-y-0 right-0 flex items-center pr-2 gap-1">
                                                <button
                                                    type="button"
                                                    onClick={() => setFormData({ ...formData, password: generatePassword() })}
                                                    className="p-2 text-gray-400 hover:text-blue-600 rounded-full hover:bg-blue-50 transition-colors"
                                                    title="Generate new password"
                                                >
                                                    <ArrowPathIcon className="h-5 w-5" />
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => setShowPassword(!showPassword)}
                                                    className="p-2 text-gray-400 hover:text-gray-600 rounded-full hover:bg-gray-100 transition-colors"
                                                    title={showPassword ? "Hide password" : "Show password"}
                                                >
                                                    {showPassword ? <EyeSlashIcon className="h-5 w-5" /> : <EyeIcon className="h-5 w-5" />}
                                                </button>
                                            </div>
                                        </div>
                                        <p className="mt-2 text-xs text-gray-500 flex items-center">
                                            <span className="inline-block w-2 h-2 rounded-full bg-blue-400 mr-2"></span>
                                            Copy this password. It will not be shown again.
                                        </p>
                                    </div>

                                    <div className="mt-6 flex justify-end gap-3">
                                        <button
                                            type="button"
                                            onClick={onClose}
                                            className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
                                        >
                                            Cancel
                                        </button>
                                        <button
                                            type="submit"
                                            disabled={loading}
                                            className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50"
                                        >
                                            {loading ? 'Creating...' : 'Create User'}
                                        </button>
                                    </div>
                                </form>
                            </Dialog.Panel>
                        </Transition.Child>
                    </div>
                </div>
            </Dialog>
        </Transition>
    )
}
