import { useAuth } from '../hooks/useAuth'
import { useNavigate, Link } from 'react-router-dom'

export default function Dashboard() {
  const { userProfile, signOut } = useAuth()
  const navigate = useNavigate()

  const handleSignOut = async () => {
    await signOut()
    navigate('/login')
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16">
            <div className="flex items-center">
              <h1 className="text-xl font-bold text-gray-900">NVS Maintenance</h1>
            </div>
            <div className="flex items-center space-x-4">
              <span className="text-sm text-gray-700">
                {userProfile?.name} ({userProfile?.role})
              </span>
              <button
                onClick={handleSignOut}
                className="text-sm text-gray-700 hover:text-gray-900"
              >
                Sign out
              </button>
            </div>
          </div>
        </div>
      </nav>

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
