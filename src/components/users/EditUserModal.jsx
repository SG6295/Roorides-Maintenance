
import { useState, useEffect, useMemo, Fragment } from 'react'
import { Dialog, Transition } from '@headlessui/react'
import { FunctionsHttpError } from '@supabase/supabase-js'
import { XMarkIcon, EyeIcon, EyeSlashIcon, ArrowPathIcon, ClipboardDocumentIcon, CheckIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline'
import CustomSelect from '../shared/CustomSelect'
import SiteCheckboxList from './SiteCheckboxList'
import { supabase } from '../../lib/supabase'
import { useAllSites } from '../../hooks/useSites'
import { useAuth } from '../../hooks/useAuth'
import { roleOptions, generatePassword, MIN_PASSWORD_LENGTH } from '../../constants/userRoles'

const EMPTY_FORM = {
    name: '',
    email: '',
    role: 'supervisor',
    sites: [],
    employee_id: '',
    contact: '',
}

export default function EditUserModal({ isOpen, user, onClose, onSuccess }) {
    const { userProfile } = useAuth()
    // All sites — an existing assignment to a deactivated site has to stay visible,
    // otherwise there is no way to remove it.
    const { data: sites = [], isLoading: sitesLoading } = useAllSites()

    const availableRoles = roleOptions(userProfile?.role)

    const [formData, setFormData] = useState(EMPTY_FORM)
    const [showPasswordSection, setShowPasswordSection] = useState(false)
    const [password, setPassword] = useState('')
    const [showPassword, setShowPassword] = useState(true)
    const [isCopied, setIsCopied] = useState(false)
    const [loading, setLoading] = useState(false)
    const [error, setError] = useState(null)

    // Site IDs come from user_sites.site_id rather than the joined sites.id —
    // site_id is always present even when the join row is missing.
    const originalSites = useMemo(
        () => (user?.user_sites ?? []).map(us => us.site_id),
        // eslint-disable-next-line react-hooks/exhaustive-deps
        [user?.id]
    )

    useEffect(() => {
        if (!isOpen || !user) return
        setFormData({
            name: user.name ?? '',
            email: user.email ?? '',
            role: user.role,
            sites: (user.user_sites ?? []).map(us => us.site_id),
            employee_id: user.employee_id ?? '',
            contact: user.contact ?? '',
        })
        setShowPasswordSection(false)
        setPassword('')
        setError(null)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [isOpen, user?.id])

    const copyToClipboard = () => {
        navigator.clipboard.writeText(password)
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

    // Unlike AddUserModal we never blank the site list on a role change — an
    // accidental supervisor → mechanic → supervisor round trip would otherwise
    // silently wipe an existing assignment.
    const handleRoleChange = (nextRole) => {
        setFormData(prev => ({
            ...prev,
            role: nextRole,
            sites: nextRole === 'supervisor' && prev.sites.length === 0
                ? originalSites
                : prev.sites,
        }))
    }

    const openPasswordSection = () => {
        setPassword(generatePassword())
        setShowPasswordSection(true)
    }

    const cancelPasswordChange = () => {
        setShowPasswordSection(false)
        setPassword('')
    }

    const losingSites = user?.role === 'supervisor' && formData.role !== 'supervisor'

    const handleSubmit = async (e) => {
        e.preventDefault()
        setError(null)

        if (formData.role === 'supervisor' && formData.sites.length === 0) {
            setError('Please assign at least one site to this supervisor.')
            return
        }
        if (showPasswordSection && password.length < MIN_PASSWORD_LENGTH) {
            setError(`Password must be at least ${MIN_PASSWORD_LENGTH} characters.`)
            return
        }

        setLoading(true)
        try {
            const { data, error: fnError } = await supabase.functions.invoke('update-user', {
                body: {
                    action: 'update',
                    user_id: user.id,
                    name: formData.name,
                    email: formData.email,
                    role: formData.role,
                    employee_id: formData.employee_id,
                    contact: formData.contact,
                    sites: formData.role === 'supervisor' ? formData.sites : [],
                    password: showPasswordSection && password ? password : null,
                }
            })

            // invoke() returns data = null and a FunctionsHttpError for any non-2xx,
            // so the real message has to be read off the response body.
            if (fnError) {
                const body = fnError instanceof FunctionsHttpError
                    ? await fnError.context.json().catch(() => null)
                    : null
                throw new Error(body?.error || fnError.message)
            }
            if (data?.error) throw new Error(data.error)

            const changedPassword = data?.password_changed
            onSuccess()
            onClose()
            if (changedPassword) {
                alert(`Password updated!\nEmail: ${formData.email}\nNew password: ${password}`)
            }
        } catch (err) {
            console.error('Error updating user:', err)
            setError(err.message || 'Failed to update user')
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
                                        Edit User
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
                                            value={formData.email}
                                            onChange={e => setFormData({ ...formData, email: e.target.value })}
                                        />
                                        <p className="mt-1 text-xs text-gray-500">
                                            This is their login email — changing it takes effect immediately.
                                        </p>
                                    </div>

                                    <div className="grid grid-cols-2 gap-4">
                                        <div>
                                            <CustomSelect
                                                label="Role"
                                                value={formData.role}
                                                onChange={handleRoleChange}
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

                                    {losingSites && (
                                        <p className="flex items-start gap-2 text-xs text-amber-700 bg-amber-50 rounded-lg p-3">
                                            <ExclamationTriangleIcon className="h-4 w-4 flex-shrink-0 mt-0.5" />
                                            <span>Changing the role will remove this user&apos;s site assignments.</span>
                                        </p>
                                    )}

                                    <div>
                                        <label className="block text-sm font-medium text-gray-700 mb-2">Contact</label>
                                        <input
                                            type="text"
                                            className="block w-full rounded-lg border-gray-300 py-3 px-4 text-left shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                                            placeholder="e.g. 98765 43210"
                                            value={formData.contact}
                                            onChange={e => setFormData({ ...formData, contact: e.target.value })}
                                        />
                                    </div>

                                    {formData.role === 'supervisor' && (
                                        <div>
                                            <label className="block text-sm font-medium text-gray-700 mb-2">
                                                Assigned Sites <span className="text-red-500">*</span>
                                            </label>
                                            <SiteCheckboxList
                                                sites={sites}
                                                selected={formData.sites}
                                                onToggle={toggleSite}
                                                loading={sitesLoading}
                                            />
                                        </div>
                                    )}

                                    {/* Password is optional — untouched means unchanged */}
                                    <div className="border-t border-gray-200 pt-4">
                                        {!showPasswordSection ? (
                                            <button
                                                type="button"
                                                onClick={openPasswordSection}
                                                className="text-sm font-medium text-blue-600 hover:text-blue-700"
                                            >
                                                Set a new password
                                            </button>
                                        ) : (
                                            <div>
                                                <div className="flex items-center justify-between mb-2">
                                                    <label className="block text-sm font-medium text-gray-700">New Password</label>
                                                    <button
                                                        type="button"
                                                        onClick={cancelPasswordChange}
                                                        className="text-xs text-gray-500 hover:text-gray-700"
                                                    >
                                                        Cancel password change
                                                    </button>
                                                </div>
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
                                                        type={showPassword ? 'text' : 'password'}
                                                        className="block w-full rounded-lg border-gray-300 py-3 pl-10 pr-24 text-left shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm font-mono"
                                                        value={password}
                                                        onChange={e => setPassword(e.target.value)}
                                                    />
                                                    <div className="absolute inset-y-0 right-0 flex items-center pr-2 gap-1">
                                                        <button
                                                            type="button"
                                                            onClick={() => setPassword(generatePassword())}
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
                                                <p className="mt-2 text-xs text-gray-600">
                                                    Copy this and share it with the user. They stay signed in on any device
                                                    they are already using until that session expires.
                                                </p>
                                            </div>
                                        )}
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
                                            {loading ? 'Saving...' : 'Save Changes'}
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
