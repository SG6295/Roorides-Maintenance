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

import Users from './pages/Users'
import ForgotPassword from './pages/auth/ForgotPassword'
import UpdatePassword from './pages/auth/UpdatePassword'

import SettingsLayout from './pages/settings/SettingsLayout'
import NotificationSettings from './pages/settings/NotificationSettings'

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
  const { user, userProfile, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-gray-600">Loading...</div>
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" />
  }

  // Role check
  if (allowedRoles.length > 0 && userProfile && !allowedRoles.includes(userProfile.role)) {
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
                <ProtectedRoute allowedRoles={['maintenance_exec', 'mechanic']}>
                  <JobCards />
                </ProtectedRoute>
              }
            />
            <Route
              path="/job-cards/:id"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec', 'mechanic']}>
                  <JobCardDetail />
                </ProtectedRoute>
              }
            />
            <Route
              path="/users"
              element={
                <ProtectedRoute allowedRoles={['maintenance_exec']}>
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
                <ProtectedRoute allowedRoles={['maintenance_exec']}>
                  <Analytics />
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
