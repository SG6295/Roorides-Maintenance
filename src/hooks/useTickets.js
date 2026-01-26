import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { useAuth } from './useAuth'

/**
 * Hook to fetch tickets based on user role
 */
export function useTickets(filters = {}) {
  const { userProfile } = useAuth()

  return useQuery({
    queryKey: ['tickets', filters, userProfile?.id],
    queryFn: async () => {
      let query = supabase
        .from('tickets')
        .select('*')
        .order('created_at', { ascending: false })




      // Apply filters
      if (filters.site) {
        query = query.eq('site', filters.site)
      }
      if (filters.status) {
        query = query.eq('status', filters.status)
      }
      if (filters.vehicle_number) {
        query = query.ilike('vehicle_number', `%${filters.vehicle_number}%`)
      }

      const { data, error } = await query

      if (error) throw error
      return data || []
    },
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

/**
 * Hook to fetch sites
 */
export function useSites() {
  return useQuery({
    queryKey: ['sites'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('sites')
        .select('*')
        .eq('is_active', true)
        .order('name')

      if (error) throw error
      return data || []
    },
  })
}

/**
 * Hook to fetch vehicles by site
 */
export function useVehicles(site = null) {
  return useQuery({
    queryKey: ['vehicles', site],
    queryFn: async () => {
      let query = supabase
        .from('vehicles')
        .select('*')
        .eq('is_active', true)
        .order('number')

      if (site) {
        query = query.eq('site', site)
      }

      const { data, error } = await query

      if (error) throw error
      return data || []
    },
  })
}
