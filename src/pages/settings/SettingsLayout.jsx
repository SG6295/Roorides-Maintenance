
import { useState } from 'react'
import { Link, useLocation, Outlet } from 'react-router-dom'
import { BellIcon, UsersIcon, ClockIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../../hooks/useAuth'

const tabs = [
    { name: 'Notifications', href: '/settings/notifications', icon: BellIcon, roles: [] }, // All roles
    { name: 'User Management', href: '/settings/users', icon: UsersIcon, roles: ['maintenance_exec'] },
    { name: 'SLA Automation', href: '/settings/sla', icon: ClockIcon, roles: ['maintenance_exec'] },
]

function classNames(...classes) {
    return classes.filter(Boolean).join(' ')
}

export default function SettingsLayout() {
    const location = useLocation()
    const { userProfile } = useAuth()

    const currentTab = tabs.find(tab => tab.href === location.pathname) || tabs[0]

    return (
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <div className="lg:grid lg:grid-cols-12 lg:gap-x-5">
                <aside className="py-6 px-2 sm:px-6 lg:col-span-3 lg:py-0 lg:px-0">
                    <nav className="space-y-1">
                        {tabs.map((tab) => {
                            if (tab.roles.length > 0 && !tab.roles.includes(userProfile?.role)) {
                                return null
                            }
                            const isActive = location.pathname === tab.href
                            return (
                                <Link
                                    key={tab.name}
                                    to={tab.href}
                                    className={classNames(
                                        isActive
                                            ? 'bg-gray-50 text-blue-700 hover:text-blue-700 hover:bg-white'
                                            : 'text-gray-900 hover:text-gray-900 hover:bg-gray-50',
                                        'group rounded-md px-3 py-2 flex items-center text-sm font-medium'
                                    )}
                                    aria-current={isActive ? 'page' : undefined}
                                >
                                    <tab.icon
                                        className={classNames(
                                            isActive ? 'text-blue-500 group-hover:text-blue-500' : 'text-gray-400 group-hover:text-gray-500',
                                            'flex-shrink-0 -ml-1 mr-3 h-6 w-6'
                                        )}
                                        aria-hidden="true"
                                    />
                                    <span className="truncate">{tab.name}</span>
                                </Link>
                            )
                        })}
                    </nav>
                </aside>

                <div className="space-y-6 sm:px-6 lg:col-span-9 lg:px-0">
                    <div className="bg-white shadow px-4 py-5 sm:rounded-lg sm:p-6">
                        <Outlet />
                    </div>
                </div>
            </div>
        </div>
    )
}
