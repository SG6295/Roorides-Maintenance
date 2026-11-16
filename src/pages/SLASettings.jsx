import { useMemo, useState } from 'react'
import Navigation from '../components/shared/Navigation'
import ReviewSLAChangesModal from '../components/sla/ReviewSLAChangesModal'
import SLAVersionHistory from '../components/sla/SLAVersionHistory'
import { useAuth } from '../hooks/useAuth'
import { useSLAConfig, useSLAHolidayChanges } from '../hooks/useSLASettings'
import {
    DAY_NAMES, draftErrors, draftFromVersion, hasChanges, versionTimeline,
} from '../utils/slaDraft'
import { formatDate, formatDateTime, todayLocal } from '../utils/datetime'
import { ISSUE_CATEGORIES } from '../constants/issueCategories'

// A new version carries a Turnaround Time for the current categories only.
const currentTurnaround = (version) => version.turnaround.filter(r => ISSUE_CATEGORIES.includes(r.category))

/**
 * SLA Configuration (MAIN-136). Edits are a draft until Review changes → reason → Confirm;
 * nothing saves on its own. Acceptance SLA Threshold, Weekly Offs and Turnaround Time are
 * saved together as a new version; only super admins can change them. Holidays are not
 * versioned, and maintenance execs can change them too.
 */
