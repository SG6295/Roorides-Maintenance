
import { useState, Fragment } from 'react'
import { Dialog, Transition } from '@headlessui/react'
import { XMarkIcon, EyeIcon, EyeSlashIcon, ArrowPathIcon, ClipboardDocumentIcon, CheckIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import { supabase } from '../../lib/supabase'
import { useSites } from '../../hooks/useSites'
import { useAuth } from '../../hooks/useAuth'

// What each creator role is allowed to create
const CREATABLE_ROLES = {
    super_admin: [
        { id: 'super_admin', name: 'Super Admin', value: 'super_admin' },
        { id: 'maintenance_exec', name: 'Maintenance Exec', value: 'maintenance_exec' },
        { id: 'finance', name: 'Finance', value: 'finance' },
        { id: 'supervisor', name: 'Supervisor', value: 'supervisor' },
        { id: 'mechanic', name: 'Mechanic', value: 'mechanic' },
        { id: 'electrician', name: 'Electrician', value: 'electrician' },
    ],
    maintenance_exec: [
        { id: 'supervisor', name: 'Supervisor', value: 'supervisor' },
        { id: 'mechanic', name: 'Mechanic', value: 'mechanic' },
        { id: 'electrician', name: 'Electrician', value: 'electrician' },
    ],
}

function generatePassword() {
    return Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-2).toUpperCase()
}

