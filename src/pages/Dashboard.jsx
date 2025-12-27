import { useAuth } from '../hooks/useAuth'
import { Link } from 'react-router-dom'
import Navigation from '../components/shared/Navigation'

export default function Dashboard() {
  const { userProfile } = useAuth()

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation />

      <main className="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        <div className="px-4 py-6 sm:px-0">
          <div className="mb-6">
            <h2 className="text-2xl font-bold text-gray-900 mb-2">
              Welcome, {userProfile?.name}
            </h2>
            <p className="text-gray-600">
              Role: {userProfile?.role}
              {userProfile?.site && ` | Site: ${userProfile.site}`}
            </p>
          </div>

          {/* Quick Actions */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <Link
              to="/tickets"
              className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow"
            >
              <h3 className="text-lg font-semibold text-gray-900 mb-2">View Tickets</h3>
              <p className="text-gray-600 text-sm">See all maintenance tickets</p>
            </Link>

            {userProfile?.role === 'supervisor' && (
              <Link
                to="/tickets/new"
                className="bg-blue-600 text-white p-6 rounded-lg shadow hover:shadow-md transition-shadow"
              >
                <h3 className="text-lg font-semibold mb-2">+ New Ticket</h3>
                <p className="text-blue-100 text-sm">Report a vehicle issue</p>
              </Link>
            )}

            <div className="bg-white p-6 rounded-lg shadow opacity-50">
              <h3 className="text-lg font-semibold text-gray-900 mb-2">Dashboard</h3>
              <p className="text-gray-600 text-sm">Coming soon...</p>
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}
