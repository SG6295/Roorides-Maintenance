import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import Navigation from '../components/shared/Navigation'
import { useAuth } from '../hooks/useAuth'

export default function SLASettings({ embedded = false }) {
    const { userProfile } = useAuth()
    const [rules, setRules] = useState([])
    const [assignmentSLA, setAssignmentSLA] = useState(1)
    const [weeklyOffs, setWeeklyOffs] = useState([])
    const [holidays, setHolidays] = useState([])
    const [newHolidayDate, setNewHolidayDate] = useState('')
    const [newHolidayDesc, setNewHolidayDesc] = useState('')
    const [loading, setLoading] = useState(true)
    const [message, setMessage] = useState(null)

    useEffect(() => {
        fetchData()
    }, [])

    const fetchData = async () => {
        setLoading(true)
        try {
            const [rulesRes, settingsRes, offsRes, holidaysRes] = await Promise.all([
                supabase.from('sla_rules').select('*').order('impact').order('category'),
                supabase.from('system_settings').select('value').eq('key', 'assignment_sla_days').single(),
                supabase.from('system_settings').select('value').eq('key', 'sla_weekly_offs').single(),
                supabase.from('holidays').select('*').order('date')
            ])

            if (rulesRes.error) throw rulesRes.error
            setRules(rulesRes.data)

            if (settingsRes.data) setAssignmentSLA(parseInt(settingsRes.data.value))
            if (offsRes.data) setWeeklyOffs(JSON.parse(offsRes.data.value))
            if (holidaysRes.data) setHolidays(holidaysRes.data)

        } catch (err) {
            console.error('Error fetching data:', err)
        } finally {
            setLoading(false)
        }
    }

    const handleSettingChange = async (newVal) => {
        setAssignmentSLA(newVal)
        try {
            const { error } = await supabase
                .from('system_settings')
                .update({ value: newVal.toString() })
                .eq('key', 'assignment_sla_days')

            if (error) throw error
            setMessage({ type: 'success', text: 'Setting saved!' })
            setTimeout(() => setMessage(null), 2000)
        } catch (err) {
            console.error('Error updating setting:', err)
            setMessage({ type: 'error', text: 'Failed to save setting' })
        }
    }

    const toggleWeeklyOff = async (dayIndex) => {
        const newOffs = weeklyOffs.includes(dayIndex)
            ? weeklyOffs.filter(d => d !== dayIndex)
            : [...weeklyOffs, dayIndex].sort()

        setWeeklyOffs(newOffs)
        try {
            await supabase.from('system_settings').upsert({ key: 'sla_weekly_offs', value: JSON.stringify(newOffs) })
            // Silent success or optional toast
        } catch (err) {
            console.error('Error saving weekly offs', err)
        }
    }

    const addHoliday = async (e) => {
        e.preventDefault()
        if (!newHolidayDate) return

        try {
            const { data, error } = await supabase
                .from('holidays')
                .insert({ date: newHolidayDate, description: newHolidayDesc })
                .select()
                .single()

            if (error) throw error
            setHolidays([...holidays, data].sort((a, b) => new Date(a.date) - new Date(b.date)))
            setNewHolidayDate('')
            setNewHolidayDesc('')
            setMessage({ type: 'success', text: 'Holiday added!' })
            setTimeout(() => setMessage(null), 2000)
        } catch (err) {
            console.error(err)
            setMessage({ type: 'error', text: 'Failed to add holiday' })
        }
    }

    const deleteHoliday = async (id) => {
        try {
            await supabase.from('holidays').delete().eq('id', id)
            setHolidays(holidays.filter(h => h.id !== id))
        } catch (err) {
            console.error(err)
        }
    }

    const handleDayChange = async (id, newDays) => {
        // Optimistic update
        setRules(rules.map(r => r.id === id ? { ...r, days: parseInt(newDays) } : r))

        try {
            const { error } = await supabase
                .from('sla_rules')
                .update({ days: parseInt(newDays) })
                .eq('id', id)

            if (error) throw error
            setMessage({ type: 'success', text: 'Saved!' })
            setTimeout(() => setMessage(null), 2000)
        } catch (err) {
            console.error('Error updating rule:', err)
            setMessage({ type: 'error', text: 'Failed to save' })
            // Revert on error would go here
        }
    }

    const canEdit = userProfile?.role === 'super_admin'
    const canView = canEdit || userProfile?.role === 'maintenance_exec'

    if (!canView) {
        return (
            <div className="min-h-screen bg-gray-50 flex items-center justify-center">
                <p className="text-gray-600">Access Restricted</p>
            </div>
        )
    }

    return (
        <div className={embedded ? "" : "min-h-screen bg-gray-50"}>
            {!embedded && (
                <Navigation breadcrumbs={[{ label: 'Dashboard', href: '/dashboard' }, { label: 'SLA Settings' }]} />
            )}

            <div className={embedded ? "" : "max-w-4xl mx-auto px-4 py-8"}>
                <div className="flex items-center justify-between mb-6">
                    <h1 className="text-2xl font-bold text-gray-900">SLA Configuration</h1>
                    {!canEdit && (
                        <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                            View only — contact Super Admin to make changes
                        </span>
                    )}
                </div>

                {message && (
                    <div className={`fixed bottom-4 right-4 px-6 py-3 rounded shadow-lg z-50 transition-opacity duration-300 ${message.type === 'success' ? 'bg-green-100 text-green-800 border border-green-200' : 'bg-red-100 text-red-800 border border-red-200'
                        }`}>
                        {message.text}
                    </div>
                )}

                {/* Global Settings Section */}
                <div className="bg-white rounded-lg shadow p-6 mb-8 space-y-8">
                    <h2 className="text-lg font-medium text-gray-900 border-b pb-2">Global Settings</h2>

                    {/* Assignment SLA */}
                    <div className="flex items-center justify-between max-w-lg">
                        <div>
                            <label className="block text-sm font-medium text-gray-700">Assignment SLA Threshold</label>
                            <p className="text-xs text-gray-600">Max days to assign a ticket before violation</p>
                        </div>
                        <div className="flex items-center">
                            <input
                                type="number"
                                min="1"
                                value={assignmentSLA}
                                onChange={(e) => canEdit && handleSettingChange(e.target.value)}
                                readOnly={!canEdit}
                                className={`w-20 px-3 py-2 border border-gray-300 rounded-md shadow-sm sm:text-sm ${canEdit ? 'focus:ring-blue-500 focus:border-blue-500' : 'bg-gray-50 cursor-default'}`}
                            />
                            <span className="ml-2 text-sm text-gray-600">days</span>
                        </div>
                    </div>

                    {/* Weekly Offs */}
                    <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">Weekly Offs</label>
                        <p className="text-xs text-gray-600 mb-3">SLA calculations will skip these days.</p>
                        <div className="flex gap-4 flex-wrap">
                            {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((day, index) => (
                                <label key={day} className={`inline-flex items-center ${!canEdit ? 'cursor-default' : ''}`}>
                                    <input
                                        type="checkbox"
                                        checked={weeklyOffs.includes(index)}
                                        onChange={() => canEdit && toggleWeeklyOff(index)}
                                        disabled={!canEdit}
                                        className="rounded border-gray-300 text-blue-600 shadow-sm focus:border-blue-300 focus:ring focus:ring-blue-200 focus:ring-opacity-50 disabled:opacity-60"
                                    />
                                    <span className="ml-2 text-sm text-gray-700">{day}</span>
                                </label>
                            ))}
                        </div>
                    </div>

                    {/* Holidays */}
                    <div>
                        <label className="block text-sm font-medium text-gray-700 mb-2">Holidays</label>
                        <p className="text-xs text-gray-600 mb-3">Add specific dates to exclude from SLA.</p>

                        <form onSubmit={canEdit ? addHoliday : (e) => e.preventDefault()} className="flex gap-2 mb-4 max-w-lg">
                            <input
                                type="date"
                                required
                                disabled={!canEdit}
                                value={newHolidayDate}
                                onChange={e => setNewHolidayDate(e.target.value)}
                                className="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm disabled:bg-gray-50 disabled:opacity-60"
                            />
                            <input
                                type="text"
                                placeholder="Description (e.g. Republic Day)"
                                disabled={!canEdit}
                                value={newHolidayDesc}
                                onChange={e => setNewHolidayDesc(e.target.value)}
                                className="flex-1 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm disabled:bg-gray-50 disabled:opacity-60"
                            />
                            {canEdit && (
                                <button
                                    type="submit"
                                    className="bg-blue-600 text-white px-3 py-2 rounded-md hover:bg-blue-700 text-sm"
                                >
                                    Add
                                </button>
                            )}
                        </form>

                        <div className="bg-gray-50 rounded border border-gray-300 max-h-48 overflow-y-auto max-w-lg">
                            {holidays.length === 0 ? (
                                <p className="text-sm text-gray-600 p-4 text-center">No holidays added.</p>
                            ) : (
                                <table className="min-w-full divide-y divide-gray-200">
                                    <tbody className="bg-white divide-y divide-gray-200">
                                        {holidays.map(h => (
                                            <tr key={h.id}>
                                                <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-900">{h.date}</td>
                                                <td className="px-4 py-2 whitespace-nowrap text-sm text-gray-600">{h.description}</td>
                                                <td className="px-4 py-2 whitespace-nowrap text-right text-sm font-medium">
                                                    {canEdit && (
                                                        <button onClick={() => deleteHoliday(h.id)} className="text-red-600 hover:text-red-900">Delete</button>
                                                    )}
                                                </td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            )}
                        </div>
                    </div>
                </div>

                <div className="bg-white rounded-lg shadow overflow-hidden">
                    <table className="min-w-full divide-y divide-gray-200">
                        <thead className="bg-gray-50">
                            <tr>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Impact
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    Category
                                </th>
                                <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">
                                    SLA Days
                                </th>
                            </tr>
                        </thead>
                        <tbody className="bg-white divide-y divide-gray-200">
                            {loading ? (
                                <tr><td colSpan="3" className="px-6 py-4 text-center">Loading...</td></tr>
                            ) : rules.map((rule) => (
                                <tr key={rule.id}>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <span className={`px-2 py-1 rounded-full text-xs font-medium ${rule.impact === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-blue-100 text-blue-800'
                                            }`}>
                                            {rule.impact}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                                        {rule.category}
                                    </td>
                                    <td className="px-6 py-4 whitespace-nowrap">
                                        <input
                                            type="number"
                                            min="1"
                                            readOnly={!canEdit}
                                            className={`w-20 px-2 py-1 border border-gray-300 rounded ${canEdit ? 'focus:ring-blue-500 focus:border-blue-500' : 'bg-gray-50 cursor-default'}`}
                                            value={rule.days}
                                            onChange={(e) => canEdit && handleDayChange(rule.id, e.target.value)}
                                        />
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    )
}
