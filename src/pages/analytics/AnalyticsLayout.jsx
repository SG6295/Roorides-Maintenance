import { Link, useLocation, Outlet } from 'react-router-dom'
import { ClockIcon, UserGroupIcon } from '@heroicons/react/24/outline'
import Navigation from '../../components/shared/Navigation'

// Each report is a sub-page under /analytics (MAIN-117). Add new reports here.
const reports = [
    { name: 'SLA & tickets', href: '/analytics/sla', icon: ClockIcon },
    { name: 'Labour utilisation', href: '/analytics/labour', icon: UserGroupIcon },
]

export default function AnalyticsLayout() {
    const location = useLocation()
    const current = reports.find(r => r.href === location.pathname)

    return (
        <div className="min-h-screen bg-gray-50 pb-12">
            <Navigation breadcrumbs={[
                { label: 'Analytics', href: '/analytics' },
                ...(current ? [{ label: current.name }] : []),
            ]} />

            <div className="max-w-[90rem] mx-auto px-4 sm:px-6 py-6 lg:flex lg:gap-6">
                <aside className="lg:w-52 lg:shrink-0 mb-4 lg:mb-0">
                    <nav className="flex lg:flex-col gap-1 overflow-x-auto" aria-label="Reports">
                        {reports.map(r => {
                            const active = location.pathname === r.href
                            return (
                                <Link
                                    key={r.href}
                                    to={r.href}
                                    aria-current={active ? 'page' : undefined}
                                    className={`group shrink-0 rounded-md px-3 py-2 flex items-center text-sm font-medium ${
                                        active ? 'bg-blue-50 text-blue-700' : 'text-gray-900 hover:bg-white'
                                    }`}
                                >
                                    <r.icon className={`-ml-1 mr-2.5 h-5 w-5 shrink-0 ${active ? 'text-blue-500' : 'text-gray-500'}`} aria-hidden="true" />
                                    {r.name}
                                </Link>
                            )
                        })}
                    </nav>
                </aside>

                <main className="flex-1 min-w-0">
                    <Outlet />
                </main>
            </div>
        </div>
    )
}
