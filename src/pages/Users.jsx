
import { useState } from 'react'
import { Switch } from '@headlessui/react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import Navigation from '../components/shared/Navigation'
import AddUserModal from '../components/users/AddUserModal'
import { PlusIcon, UserIcon, WrenchIcon, BriefcaseIcon, CurrencyDollarIcon, MagnifyingGlassIcon, ShieldCheckIcon, BoltIcon } from '@heroicons/react/24/outline'

const ROLE_LABELS = {
    super_admin: 'Super Admin',
    maintenance_exec: 'Maintenance Exec',
    supervisor: 'Supervisor',
    mechanic: 'Mechanic',
    electrician: 'Electrician',
    finance: 'Finance',
}

const ROLE_COLORS = {
    super_admin: 'bg-purple-100 text-purple-800',
    maintenance_exec: 'bg-indigo-100 text-indigo-800',
    supervisor: 'bg-blue-100 text-blue-800',
    mechanic: 'bg-gray-100 text-gray-800',
    electrician: 'bg-yellow-100 text-yellow-800',
    finance: 'bg-green-100 text-green-800',
}

function getRoleIcon(role) {
    switch (role) {
        case 'super_admin': return <ShieldCheckIcon className="h-5 w-5 text-purple-500" />
        case 'maintenance_exec': return <BriefcaseIcon className="h-5 w-5 text-indigo-500" />
        case 'mechanic': return <WrenchIcon className="h-5 w-5 text-gray-600" />
        case 'electrician': return <BoltIcon className="h-5 w-5 text-yellow-500" />
        case 'finance': return <CurrencyDollarIcon className="h-5 w-5 text-green-500" />
        default: return <UserIcon className="h-5 w-5 text-blue-500" />
    }
}

// Roles that a given role is allowed to activate/deactivate
const MANAGEABLE_BY = {
    super_admin: ['super_admin', 'maintenance_exec', 'finance', 'supervisor', 'mechanic', 'electrician'],
    maintenance_exec: ['supervisor', 'mechanic', 'electrician'],
}

