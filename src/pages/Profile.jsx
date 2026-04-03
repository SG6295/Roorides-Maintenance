import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../hooks/useAuth'
import Navigation from '../components/shared/Navigation'

export default function Profile() {
  const { user, userProfile, refreshProfile } = useAuth()
  const navigate = useNavigate()

  const [name, setName] = useState(userProfile?.name || '')
  const [nameLoading, setNameLoading] = useState(false)
  const [nameMsg, setNameMsg] = useState(null)

  const [email, setEmail] = useState(user?.email || '')
  const [emailLoading, setEmailLoading] = useState(false)
  const [emailMsg, setEmailMsg] = useState(null)

  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [passwordLoading, setPasswordLoading] = useState(false)
  const [passwordMsg, setPasswordMsg] = useState(null)

  const handleNameSave = async (e) => {
    e.preventDefault()
    setNameLoading(true)
    setNameMsg(null)
    const { error } = await supabase
      .from('users')
      .update({ name: name.trim() })
      .eq('id', user.id)
    if (error) {
      setNameMsg({ type: 'error', text: error.message })
    } else {
      await refreshProfile()
      setNameMsg({ type: 'success', text: 'Name updated.' })
    }
    setNameLoading(false)
  }

  const handleEmailSave = async (e) => {
    e.preventDefault()
    setEmailLoading(true)
    setEmailMsg(null)
    const { error } = await supabase.auth.updateUser({ email: email.trim() })
    if (error) {
      setEmailMsg({ type: 'error', text: error.message })
    } else {
      setEmailMsg({ type: 'success', text: 'Confirmation sent to new email. Check your inbox.' })
    }
    setEmailLoading(false)
  }

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
      setCurrentPassword('')
      setNewPassword('')
      setConfirmPassword('')
      setPasswordMsg({ type: 'success', text: 'Password updated successfully.' })
    }
    setPasswordLoading(false)
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation breadcrumbs={[{ label: 'Profile' }]} />

      <main className="max-w-2xl mx-auto py-8 px-4 sm:px-6 space-y-6">
        <h1 className="text-2xl font-bold text-gray-900">Profile</h1>

        {/* Name */}
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-base font-semibold text-gray-900 mb-4">Personal Information</h2>
          <form onSubmit={handleNameSave} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Name</label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Role</label>
              <input
                type="text"
                value={userProfile?.role || ''}
                disabled
                className="w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-500"
              />
            </div>
            {userProfile?.site && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">Site</label>
                <input
                  type="text"
                  value={userProfile.site}
                  disabled
                  className="w-full border border-gray-200 rounded-md px-3 py-2 text-sm bg-gray-50 text-gray-500"
                />
              </div>
            )}
            {nameMsg && (
              <p className={`text-sm ${nameMsg.type === 'error' ? 'text-red-600' : 'text-green-600'}`}>
                {nameMsg.text}
              </p>
            )}
            <button
              type="submit"
              disabled={nameLoading}
              className="px-4 py-2 bg-blue-600 text-white text-sm rounded-md hover:bg-blue-700 disabled:opacity-50"
            >
              {nameLoading ? 'Saving...' : 'Save Name'}
            </button>
          </form>
        </div>

        {/* Email */}
        <div className="bg-white rounded-lg shadow p-6">
          <h2 className="text-base font-semibold text-gray-900 mb-4">Email Address</h2>
          <form onSubmit={handleEmailSave} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            {emailMsg && (
              <p className={`text-sm ${emailMsg.type === 'error' ? 'text-red-600' : 'text-green-600'}`}>
                {emailMsg.text}
              </p>
            )}
            <button
              type="submit"
              disabled={emailLoading}
              className="px-4 py-2 bg-blue-600 text-white text-sm rounded-md hover:bg-blue-700 disabled:opacity-50"
            >
              {emailLoading ? 'Saving...' : 'Update Email'}
            </button>
          </form>
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
