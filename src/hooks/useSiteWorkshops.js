import { useMemo } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useWorkshopLocations } from './useWorkshopLocations'

/**
 * Workshop hub mapping (MAIN-131) — the workshop that serves each site.
 * One row per assigned site; no row means "Not assigned".
 *
 * Only super admins can write (enforced by RLS); everyone signed in can read.
 */
export function useSiteWorkshops() {
    return useQuery({
        queryKey: ['site_workshops'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('site_workshops')
                .select('site_id, location_id')
            if (error) throw error
            return data || []
        },
    })
}

/** `locationId` null unassigns the site, which deletes its row. */
export function useSetSiteWorkshop() {
    const queryClient = useQueryClient()
    return useMutation({
        mutationFn: async ({ siteId, locationId }) => {
            const { error } = locationId
                ? await supabase
                    .from('site_workshops')
                    .upsert({ site_id: siteId, location_id: locationId, updated_at: new Date().toISOString() })
                : await supabase
                    .from('site_workshops')
                    .delete()
                    .eq('site_id', siteId)
            if (error) throw error
        },
        onSuccess: () => queryClient.invalidateQueries({ queryKey: ['site_workshops'] }),
    })
}

/**
 * The workshop rows for an Analytics site filter: one group per active workshop,
 * holding the names of the sites mapped to it. A group only ticks sites — the
 * filter's value stays a list of site names, so the reports need no change.
 */
export function useWorkshopSiteGroups(sites) {
    const { data: locations = [] } = useWorkshopLocations()
    const { data: mapping = [] } = useSiteWorkshops()

    return useMemo(() => {
        const nameById = new Map(sites.map(s => [s.id, s.name]))
        return locations.map(location => {
            const values = mapping
                .filter(m => m.location_id === location.id && nameById.has(m.site_id))
                .map(m => nameById.get(m.site_id))
            return { key: location.id, label: location.name, values }
        })
    }, [sites, locations, mapping])
}