export default function AddUserModal({ isOpen, onClose, onSuccess }) {
    const { userProfile } = useAuth()
    const { data: sites = [], isLoading: sitesLoading } = useSites()

    const availableRoles = CREATABLE_ROLES[userProfile?.role] || []
    const defaultRole = availableRoles[0]?.value || 'supervisor'

    const [formData, setFormData] = useState({
        name: '',
        email: '',
        role: defaultRole,
        sites: [],       // array of site_id UUIDs (supervisors only)
        employee_id: '',
        contact: '',
        password: generatePassword()
    })
    const [loading, setLoading] = useState(false)
    const [showPassword, setShowPassword] = useState(true)
    const [isCopied, setIsCopied] = useState(false)
    const [error, setError] = useState(null)

    const resetForm = () => setFormData({
        name: '',
        email: '',
        role: defaultRole,
        sites: [],
        employee_id: '',
        contact: '',
        password: generatePassword()
    })

    const copyToClipboard = () => {
        navigator.clipboard.writeText(formData.password)
        setIsCopied(true)
        setTimeout(() => setIsCopied(false), 2000)
    }

    const toggleSite = (siteId) => {
        setFormData(prev => ({
            ...prev,
            sites: prev.sites.includes(siteId)
                ? prev.sites.filter(id => id !== siteId)
                : [...prev.sites, siteId]
        }))
    }

    const handleSubmit = async (e) => {
        e.preventDefault()
        setLoading(true)
        setError(null)

        if (formData.role === 'supervisor' && formData.sites.length === 0) {
            setError('Please assign at least one site to this supervisor.')
            setLoading(false)
            return
        }

        try {
            const { data, error } = await supabase.functions.invoke('create-user', {
                body: formData
            })

            if (error) throw error
            if (data?.error) throw new Error(data.error)

            onSuccess()
            onClose()
            resetForm()
            alert(`User created!\nEmail: ${formData.email}\nPassword: ${formData.password}`)
        } catch (err) {
            console.error('Error creating user:', err)
            setError(err.message || 'Failed to create user')
        } finally {
            setLoading(false)
        }
    }

    return (
        <Transition appear show={isOpen} as={Fragment}>
            <Dialog as="div" className="relative z-50" onClose={onClose}>
                <Transition.Child
                    as={Fragment}
                    enter="ease-out duration-300" enterFrom="opacity-0" enterTo="opacity-100"
                    leave="ease-in duration-200" leaveFrom="opacity-100" leaveTo="opacity-0"
                >
                    <div className="fixed inset-0 bg-black bg-opacity-25" />
                </Transition.Child>

                <div className="fixed inset-0 overflow-y-auto">
                    <div className="flex min-h-full items-center justify-center p-4 text-center">
                        <Transition.Child
                            as={Fragment}
                            enter="ease-out duration-300" enterFrom="opacity-0 scale-95" enterTo="opacity-100 scale-100"
                            leave="ease-in duration-200" leaveFrom="opacity-100 scale-100" leaveTo="opacity-0 scale-95"
                        >
                            <Dialog.Panel className="w-full max-w-md transform overflow-hidden rounded-2xl bg-white p-6 text-left align-middle shadow-xl transition-all">
                                <div className="flex justify-between items-center mb-4">
                                    <Dialog.Title as="h3" className="text-lg font-medium leading-6 text-gray-900">
                                        Add New User
                                    </Dialog.Title>
                                    <button onClick={onClose} className="text-gray-500 hover:text-gray-600">
                                        <XMarkIcon className="h-6 w-6" />
                                    </button>
                                </div>

                                <form onSubmit={handleSubmit} className="space-y-4">
                                    {error && (
                                        <div className="bg-red-50 text-red-600 p-3 rounded-lg text-sm">{error}</div>
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
                                                onChange={val => setFormData({ ...formData, role: val, sites: [] })}
                                                options={availableRoles}
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

                                    {/* Multi-site picker — supervisors only */}
                                    {formData.role === 'supervisor' && (
                                        <div>
                                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                                Assigned Sites <span className="text-red-500">*</span>
                                            </label>
                                            {sitesLoading ? (
                                                <p className="text-sm text-gray-500">Loading sites...</p>
                                            ) : sites.length === 0 ? (
                                                <p className="text-sm text-gray-500">No sites available.</p>
                                            ) : (
                                                <div className="max-h-40 overflow-y-auto border border-gray-300 rounded-lg divide-y divide-gray-100">
                                                    {sites.map(site => (
                                                        <label
                                                            key={site.id}
                                                            className="flex items-center gap-3 px-3 py-2 hover:bg-gray-50 cursor-pointer"
                                                        >
                                                            <input
                                                                type="checkbox"
                                                                checked={formData.sites.includes(site.id)}
                                                                onChange={() => toggleSite(site.id)}
                                                                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                                                            />
                                                            <span className="text-sm text-gray-700">{site.name}</span>
                                                        </label>
                                                    ))}
                                                </div>
                                            )}
                                            {formData.sites.length > 0 && (
                                                <p className="mt-1 text-xs text-gray-500">
                                                    {formData.sites.length} site{formData.sites.length > 1 ? 's' : ''} selected
                                                </p>
                                            )}
                                        </div>
                                    )}

                                    <div>
                                        <label className="block text-sm font-medium text-gray-700 mb-2">Temporary Password</label>
                                        <div className="relative">
                                            <div className="absolute inset-y-0 left-0 flex items-center pl-3">
                                                <button
                                                    type="button"
                                                    onClick={copyToClipboard}
                                                    className="p-1 text-gray-500 hover:text-blue-600 transition-colors"
                                                    title="Copy to clipboard"
                                                >
                                                    {isCopied
                                                        ? <CheckIcon className="h-5 w-5 text-green-500" />
                                                        : <ClipboardDocumentIcon className="h-5 w-5" />}
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
                                                    className="p-2 text-gray-500 hover:text-blue-600 rounded-full hover:bg-blue-50 transition-colors"
                                                    title="Generate new password"
                                                >
                                                    <ArrowPathIcon className="h-5 w-5" />
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => setShowPassword(!showPassword)}
                                                    className="p-2 text-gray-500 hover:text-gray-600 rounded-full hover:bg-gray-100 transition-colors"
                                                >
                                                    {showPassword ? <EyeSlashIcon className="h-5 w-5" /> : <EyeIcon className="h-5 w-5" />}
                                                </button>
                                            </div>
                                        </div>
                                        <p className="mt-2 text-xs text-gray-600 flex items-center">
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
