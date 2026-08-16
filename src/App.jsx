import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider, useAuth } from './hooks/useAuth'
import Login from './pages/Login'
import Dashboard from './pages/Dashboard'
import Tickets from './pages/Tickets'
import NewTicket from './pages/NewTicket'
import TicketDetail from './pages/TicketDetail'
import JobCards from './pages/JobCards'
import JobCardDetail from './pages/JobCardDetail'
import Issues from './pages/Issues'
import SLASettings from './pages/SLASettings'
import Analytics from './pages/Analytics'
import FeedbackReport from './pages/FeedbackReport'
import Inventory from './pages/Inventory'
import Scrap from './pages/Scrap'
import VehicleHistory from './pages/VehicleHistory'
import MechanicDetail from './pages/MechanicDetail'
import Vehicles from './pages/Vehicles'

import OutsourceInvoices from './pages/OutsourceInvoices'
import Suppliers from './pages/Suppliers'
import SupplierDetail from './pages/SupplierDetail'
import SupplierRegistration from './pages/SupplierRegistration'
import Users from './pages/Users'
import Profile from './pages/Profile'
import ForgotPassword from './pages/auth/ForgotPassword'
import UpdatePassword from './pages/auth/UpdatePassword'

import SettingsLayout from './pages/settings/SettingsLayout'
import NotificationSettings from './pages/settings/NotificationSettings'
import PartUnitsSettings from './pages/settings/PartUnitsSettings'
import WorkshopLocationSettings from './pages/settings/WorkshopLocationSettings'
import SeedStaging from './pages/settings/SeedStaging'

import { sendEmail } from './lib/email'

// Expose for testing
window.testResend = async (email) => {
  const res = await sendEmail({
    to: email,
    subject: 'NVS Maintenance: Test Email',
    html: '<strong>Resend Integration is Working!</strong> 🚀'
  })
  console.log('Email Result:', res)
  return res
}

const queryClient = new QueryClient()

function ProtectedRoute({ children, allowedRoles = [] }) {
  const { user, userProfile, loading, profileError } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-gray-600">Loading...</div>
      </div>
    )
  }

  // Before the profile check — a deactivated user is signed out and then
  // throws, so they belong at the login screen, not the error screen.
  if (!user) {
    return <Navigate to="/login" />
  }

  // Without a profile there is no role to check, so the role gate below cannot
  // be trusted. Fail closed rather than rendering the page.
  if (profileError || !userProfile) {
    return (
      <div className="min-h-screen flex items-center justify-center p-4">
        <div className="max-w-sm text-center">
          <h1 className="text-lg font-medium text-gray-900">
            We couldn't load your account
          </h1>
          <p className="mt-2 text-sm text-gray-600">
            This is usually a connection problem. Please refresh to try again —
            if it keeps happening, contact your administrator.
          </p>
          <button
            onClick={() => window.location.reload()}
            className="mt-4 px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700"
          >
            Refresh
          </button>
        </div>
      </div>
    )
  }

  // Role check
  if (allowedRoles.length > 0 && !allowedRoles.includes(userProfile.role)) {
    return <Navigate to="/dashboard" replace />
  }

  return children
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route
              path="/dashboard"
              element={
                <ProtectedRoute>
                  <Dashboard />
                </ProtectedRoute>
              }
            />
            <Route
              path="/tickets"
              element={
                <ProtectedRoute>
                  <Tickets />
                </ProtectedRoute>
              }
            />
            <Route
              path="/tickets/new"
              element={
                <ProtectedRoute>
                  <NewTicket />
                </ProtectedRoute>
              }
            />
            <Route
              path="/tickets/:id"
              element={
                <ProtectedRoute>
                  <TicketDetail />
                </ProtectedRoute>
              }
            />
            <Route
              path="/issues"
              element={
                <ProtectedRoute>
                  <Issues />
                </ProtectedRoute>
              }
            />
            <Route
              path="/job-cards"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'mechanic', 'electrician']}>
                  <JobCards />
                </ProtectedRoute>
              }
            />
            <Route
              path="/job-cards/:id"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'mechanic', 'electrician']}>
                  <JobCardDetail />
                </ProtectedRoute>
              }
            />
            <Route
              path="/users"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin']}>
                  <Users />
                </ProtectedRoute>
              }
            />
            <Route
              path="/sla-settings"
              element={
                <ProtectedRoute>
                  <SLASettings />
                </ProtectedRoute>
              }
            />
            <Route
              path="/analytics"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin']}>
                  <Analytics />
                </ProtectedRoute>
              }
            />
            <Route
              path="/feedback"
              element={
                <ProtectedRoute>
                  <FeedbackReport />
                </ProtectedRoute>
              }
            />
            <Route
              path="/inventory"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <Inventory />
                </ProtectedRoute>
              }
            />
            <Route
              path="/scrap"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <Scrap />
                </ProtectedRoute>
              }
            />
            <Route
              path="/vehicles"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <Vehicles />
                </ProtectedRoute>
              }
            />
            <Route
              path="/vehicles/:vehicleNumber"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <VehicleHistory />
                </ProtectedRoute>
              }
            />
            <Route
              path="/mechanics/:mechanicId"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <MechanicDetail />
                </ProtectedRoute>
              }
            />
            <Route
              path="/profile"
              element={
                <ProtectedRoute>
                  <Profile />
                </ProtectedRoute>
              }
            />
            {/* Public supplier registration — no auth required */}
            <Route path="/supplier-registration" element={<SupplierRegistration />} />

            <Route
              path="/outsource-invoices"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance', 'supervisor']}>
                  <OutsourceInvoices />
                </ProtectedRoute>
              }
            />
            <Route
              path="/suppliers"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <Suppliers />
                </ProtectedRoute>
              }
            />
            <Route
              path="/suppliers/:id"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'super_admin', 'finance']}>
                  <SupplierDetail />
                </ProtectedRoute>
              }
            />

            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route
              path="/update-password"
              element={
                <ProtectedRoute>
                  <UpdatePassword />
                </ProtectedRoute>
              }
            />
            {/* Settings Nested Routes */}
            <Route
              path="/settings"
              element={
                <ProtectedRoute>
                  <SettingsLayout />
                </ProtectedRoute>
              }
            >
              <Route path="notifications" element={<NotificationSettings />} />
              <Route path="users" element={<Users embedded={true} />} />
              <Route path="sla" element={<SLASettings embedded={true} />} />
              <Route path="units" element={<PartUnitsSettings />} />
              <Route path="workshops" element={<WorkshopLocationSettings />} />
              {import.meta.env.VITE_ENABLE_DANGER_ZONE === 'true' && (
                <Route path="seed-staging" element={<SeedStaging />} />
              )}
              <Route index element={<Navigate to="notifications" replace />} />
            </Route>

            <Route path="/" element={<Navigate to="/dashboard" />} />
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </QueryClientProvider>
  )
}

export default App
