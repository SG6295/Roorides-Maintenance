import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useAuth } from './useAuth'
import { fetchAllRows } from '../utils/fetchAllRows'
import { localDayRangeToUtc } from '../utils/datetime'

/**
 * Hook to fetch tickets based on user role
 *
 * `filters.dateRange` ({ start, end } as local "yyyy-MM-dd") is applied in the database.
 * It used to be applied in the browser, after the API had already cut the list to the
 * newest 1,000 tickets, so no date range could reach further back than that (MAIN-83).
 */
export function useTickets(filters = {}) {
  const { userProfile } = useAuth()

  return useQuery({
    queryKey: ['tickets', filters, userProfile?.id],
    // Keep the current list on screen while a new date range loads.
    placeholderData: keepPreviousData,
    queryFn: () => fetchAllRows(() => {
      let query = supabase
        .from('tickets')
        .select('*')
        .order('created_at', { ascending: false })
        .order('id')

      if (filters.dateRange) {
        const { from, to } = localDayRangeToUtc(filters.dateRange.start, filters.dateRange.end)
        query = query.gte('created_at', from).lt('created_at', to)
      }
      if (filters.site) {
        query = query.eq('site', filters.site)
      }
      if (filters.status) {
        query = query.eq('status', filters.status)
      }
      if (filters.vehicle_number) {
        query = query.ilike('vehicle_number', `%${filters.vehicle_number}%`)
      }

      return query
    }),
    enabled: !!userProfile,
  })
}

/**
 * Hook to fetch a single ticket by ID
 */
export function useTicket(ticketId) {
  return useQuery({
    queryKey: ['ticket', ticketId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('tickets')
        .select('*')
        .eq('id', ticketId)
        .single()

      if (error) throw error
      return data
    },
    enabled: !!ticketId,
  })
}

/**
 * Hook to create a new ticket
 */
export function useCreateTicket() {
  const queryClient = useQueryClient()
  const { userProfile } = useAuth()

  return useMutation({
    mutationFn: async (ticketData) => {
      const { data, error } = await supabase
        .from('tickets')
        .insert([
          {
            ...ticketData,
            created_by_user_id: userProfile.id,
          },
        ])
        .select()
        .single()

      if (error) throw error
      return data
    },
    onSuccess: () => {
      // Invalidate tickets list to refetch
      queryClient.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

/**
 * Hook to update a ticket
 */
export function useUpdateTicket() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: async ({ id, updates }) => {
      const { data, error } = await supabase
        .from('tickets')
        .update(updates)
        .eq('id', id)
        .select()
        .single()

      if (error) throw error
      return data
    },
    onSuccess: (data) => {
      // Invalidate both list and detail views
      queryClient.invalidateQueries({ queryKey: ['tickets'] })
      queryClient.invalidateQueries({ queryKey: ['ticket', data.id] })
    },
  })
}

// Sites are not fetched here. useActiveSites / useAllSites in hooks/useSites.js are
// the only sources — see the note there on why one shared ['sites'] key was a bug.

/**
 * Hook to fetch vehicles, optionally filtered by site via the vehicle_sites junction table.
 *
 * Inactive vehicles are returned, not filtered out — omitting them made a bus that is
 * out of service look identical to one that was never added (MAIN-67). The caller greys
 * them out and blocks selection; is_active is selected so it can tell them apart.
 *
 * Note the site branch inner-joins vehicle_sites, so a vehicle with no site link is
 * still invisible here regardless of its is_active value.
 */
export function useVehicles(site = null) {
  return useQuery({
    queryKey: ['vehicles', site],
    // registration_number is unique, so it is already a stable order for fetchAllRows.
    // `id` is selected only so fetchAllRows can de-duplicate.
    queryFn: () => fetchAllRows(() => {
      if (site) {
        return supabase
          .from('vehicles')
          .select('id, registration_number, make, model, is_active, vehicle_sites!inner(site_name)')
          .eq('vehicle_sites.site_name', site)
          .order('registration_number')
      }

      return supabase
        .from('vehicles')
        .select('id, registration_number, make, model, is_active')
        .order('registration_number')
    }),
  })
}
