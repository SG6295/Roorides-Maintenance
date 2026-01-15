
import { useState, useEffect } from 'react'
import { Switch } from '@headlessui/react'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../hooks/useAuth'

function Toggle({ label, description, enabled, onChange }) {
    return (
        <Switch.Group as="div" className="flex items-center justify-between py-4">
            <span className="flex flex-grow flex-col">
                <Switch.Label as="span" className="text-sm font-medium text-gray-900" passive>
                    {label}
                </Switch.Label>
                <Switch.Description as="span" className="text-sm text-gray-500">
                    {description}
                </Switch.Description>
            </span>
            <Switch
                checked={enabled}
                onChange={onChange}
                className={`${enabled ? 'bg-blue-600' : 'bg-gray-200'
                    } relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2`}
            >
                <span
                    aria-hidden="true"
                    className={`${enabled ? 'translate-x-5' : 'translate-x-0'
                        } pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out`}
                />
            </Switch>
        </Switch.Group>
    )
}

export default function NotificationSettings() {
    const { user } = useAuth()
    const [loading, setLoading] = useState(true)
    const [digestEnabled, setDigestEnabled] = useState(false)
    const [preferences, setPreferences] = useState({
        sla_expiring: true,
        rejected_24h: true,
        created_24h: true
    })

    useEffect(() => {
        if (!user) return
        fetchSettings()
    }, [user])

    const fetchSettings = async () => {
        setLoading(true)
        const { data, error } = await supabase
            .from('user_settings')
            .select('*')
            .eq('user_id', user.id)
            .single()

        if (data) {
            setDigestEnabled(data.notify_daily_digest)
            setPreferences(data.digest_preferences)
        } else if (error && error.code !== 'PGRST116') { // Ignore 'not found' error
            console.error('Error fetching settings:', error)
        }
        setLoading(false)
    }

    const saveSettings = async (newDigestEnabled, newPreferences) => {
        // Optimistic update
        setDigestEnabled(newDigestEnabled)
        setPreferences(newPreferences)

        const { error } = await supabase
            .from('user_settings')
            .upsert({
                user_id: user.id,
                notify_daily_digest: newDigestEnabled,
                digest_preferences: newPreferences,
                updated_at: new Date()
            })

        if (error) {
            console.error('Error saving settings:', error)
            alert('Failed to save settings')
        }
    }

    if (loading) return <div>Loading settings...</div>

    return (
        <div>
            <div className="md:flex md:items-center md:justify-between mb-6">
                <div className="min-w-0 flex-1">
                    <h2 className="text-2xl font-bold leading-7 text-gray-900 sm:truncate sm:text-3xl sm:tracking-tight">
                        Email Notifications
                    </h2>
                </div>
            </div>

            <div className="space-y-6">
                <div>
                    <h3 className="text-base font-semibold leading-6 text-gray-900">Daily Digest</h3>
                    <div className="max-w-xl text-sm text-gray-500">
                        <p>Receive a summary email every morning at 9:00 AM IST.</p>
                    </div>
                    <div className="mt-4 border-t border-gray-200 divide-y divide-gray-200">
                        <Toggle
                            label="Enable Daily Digest"
                            description="Turn on/off the daily email report."
                            enabled={digestEnabled}
                            onChange={(val) => saveSettings(val, preferences)}
                        />
                    </div>
                </div>

                {digestEnabled && (
                    <div className="mt-6">
                        <h3 className="text-base font-semibold leading-6 text-gray-900">Digest Content</h3>
                        <div className="max-w-xl text-sm text-gray-500">
                            <p>Select what information you want included in your report.</p>
                        </div>
                        <div className="mt-4 border-t border-gray-200 divide-y divide-gray-200">
                            <Toggle
                                label="SLA Expiring"
                                description="List of tickets expiring in the next 24 hours."
                                enabled={preferences.sla_expiring}
                                onChange={(val) => saveSettings(digestEnabled, { ...preferences, sla_expiring: val })}
                            />
                            <Toggle
                                label="Rejected Tickets"
                                description="List of tickets rejected in the last 24 hours."
                                enabled={preferences.rejected_24h}
                                onChange={(val) => saveSettings(digestEnabled, { ...preferences, rejected_24h: val })}
                            />
                            <Toggle
                                label="New Tickets"
                                description="List of tickets created in the last 24 hours."
                                enabled={preferences.created_24h}
                                onChange={(val) => saveSettings(digestEnabled, { ...preferences, created_24h: val })}
                            />
                        </div>
                    </div>
                )}
            </div>
        </div>
    )
}
