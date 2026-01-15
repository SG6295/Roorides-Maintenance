
import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import Navigation from '../components/shared/Navigation'
import AddUserModal from '../components/users/AddUserModal'
import { PlusIcon, UserIcon, WrenchIcon, BriefcaseIcon, CurrencyDollarIcon, MagnifyingGlassIcon } from '@heroicons/react/24/outline'

export default function Users() {
    const [isAddModalOpen, setIsAddModalOpen] = useState(false)
    const [filterRole, setFilterRole] = useState('all')
    const [searchQuery, setSearchQuery] = useState('')

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
            case 'mechanic': return <WrenchIcon className="h-5 w-5 text-gray-500" />
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
        <div className="min-h-screen bg-gray-50">
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

            <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">

                {/* Filters */}
                <div className="mb-6 flex gap-4 flex-col sm:flex-row">
                    <div className="relative flex-1">
                        <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                            <MagnifyingGlassIcon className="h-5 w-5 text-gray-400" />
                        </div>
                        <input
                            type="text"
                            placeholder="Search users..."
                            className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-lg leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                        />
                    </div>
                    <select
                        value={filterRole}
                        onChange={(e) => setFilterRole(e.target.value)}
                        className="block w-full sm:w-48 pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-lg"
                    >
                        <option value="all">All Roles</option>
                        <option value="supervisor">Supervisor</option>
                        <option value="mechanic">Mechanic</option>
                        <option value="maintenance_exec">Maintenance Exec</option>
                        <option value="finance">Finance</option>
                    </select>
                </div>

                {/* Users List */}
                <div className="bg-white shadow overflow-hidden sm:rounded-md">
                    <ul role="list" className="divide-y divide-gray-200">
                        {isLoading ? (
                            <li className="px-6 py-4 text-center text-gray-500">Loading users...</li>
                        ) : filteredUsers?.length === 0 ? (
                            <li className="px-6 py-4 text-center text-gray-500">No users found</li>
                        ) : (
                            filteredUsers.map((user) => (
                                <li key={user.id}>
                                    <div className="px-4 py-4 sm:px-6 hover:bg-gray-50">
                                        <div className="flex items-center justify-between">
                                            <div className="flex items-center">
                                                <div className="flex-shrink-0 bg-gray-100 rounded-full p-2">
                                                    {getRoleIcon(user.role)}
                                                </div>
                                                <div className="ml-4">
                                                    <p className="text-sm font-medium text-blue-600 truncate">{user.name}</p>
                                                    <div className="flex items-center text-sm text-gray-500">
                                                        <span className="truncate">{user.email}</span>
                                                    </div>
                                                </div>
                                            </div>
                                            <div className="flex flex-col items-end">
                                                <span className="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800">
                                                    {user.is_active ? 'Active' : 'Inactive'}
                                                </span>
                                                <p className="mt-1 text-xs text-gray-500">
                                                    {getRoleLabel(user.role)} • {user.site || 'Global'}
                                                </p>
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