export default function SLASettings({ embedded = false }) {
    const { userProfile } = useAuth()
    const { data: config, isLoading, error } = useSLAConfig()
    const [draft, setDraft] = useState(null)
    const [newHolidayDate, setNewHolidayDate] = useState('')
    const [newHolidayDesc, setNewHolidayDesc] = useState('')
    const [reviewing, setReviewing] = useState(false)
    const [message, setMessage] = useState(null)

    const canEdit = userProfile?.role === 'super_admin'
    const canView = canEdit || userProfile?.role === 'maintenance_exec'
    const canEditHolidays = canView

    const latest = config?.latest
    const latestTurnaround = useMemo(() => (latest ? currentTurnaround(latest) : []), [latest])
    const timeline = useMemo(() => (config ? versionTimeline(config.versions) : []), [config])
    const active = timeline.find(v => v.state === 'active')
    const scheduled = timeline.find(v => v.state === 'scheduled')

    // A fresh draft whenever the saved version changes (after a save or a cancel).
    const [draftBase, setDraftBase] = useState(null)
    if (latest && latest !== draftBase) {
        setDraftBase(latest)
        setDraft(draftFromVersion(latest, currentTurnaround(latest)))
    }

    if (!canView) {
        return (
            <div className="min-h-screen bg-gray-50 flex items-center justify-center">
                <p className="text-gray-600">Access Restricted</p>
            </div>
        )
    }

    const today = todayLocal()
    // While a version is scheduled, only holidays can change: the versioned settings show
    // the active version, read-only.
    const versionEditable = canEdit && !scheduled
    const shown = versionEditable ? draft : active && draftFromVersion(active, currentTurnaround(active))
    const dirty = !!(draft && latest && hasChanges(latest, latestTurnaround, draft))
    const errors = draft ? draftErrors(draft) : []

    const update = (patch) => setDraft(d => ({ ...d, ...patch }))
    const toggleWeeklyOff = (day) => update({
        weeklyOffs: draft.weeklyOffs.includes(day) ? draft.weeklyOffs.filter(d => d !== day) : [...draft.weeklyOffs, day].sort(),
    })
    const setTurnaround = (key, value) => update({ turnaround: { ...draft.turnaround, [key]: value } })

    const holidayTaken = (date) => config.holidays.some(h => h.date === date) || draft.holidaysAdd.some(h => h.date === date)
    const addHoliday = (e) => {
        e.preventDefault()
        if (!newHolidayDate || newHolidayDate < today) return
        if (draft.holidaysRemove.includes(newHolidayDate)) {
            update({ holidaysRemove: draft.holidaysRemove.filter(d => d !== newHolidayDate) })
        } else if (!holidayTaken(newHolidayDate)) {
            update({ holidaysAdd: [...draft.holidaysAdd, { date: newHolidayDate, description: newHolidayDesc.trim() }] })
        }
        setNewHolidayDate('')
        setNewHolidayDesc('')
    }
    const toggleRemoveHoliday = (date) => update({
        holidaysRemove: draft.holidaysRemove.includes(date)
            ? draft.holidaysRemove.filter(d => d !== date)
            : [...draft.holidaysRemove, date],
    })
    const dropNewHoliday = (date) => update({ holidaysAdd: draft.holidaysAdd.filter(h => h.date !== date) })

    const holidayRows = config && draft ? [
        ...config.holidays.map(h => ({ ...h, removing: draft.holidaysRemove.includes(h.date) })),
        ...draft.holidaysAdd.map(h => ({ ...h, id: `new-${h.date}`, adding: true })),
    ].sort((a, b) => a.date.localeCompare(b.date)) : []

    const onSaved = (result) => {
        setReviewing(false)
        // A new version also resets the draft when it loads; a holiday-only save doesn't
        // change the version, so start clean here.
        setDraft(draftFromVersion(latest, latestTurnaround))
        setMessage(result?.version_number
            ? `Saved as Version ${result.version_number}.`
            : 'Saved.')
        setTimeout(() => setMessage(null), 3000)
    }

    const inputClass = (editable) =>
        `w-20 px-3 py-2 border border-gray-300 rounded-md shadow-sm sm:text-sm ${editable ? 'focus:ring-blue-500 focus:border-blue-500' : 'bg-gray-50 cursor-default'}`

    return (
        <div className={embedded ? "" : "min-h-screen bg-gray-50"}>
            {!embedded && (
                <Navigation breadcrumbs={[{ label: 'Dashboard', href: '/dashboard' }, { label: 'SLA Settings' }]} />
            )}

            <div className={`${embedded ? "" : "max-w-4xl mx-auto px-4 py-8"} ${dirty ? 'pb-24' : ''}`}>
                <div className="flex flex-wrap items-center justify-between gap-2 mb-6">
                    <h1 className="text-2xl font-bold text-gray-900">SLA Configuration</h1>
                    {!canEdit && (
                        <span className="inline-flex items-center px-3 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                            You can change holidays — contact Super Admin for the other settings
                        </span>
                    )}
                </div>

                {message && (
                    <div className="fixed bottom-4 right-4 px-6 py-3 rounded shadow-lg z-50 bg-green-100 text-green-800 border border-green-200">
                        {message}
                    </div>
                )}

                {error && <p className="text-sm text-red-600 mb-4">Couldn't load the SLA settings: {error.message}</p>}

                {isLoading || !shown ? (
                    <p className="text-sm text-gray-600">Loading...</p>
                ) : (
                    <>
                        <div className="bg-white rounded-lg shadow p-6 mb-8 space-y-8">
                            <div className="border-b pb-2">
                                <h2 className="text-lg font-medium text-gray-900">
                                    {versionEditable ? 'Settings' : `Version ${active.version_number} (active)`}
                                </h2>
                                {active && (
                                    <p className="text-xs text-gray-600 mt-0.5">
                                        Version {active.version_number} is active since {formatDateTime(active.starts_at)}.
                                        Changing these settings saves a new version; existing tickets and issues keep theirs.
                                    </p>
                                )}
                            </div>

                            {scheduled && (
                                <p className="text-sm text-blue-800 bg-blue-50 border border-blue-200 rounded-lg p-3">
                                    Version {scheduled.version_number} is scheduled to start {formatDateTime(scheduled.starts_at)}.
                                    {canEdit && ' To change the settings, cancel it in the version history and save a new version. Holidays can still be changed.'}
                                </p>
                            )}

                            {/* Acceptance SLA */}
                            <div className="flex items-center justify-between max-w-lg">
                                <div>
                                    <label htmlFor="acceptance-sla" className="block text-sm font-medium text-gray-700">Acceptance SLA Threshold</label>
                                    <p className="text-xs text-gray-600">Max working days to assign a ticket before violation</p>
                                </div>
                                <div className="flex items-center">
                                    <input
                                        id="acceptance-sla"
                                        type="number"
                                        min="1"
                                        max="365"
                                        value={shown.acceptanceDays}
                                        onChange={(e) => versionEditable && update({ acceptanceDays: e.target.value })}
                                        readOnly={!versionEditable}
                                        className={inputClass(versionEditable)}
                                    />
                                    <span className="ml-2 text-sm text-gray-600">working days</span>
                                </div>
                            </div>

                            {/* Weekly Offs */}
                            <div>
                                <label className="block text-sm font-medium text-gray-700 mb-2">Weekly Offs</label>
                                <p className="text-xs text-gray-600 mb-3">All SLA deadlines skip these days.</p>
                                <div className="flex gap-4 flex-wrap">
                                    {DAY_NAMES.map((day, index) => (
                                        <label key={day} className={`inline-flex items-center ${!versionEditable ? 'cursor-default' : ''}`}>
                                            <input
                                                type="checkbox"
                                                checked={shown.weeklyOffs.includes(index)}
                                                onChange={() => versionEditable && toggleWeeklyOff(index)}
                                                disabled={!versionEditable}
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
                                <p className="text-xs text-gray-600 mb-3">
                                    Dates excluded from every SLA. Not versioned: a change moves the deadline of every ticket and
                                    issue whose deadline window covers the date. Only today or later can be added or removed.
                                </p>

                                {canEditHolidays && (
                                    <form onSubmit={addHoliday} className="flex flex-wrap gap-2 mb-4 max-w-lg">
                                        <input
                                            type="date"
                                            required
                                            min={today}
                                            aria-label="Holiday date"
                                            value={newHolidayDate}
                                            onChange={e => setNewHolidayDate(e.target.value)}
                                            className="rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                                        />
                                        <input
                                            type="text"
                                            placeholder="Description (e.g. Republic Day)"
                                            value={newHolidayDesc}
                                            onChange={e => setNewHolidayDesc(e.target.value)}
                                            className="flex-1 min-w-0 rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
                                        />
                                        <button type="submit" className="bg-blue-600 text-white px-3 py-2 rounded-md hover:bg-blue-700 text-sm">
                                            Add
                                        </button>
                                    </form>
                                )}

                                <div className="bg-gray-50 rounded border border-gray-300 max-h-48 overflow-y-auto max-w-lg">
                                    {holidayRows.length === 0 ? (
                                        <p className="text-sm text-gray-600 p-4 text-center">No holidays added.</p>
                                    ) : (
                                        <table className="min-w-full divide-y divide-gray-200">
                                            <tbody className="bg-white divide-y divide-gray-200">
                                                {holidayRows.map(h => (
                                                    <tr key={h.id} className={h.removing ? 'bg-red-50' : h.adding ? 'bg-green-50' : ''}>
                                                        <td className={`px-4 py-2 whitespace-nowrap text-sm text-gray-900 ${h.removing ? 'line-through' : ''}`}>{formatDate(h.date)}</td>
                                                        <td className={`px-4 py-2 text-sm text-gray-600 ${h.removing ? 'line-through' : ''}`}>
                                                            {h.description}
                                                            {h.adding && <span className="ml-2 text-xs text-green-700">Not saved</span>}
                                                        </td>
                                                        <td className="px-4 py-2 whitespace-nowrap text-right text-sm font-medium">
                                                            {canEditHolidays && h.adding && (
                                                                <button type="button" onClick={() => dropNewHoliday(h.date)} className="text-gray-600 hover:text-gray-900">Undo</button>
                                                            )}
                                                            {canEditHolidays && !h.adding && h.date >= today && (
                                                                <button type="button" onClick={() => toggleRemoveHoliday(h.date)} className={h.removing ? 'text-gray-600 hover:text-gray-900' : 'text-red-600 hover:text-red-900'}>
                                                                    {h.removing ? 'Undo' : 'Remove'}
                                                                </button>
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

                        <div className="bg-white rounded-lg shadow overflow-hidden mb-8">
                            <table className="min-w-full divide-y divide-gray-200">
                                <thead className="bg-gray-50">
                                    <tr>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Severity</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Category</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Turnaround Time (working days)</th>
                                    </tr>
                                </thead>
                                <tbody className="bg-white divide-y divide-gray-200">
                                    {currentTurnaround(versionEditable ? latest : active).map((rule) => {
                                        const key = `${rule.severity}|${rule.category}`
                                        return (
                                            <tr key={key}>
                                                <td className="px-6 py-4 whitespace-nowrap">
                                                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${rule.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-blue-100 text-blue-800'}`}>
                                                        {rule.severity}
                                                    </span>
                                                </td>
                                                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{rule.category}</td>
                                                <td className="px-6 py-4 whitespace-nowrap">
                                                    <input
                                                        type="number"
                                                        min="1"
                                                        max="365"
                                                        aria-label={`Turnaround Time, ${rule.severity} ${rule.category}`}
                                                        readOnly={!versionEditable}
                                                        className={inputClass(versionEditable)}
                                                        value={shown.turnaround[key]}
                                                        onChange={(e) => versionEditable && setTurnaround(key, e.target.value)}
                                                    />
                                                </td>
                                            </tr>
                                        )
                                    })}
                                </tbody>
                            </table>
                        </div>

                        <div className="mb-8">
                            <SLAVersionHistory versions={config.versions} canEdit={canEdit} />
                        </div>

                        <HolidayChangeLog />
                    </>
                )}
            </div>

            {canEditHolidays && dirty && (
                <div className="fixed inset-x-0 bottom-0 z-40 bg-white border-t shadow-lg">
                    <div className="max-w-4xl mx-auto px-4 py-3 flex flex-wrap items-center justify-between gap-3">
                        <div className="text-sm">
                            <p className="font-medium text-gray-900">Unsaved changes</p>
                            {errors.map(e => <p key={e} className="text-red-600">{e}</p>)}
                        </div>
                        <div className="flex gap-3">
                            <button
                                type="button"
                                onClick={() => setDraft(draftFromVersion(latest, latestTurnaround))}
                                className="px-4 py-2 text-sm text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50"
                            >
                                Discard
                            </button>
                            <button
                                type="button"
                                onClick={() => setReviewing(true)}
                                disabled={errors.length > 0}
                                className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                Review changes
                            </button>
                        </div>
                    </div>
                </div>
            )}

            {reviewing && (
                <ReviewSLAChangesModal
                    version={latest}
                    turnaround={latestTurnaround}
                    holidays={config.holidays}
                    draft={draft}
                    onClose={() => setReviewing(false)}
                    onSaved={onSaved}
                />
            )}
        </div>
    )
}

function HolidayChangeLog() {
    const { data: changes = [] } = useSLAHolidayChanges()
    if (changes.length === 0) return null
    return (
        <div className="bg-white rounded-lg shadow overflow-hidden">
            <h2 className="text-lg font-medium text-gray-900 px-6 pt-5 pb-3">Holiday changes</h2>
            <ul className="divide-y divide-gray-200 border-t border-gray-200">
                {changes.map(c => (
                    <li key={c.id} className="px-6 py-3 text-sm">
                        <p className="text-gray-900">
                            <span className={c.action === 'add' ? 'text-green-700 font-medium' : 'text-red-700 font-medium'}>
                                {c.action === 'add' ? 'Added' : 'Removed'}
                            </span>{' '}
                            {formatDate(c.holiday_date)}{c.description ? ` (${c.description})` : ''}
                        </p>
                        <p className="text-xs text-gray-600">
                            {c.performed_by_name ?? 'System'} on {formatDateTime(c.performed_at)}: {c.reason}
                        </p>
                    </li>
                ))}
            </ul>
        </div>
    )
}
