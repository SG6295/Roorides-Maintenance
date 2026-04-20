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
          {/* Quick Actions */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {/* 1. View Tickets */}
            <Link
              to="/tickets"
              className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
            >
              <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-blue-200 transition-colors">
                <svg className="w-6 h-6 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-1">View Tickets</h3>
            </Link>

            {/* 2. View Issues */}
            <Link
              to="/issues"
              className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
            >
              <div className="w-12 h-12 bg-purple-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-purple-200 transition-colors">
                <svg className="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-1">View Issues</h3>
            </Link>

            {/* 3. View Job Cards */}
            <Link
              to="/job-cards"
              className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
            >
              <div className="w-12 h-12 bg-orange-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-orange-200 transition-colors">
                <svg className="w-6 h-6 text-orange-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-1">View Job Cards</h3>
            </Link>

            {/* 4. View Feedback */}
            <Link
              to="/feedback"
              className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
            >
              <div className="w-12 h-12 bg-teal-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-teal-200 transition-colors">
                <svg className="w-6 h-6 text-teal-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.828 14.828a4 4 0 01-5.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-1">View Feedback</h3>
            </Link>

            {/* Analysis */}
            {['maintenance_exec', 'super_admin'].includes(userProfile?.role) ? (
              <Link
                to="/analytics"
                className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
              >
                <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-green-200 transition-colors">
                  <svg className="w-6 h-6 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                </div>
                <h3 className="text-lg font-semibold text-gray-900 mb-1">Analysis</h3>
              </Link>
            ) : null}

            {/* Vehicles */}
            {(['maintenance_exec', 'super_admin', 'finance'].includes(userProfile?.role)) && (
              <Link
                to="/vehicles"
                className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
              >
                <div className="w-12 h-12 bg-sky-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-sky-200 transition-colors">
                  <svg className="w-6 h-6 text-sky-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 17a2 2 0 100 4 2 2 0 000-4zm8 0a2 2 0 100 4 2 2 0 000-4zM3 4h2l2.5 8h9L19 7H7" />
                  </svg>
                </div>
                <h3 className="text-lg font-semibold text-gray-900 mb-1">Vehicles</h3>
              </Link>
            )}

            {/* Inventory */}
            {(['maintenance_exec', 'super_admin', 'finance'].includes(userProfile?.role)) && (
              <Link
                to="/inventory"
                className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
              >
                <div className="w-12 h-12 bg-amber-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-amber-200 transition-colors">
                  <svg className="w-6 h-6 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
                  </svg>
                </div>
                <h3 className="text-lg font-semibold text-gray-900 mb-1">Inventory</h3>
              </Link>
            )}

            {/* Suppliers */}
            {(['maintenance_exec', 'super_admin', 'finance'].includes(userProfile?.role)) && (
              <Link
                to="/suppliers"
                className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
              >
                <div className="w-12 h-12 bg-indigo-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-indigo-200 transition-colors">
                  <svg className="w-6 h-6 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                  </svg>
                </div>
                <h3 className="text-lg font-semibold text-gray-900 mb-1">Suppliers</h3>
              </Link>
            )}

            {/* Settings */}
            <Link
              to="/settings"
              className="bg-white p-6 rounded-lg shadow hover:shadow-md transition-shadow flex flex-col items-center text-center group"
            >
              <div className="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-4 group-hover:bg-gray-200 transition-colors">
                <svg className="w-6 h-6 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </div>
              <h3 className="text-lg font-semibold text-gray-900 mb-1">Settings</h3>
            </Link>
          </div>
        </div>
      </main>
    </div>
  )
}
