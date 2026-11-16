import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

/**
 * SLA settings as versions (MAIN-136). The tables have SELECT policies only: every change
 * goes through apply_sla_change, after preview_sla_changes has shown what it would do.
 */

// The SLA functions raise { error_code, error_message } as JSON; show the message.
function readableError(error) {
    let parsed = null
    try { parsed = JSON.parse(error.message) } catch { /* not one of ours */ }
    return parsed?.error_message ? new Error(parsed.error_message) : error
}

const SEVERITY_ORDER = { Major: 0, Minor: 1 }

/**
 * Every version (cancelled ones too) with its Turnaround rows, newest first, and the
 * holiday calendar. `latest` is the newest non-cancelled version: what a draft starts from.
 */
export function useSLAConfig() {
    return useQuery({
        queryKey: ['sla_config'],
        queryFn: async () => {
            const [versionsRes, holidaysRes] = await Promise.all([
                supabase.from('sla_versions').select('*, turnaround:sla_version_turnaround(category, severity, sla_days)')
                    .order('version_number', { ascending: false }),
                supabase.from('holidays').select('*').order('date'),
            ])
            if (versionsRes.error) throw versionsRes.error
            if (holidaysRes.error) throw holidaysRes.error

            const versions = versionsRes.data.map(v => ({
                ...v,
                turnaround: [...v.turnaround].sort((a, b) =>
                    SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity] || a.category.localeCompare(b.category)),
            }))
            return {
                versions,
                latest: versions.find(v => !v.cancelled_at) ?? null,
                holidays: holidaysRes.data,
            }
        },
    })
}

/** Version numbers by id, for the ticket page. */
export function useSLAVersionNumbers() {
    return useQuery({
        queryKey: ['sla_version_numbers'],
        queryFn: async () => {
            const { data, error } = await supabase.from('sla_versions').select('id, version_number')
            if (error) throw error
            return Object.fromEntries(data.map(v => [v.id, v.version_number]))
        },
        staleTime: 5 * 60 * 1000,
    })
}

/** Holidays added and removed, newest first. Execs and super admins only (RLS). */
export function useSLAHolidayChanges() {
    return useQuery({
        queryKey: ['sla_holiday_changes'],
        queryFn: async () => {
            const { data, error } = await supabase.from('sla_holiday_changes').select('*')
                .order('performed_at', { ascending: false })
            if (error) throw error
            return data
        },
    })
}

/** What a draft would do; writes nothing. */
export function usePreviewSLAChanges(change, enabled) {
    return useQuery({
        queryKey: ['sla_preview', change],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('preview_sla_changes', { p_change: change })
            if (error) throw readableError(error)
            return data
        },
        enabled,
        staleTime: Infinity,
        retry: false,
    })
}

function useSLAMutation() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async (change) => {
            const { data, error } = await supabase.rpc('apply_sla_change', { p_change: change })
            if (error) throw readableError(error)
            return data
        },
        onSuccess: () => {
            // Holiday changes move deadlines and statuses on tickets and issues.
            for (const key of [['sla_config'], ['sla_version_numbers'], ['sla_holiday_changes'], ['tickets'], ['ticket'], ['issues']]) {
                queryClient.invalidateQueries({ queryKey: key })
            }
        },
    })
}

/** Saves a reviewed draft: a version and/or holiday changes, under one reason. */
export const useApplySLAChange = useSLAMutation

/** Cancels a scheduled version: mutate({ versionId, reason }). */
export function useCancelSLAVersion() {
    const mutation = useSLAMutation()
    return {
        ...mutation,
        mutate: ({ versionId, reason }, options) =>
            mutation.mutate({ action: 'cancel_version', version_id: versionId, reason }, options),
    }
}
