
import { useState } from 'react'
import { Switch } from '@headlessui/react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import Navigation from '../components/shared/Navigation'
import AddUserModal from '../components/users/AddUserModal'
import { PlusIcon, UserIcon, WrenchIcon, BriefcaseIcon, CurrencyDollarIcon, MagnifyingGlassIcon } from '@heroicons/react/24/outline'

export default function Users({ embedded = false }) {
    const { user: currentUser } = useAuth()
    const [isAddModalOpen, setIsAddModalOpen] = useState(false)
    const [filterRole, setFilterRole] = useState('all')
    const [searchQuery, setSearchQuery] = useState('')

    const toggleUserStatus = async (userId, currentStatus) => {
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
                .select('*')
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

    const getRoleIcon = (role) => {
        switch (role) {
            case 'mechanic': return <WrenchIcon className="h-5 w-5 text-gray-600" />
            case 'maintenance_exec': return <BriefcaseIcon className="h-5 w-5 text-purple-500" />
            case 'finance': return <CurrencyDollarIcon className="h-5 w-5 text-green-500" />
            default: return <UserIcon className="h-5 w-5 text-blue-500" />
        }
    }

    const getRoleLabel = (role) => {
        switch (role) {
            case 'maintenance_exec': return 'Maintenance Exec'
            default: return role?.charAt(0).toUpperCase() + role?.slice(1)
        }
    }

    return (
        <div className={embedded ? "" : "min-h-screen bg-gray-50"}>
            {!embedded && (
                <Navigation
                    breadcrumbs={[
                        { label: 'Users', href: '/users' }
                    ]}
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
                            <option value="supervisor">Supervisor</option>
                            <option value="mechanic">Mechanic</option>
                            <option value="maintenance_exec">Maintenance Exec</option>
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
                            filteredUsers.map((user) => (
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
                                                            <p className="text-sm text-gray-900">
                                                                {getRoleLabel(user.role)}
                                                            </p>
                                                            <p className="mt-1 flex items-center text-xs text-gray-600">
                                                                {user.site || 'Global'}
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
                                                            onChange={() => toggleUserStatus(user.id, user.is_active)}
                                                            disabled={currentUser?.id === user.id}
                                                            className={`${user.is_active ? 'bg-green-600' : 'bg-gray-200'} ${currentUser?.id === user.id ? 'opacity-50 cursor-not-allowed' : ''} relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2`}
                                                        >
                                                            <span className="sr-only">Use setting</span>
                                                            <span
                                                                aria-hidden="true"
                                                                className={`${user.is_active ? 'translate-x-5' : 'translate-x-0'} pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out`}
                                                            />
                                                        </Switch>
                                                    </div>
                                                    {/* Mobile Only Details */}
                                                    <div className="md:hidden text-right">
                                                        <p className="text-xs text-gray-600">{getRoleLabel(user.role)}</p>
                                                        <p className="text-xs text-gray-500">{user.site || 'Global'}</p>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                </li>
                            ))
                        )}
                    </ul>
                </div>
            </div>

            <AddUserModal
                isOpen={isAddModalOpen}
                onClose={() => setIsAddModalOpen(false)}
                onSuccess={() => {
                    refetch()
                }}
            />
        </div>
    )
}