export default function Users({ embedded = false }) {
    const { userProfile: currentUserProfile } = useAuth()
    const [isAddModalOpen, setIsAddModalOpen] = useState(false)
    const [filterRole, setFilterRole] = useState('all')
    const [searchQuery, setSearchQuery] = useState('')

    const canManage = (targetRole, targetId) => {
        if (targetId === currentUserProfile?.id) return false
        const allowed = MANAGEABLE_BY[currentUserProfile?.role] || []
        return allowed.includes(targetRole)
    }

    const toggleUserStatus = async (userId, currentStatus, targetRole) => {
        if (!canManage(targetRole, userId)) return
        try {
            const { error } = await supabase
                .from('users')
                .update({ is_active: !currentStatus })
                .eq('id', userId)

            if (error) throw error
            refetch()
        } catch (error) {
            console.error('Error toggling status:', error)
            alert('Failed to update status')
        }
    }

    const { data: users, isLoading, refetch } = useQuery({
        queryKey: ['users'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('users')
                .select('*, user_sites(site_id, sites(id, name))')
                .order('created_at', { ascending: false })

            if (error) throw error
            return data
        }
    })

    const filteredUsers = users?.filter(user => {
        const matchesRole = filterRole === 'all' || user.role === filterRole
        const matchesSearch = user.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
            user.email?.toLowerCase().includes(searchQuery.toLowerCase())
        return matchesRole && matchesSearch
    })

    const getSiteDisplay = (user) => {
        if (user.user_sites?.length > 0) {
            return user.user_sites.map(us => us.sites?.name).filter(Boolean).join(', ')
        }
        return user.site || 'Global'
    }

    return (
        <div className={embedded ? "" : "min-h-screen bg-gray-50"}>
            {!embedded && (
                <Navigation
                    breadcrumbs={[{ label: 'Users', href: '/users' }]}
                    actions={
                        <button
                            onClick={() => setIsAddModalOpen(true)}
                            className="inline-flex items-center px-4 py-2 border border-transparent rounded-lg shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                        >
                            <PlusIcon className="-ml-1 mr-2 h-5 w-5" aria-hidden="true" />
                            Add User
                        </button>
                    }
                />
            )}

            <div className={embedded ? "" : "max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8"}>

                {embedded && (
                    <div className="md:flex md:items-center md:justify-between mb-6">
                        <div className="min-w-0 flex-1">
                            <h2 className="text-2xl font-bold leading-7 text-gray-900 sm:truncate sm:text-3xl sm:tracking-tight">
                                User Management
                            </h2>
                        </div>
                        <div className="mt-4 flex md:ml-4 md:mt-0">
                            <button
                                onClick={() => setIsAddModalOpen(true)}
                                className="ml-3 inline-flex items-center rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-blue-600"
                            >
                                <PlusIcon className="-ml-1.5 mr-1 h-5 w-5" aria-hidden="true" />
                                Add User
                            </button>
                        </div>
                    </div>
                )}

                {/* Filters */}
                <div className="mb-6 flex flex-col sm:flex-row gap-4">
                    <div className="relative flex-grow">
                        <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                            <MagnifyingGlassIcon className="h-5 w-5 text-gray-500" />
                        </div>
                        <input
                            type="text"
                            placeholder="Search users..."
                            className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-lg leading-5 bg-white placeholder-gray-500 focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                        />
                    </div>
                    <div className="sm:w-48">
                        <select
                            value={filterRole}
                            onChange={(e) => setFilterRole(e.target.value)}
                            className="block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-lg"
                        >
                            <option value="all">All Roles</option>
                            <option value="super_admin">Super Admin</option>
                            <option value="maintenance_exec">Maintenance Exec</option>
                            <option value="supervisor">Supervisor</option>
                            <option value="mechanic">Mechanic</option>
                            <option value="electrician">Electrician</option>
                            <option value="finance">Finance</option>
                        </select>
                    </div>
                </div>

                {/* Users List */}
                <div className="bg-white shadow overflow-hidden sm:rounded-md border border-gray-300">
                    <ul role="list" className="divide-y divide-gray-200">
                        {isLoading ? (
                            <li className="px-6 py-12 text-center text-gray-600">Loading users...</li>
                        ) : filteredUsers?.length === 0 ? (
                            <li className="px-6 py-12 text-center text-gray-600">No users found matching your filters.</li>
                        ) : (
                            filteredUsers.map((user) => {
                                const toggleAllowed = canManage(user.role, user.id)
                                return (
                                    <li key={user.id} className="hover:bg-gray-50 transition-colors duration-150 ease-in-out">
                                        <div className="px-4 py-4 sm:px-6">
                                            <div className="flex items-center justify-between">
                                                <div className="flex items-center min-w-0 flex-1">
                                                    <div className="flex-shrink-0">
                                                        <span className="inline-flex items-center justify-center h-10 w-10 rounded-full bg-gray-100 ring-4 ring-white">
                                                            {getRoleIcon(user.role)}
                                                        </span>
                                                    </div>
                                                    <div className="min-w-0 flex-1 px-4 md:grid md:grid-cols-2 md:gap-4">
                                                        <div>
                                                            <p className="text-sm font-medium text-blue-600 truncate">{user.name}</p>
                                                            <p className="mt-1 flex items-center text-sm text-gray-600">
                                                                <span className="truncate">{user.email}</span>
                                                            </p>
                                                        </div>
                                                        <div className="hidden md:block">
                                                            <div>
                                                                <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${ROLE_COLORS[user.role] || 'bg-gray-100 text-gray-800'}`}>
                                                                    {ROLE_LABELS[user.role] || user.role}
                                                                </span>
                                                                <p className="mt-1 flex items-center text-xs text-gray-600">
                                                                    {getSiteDisplay(user)}
                                                                </p>
                                                            </div>
                                                        </div>
                                                    </div>
                                                </div>
                                                <div>
                                                    <div className="flex flex-col items-end space-y-2">
                                                        <div className="flex items-center gap-2">
                                                            <span className={`text-xs font-medium ${user.is_active ? 'text-green-700' : 'text-gray-600'}`}>
                                                                {user.is_active ? 'Active' : 'Inactive'}
                                                            </span>
                                                            <Switch
                                                                checked={user.is_active}
                                                                onChange={() => toggleUserStatus(user.id, user.is_active, user.role)}
                                                                disabled={!toggleAllowed}
                                                                className={`${user.is_active ? 'bg-green-600' : 'bg-gray-200'} ${!toggleAllowed ? 'opacity-40 cursor-not-allowed' : ''} relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2`}
                                                            >
                                                                <span className="sr-only">Toggle status</span>
                                                                <span
                                                                    aria-hidden="true"
                                                                    className={`${user.is_active ? 'translate-x-5' : 'translate-x-0'} pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out`}
                                                                />
                                                            </Switch>
                                                        </div>
                                                        {/* Mobile Only Details */}
                                                        <div className="md:hidden text-right">
                                                            <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${ROLE_COLORS[user.role] || 'bg-gray-100 text-gray-800'}`}>
                                                                {ROLE_LABELS[user.role] || user.role}
                                                            </span>
                                                            <p className="text-xs text-gray-500 mt-1">{getSiteDisplay(user)}</p>
                                                        </div>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    </li>
                                )
                            })
                        )}
                    </ul>
                </div>
            </div>

            <AddUserModal
                isOpen={isAddModalOpen}
                onClose={() => setIsAddModalOpen(false)}
                onSuccess={() => refetch()}
            />
        </div>
    )
}
