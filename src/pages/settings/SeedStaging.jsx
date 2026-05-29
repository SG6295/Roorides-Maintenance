import { useState } from 'react'
import { supabase } from '../../lib/supabase'

const CONFIRM_PHRASE = 'CONFIRM'

export default function SeedStaging() {
    const [confirmInput, setConfirmInput] = useState('')
    const [loading, setLoading] = useState(false)
    const [result, setResult] = useState(null)
    const [error, setError] = useState(null)

    const confirmed = confirmInput === CONFIRM_PHRASE

    const handleSeed = async () => {
        if (!confirmed) return
        setLoading(true)
        setResult(null)
        setError(null)

        const { data, error: fnError } = await supabase.functions.invoke('seed-staging-from-prod')

        setLoading(false)

        if (fnError) {
            setError(fnError.message)
            return
        }
        if (data?.error) {
            setError(data.error)
            return
        }

        setResult(data)
        setConfirmInput('')
    }

    return (
        <div>
            <div className="mb-6">
                <h2 className="text-2xl font-bold leading-7 text-gray-900 sm:text-3xl sm:tracking-tight">
                    Seed Staging from Production
                </h2>
                <p className="mt-1 text-sm text-gray-600">
                    Replace all staging data with a fresh copy of production. Only available in staging.
                </p>
            </div>

            {/* Warning banner */}
            <div className="rounded-md bg-red-50 border border-red-200 p-4 mb-6">
                <div className="flex">
                    <div className="ml-3">
                        <h3 className="text-sm font-semibold text-red-800">Destructive action</h3>
                        <div className="mt-1 text-sm text-red-700 space-y-1">
                            <p>This will <strong>permanently delete all staging data</strong> and replace it with production data.</p>
                            <p>All staging auth users will be recreated with the test password. Your own session will remain active.</p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Confirm + trigger */}
            <div className="space-y-4">
                <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                        Type <span className="font-mono font-bold">{CONFIRM_PHRASE}</span> to enable the button
                    </label>
                    <input
                        type="text"
                        value={confirmInput}
                        onChange={e => setConfirmInput(e.target.value)}
                        placeholder={CONFIRM_PHRASE}
                        disabled={loading}
                        className="block w-full max-w-xs rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-red-500 focus:ring-red-500 disabled:bg-gray-100"
                    />
                </div>

                <button
                    onClick={handleSeed}
                    disabled={!confirmed || loading}
                    className="inline-flex items-center px-4 py-2 rounded-md text-sm font-medium text-white bg-red-600 hover:bg-red-700 disabled:opacity-40 disabled:cursor-not-allowed"
                >
                    {loading ? 'Syncing…' : 'Seed Staging from Production'}
                </button>
            </div>

            {/* Error */}
            {error && (
                <div className="mt-6 rounded-md bg-red-50 border border-red-200 p-4">
                    <p className="text-sm font-medium text-red-800">Sync failed</p>
                    <p className="text-sm text-red-700 mt-1">{error}</p>
                </div>
            )}

            {/* Result */}
            {result && (
                <div className="mt-6 space-y-4">
                    {/* Summary */}
                    <div className="rounded-md bg-green-50 border border-green-200 p-4">
                        <p className="text-sm font-semibold text-green-800">Sync complete</p>
                        <div className="mt-1 text-sm text-green-700 space-y-0.5">
                            <p>{result.summary.total_rows_copied.toLocaleString()} rows copied across {result.summary.tables_ok} tables in {(result.summary.duration_ms / 1000).toFixed(1)}s</p>
                            {result.summary.tables_failed > 0 && (
                                <p className="text-amber-700">{result.summary.tables_failed} table(s) failed — see details below</p>
                            )}
                        </div>
                    </div>

                    {/* Auth summary */}
                    <div className="rounded-md bg-blue-50 border border-blue-200 p-4">
                        <p className="text-sm font-semibold text-blue-800">Auth users</p>
                        <p className="text-sm text-blue-700 mt-1">
                            {result.auth.users_copied} of {result.auth.users_found_in_prod} users copied.
                            Test password for all staging accounts: <span className="font-mono font-bold">{result.auth.test_password}</span>
                        </p>
                        {result.auth.errors?.length > 0 && (
                            <ul className="mt-2 text-sm text-amber-700 list-disc list-inside">
                                {result.auth.errors.map((e, i) => (
                                    <li key={i}>{e.email}: {e.error}</li>
                                ))}
                            </ul>
                        )}
                    </div>

                    {/* Per-table details */}
                    {result.summary.tables_failed > 0 && (
                        <div>
                            <p className="text-sm font-medium text-gray-700 mb-2">Failed tables</p>
                            <div className="rounded-md border border-red-200 divide-y divide-red-100">
                                {result.public.filter(t => t.status === 'error').map(t => (
                                    <div key={t.table} className="px-4 py-2 text-sm">
                                        <span className="font-mono font-medium text-red-700">{t.table}</span>
                                        <span className="text-red-600 ml-2">{t.error}</span>
                                    </div>
                                ))}
                            </div>
                        </div>
                    )}
                </div>
            )}
        </div>
    )
}
