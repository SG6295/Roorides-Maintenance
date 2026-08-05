import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import Navigation from '../components/shared/Navigation'
import { ROLE_LABELS } from '../constants/userRoles'

/**
 * Self-service profile. Password only.
 *
 * Name and email are deliberately read-only here. Two reasons:
 *  1. public.users has no self-UPDATE policy, so a name save by a supervisor,
 *     mechanic, electrician or finance user silently affected zero rows while
 *     still reporting success.
 *  2. Editing email through supabase.auth.updateUser() changes the login address
 *     without touching public.users.email, leaving the two permanently out of
 *     step.
 * Both changes now go through Settings → User Management, which enforces the
 * role rules server-side and records every change in user_audit_logs. Password
 * changes stay here: they are an auth operation scoped to the caller, so they
 * work for every role and never touch public.users.
 */
export default function Profile() {
  const { user, userProfile } = useAuth()

  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordMsg, setPasswordMsg] = useState(null)

  const handlePasswordSave = async (e) => {
    e.preventDefault()
    setPasswordMsg(null)
    if (newPassword !== confirmPassword) {
      setPasswordMsg({ type: 'error', text: 'Passwords do not match.' })
      return
    }
    if (newPassword.length < 8) {
      setPasswordMsg({ type: 'error', text: 'Password must be at least 8 characters.' })
      return
    }
    setPasswordLoading(true)
    const { error } = await supabase.auth.updateUser({ password: newPassword })
    if (error) {
      setPasswordMsg({ type: 'error', text: error.message })
    } else {
      setNewPassword('')
      setConfirmPassword('')
      setPasswordMsg({ type: 'success', text: 'Password updated successfully.' })
    }
    setPasswordLoading(false)
  }

  const readOnlyField = (label, value) => (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-1">{label}</label>
      <input
        type="text"
        value={value || '—'}
        disabled
        className="w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-500"
      />
    </div>
  )

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation breadcrumbs={[{ label: 'Profile' }]} />

      <main className="max-w-2xl mx-auto py-8 px-4 sm:px-6 space-y-6">
        <h1 className="text-2xl font-bold text-gray-900">Profile</h1>

        {/* Account details — managed by an administrator */}
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-base font-semibold text-gray-900 mb-4">Account Details</h2>
          <div className="space-y-4">
            {readOnlyField('Name', userProfile?.name)}
            {readOnlyField('Email', user?.email)}
            {readOnlyField('Role', ROLE_LABELS[userProfile?.role] || userProfile?.role)}
            {userProfile?.site && readOnlyField('Site', userProfile.site)}
            <p className="text-xs text-gray-500">
              To change your name or email address, ask an administrator to update it
              under Settings → User Management.
            </p>
          </div>
        </div>

        {/* Password */}
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-base font-semibold text-gray-900 mb-4">Change Password</h2>
          <form onSubmit={handlePasswordSave} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">New Password</label>
              <input
                type="password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                required
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Confirm New Password</label>
              <input
                type="password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            {passwordMsg && (
              <p className={`text-sm ${passwordMsg.type === 'error' ? 'text-red-600' : 'text-green-600'}`}>
                {passwordMsg.text}
              </p>
            )}
            <button
              type="submit"
              disabled={passwordLoading}
              className="px-4 py-2 bg-blue-600 text-white text-sm rounded-md hover:bg-blue-700 disabled:opacity-50"
            >
              {passwordLoading ? 'Saving...' : 'Update Password'}
            </button>
          </form>
        </div>
      </main>
    </div>
  )
}
