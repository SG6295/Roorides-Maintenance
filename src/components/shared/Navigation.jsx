import { Link, useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../../hooks/useAuth'

export default function Navigation({ breadcrumbs = [], actions }) {
  const { userProfile, signOut } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  const handleSignOut = async () => {
    await signOut()
    navigate('/login')
  }

  return (
    <nav className="bg-white shadow-sm sticky top-0 z-20">
      <div className="max-w-7xl mx-auto px-4 sm:px-6">
        {/* Top Bar */}
        <div className="flex justify-between h-16 items-center">
          <div className="flex items-center">
            <Link to="/dashboard" className="text-xl font-bold text-gray-900 hover:text-blue-600 mr-8">
              NVS Maintenance
            </Link>
          </div>

          <div className="flex items-center space-x-4">
            {actions && (
              <div className="mr-4">
                {actions}
              </div>
            )}

            <span className="text-sm text-gray-700 hidden sm:inline">
              {userProfile?.name} ({userProfile?.role})
            </span>
            <Link to="/settings" className="text-sm text-blue-600 hover:text-blue-800">
              Settings
            </Link>
            <button
              onClick={handleSignOut}
              className="text-sm text-gray-700 hover:text-gray-900"
            >
              Sign out
            </button>
          </div>
        </div>

        {/* Breadcrumbs */}
        {breadcrumbs.length > 0 && (
          <div className="pb-3 flex items-center text-sm text-gray-600 overflow-x-auto">
            <Link to="/dashboard" className="hover:text-blue-600">
              Dashboard
            </Link>
            {breadcrumbs.map((crumb, index) => (
              <div key={index} className="flex items-center">
                <span className="mx-2">/</span>
                {crumb.href ? (
                  <Link to={crumb.href} className="hover:text-blue-600">
                    {crumb.label}
                  </Link>
                ) : (
                  <span className="text-gray-900 font-medium">{crumb.label}</span>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </nav>
  )
}
