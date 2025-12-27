import { useAuth } from '../hooks/useAuth'
import { useNavigate } from 'react-router-dom'

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
          <div className="border-4 border-dashed border-gray-200 rounded-lg h-96 p-4">
            <h2 className="text-2xl font-bold text-gray-900 mb-4">
              Welcome, {userProfile?.name}
            </h2>
            <p className="text-gray-600">
              Role: {userProfile?.role}
              {userProfile?.site && ` | Site: ${userProfile.site}`}
            </p>
            <p className="text-gray-500 mt-4">Dashboard coming soon...</p>
          </div>
        </div>
      </main>
    </div>
  )
}
