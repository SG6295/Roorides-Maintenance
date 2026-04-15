import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useSuppliers(filters = {}) {
  return useQuery({
    queryKey: ['suppliers', filters],
    queryFn: async () => {
      let query = supabase
        .from('suppliers')
        .select('id, created_at, status, email, entity_name, entity_type, pan_number, nature_of_work, submitted_by')
        .order('created_at', { ascending: false })

      if (filters.status) {
        query = query.eq('status', filters.status)
      }
      if (filters.search) {
        query = query.or(
          `entity_name.ilike.%${filters.search}%,pan_number.ilike.%${filters.search}%,email.ilike.%${filters.search}%`
        )
      }

      const { data, error } = await query
      if (error) throw error
      return data || []
    },
  })
}

export function useSupplierById(id) {
  return useQuery({
    queryKey: ['supplier', id],
    enabled: !!id,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('*')
        .eq('id', id)
        .single()
      if (error) throw error
      return data
    },
  })
}

export function useRegisterSupplier() {
  return useMutation({
    mutationFn: async (supplierData) => {
      const { data, error } = await supabase
        .from('suppliers')
        .insert([supplierData])
        .select()
        .single()
      if (error) throw error
      return data
    },
  })
}

export function useUpdateSupplierStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, status }) => {
      const { data, error } = await supabase
        .from('suppliers')
        .update({ status })
        .eq('id', id)
        .select()
        .single()
      if (error) throw error
      return data
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] })
      queryClient.invalidateQueries({ queryKey: ['supplier', data.id] })
    },
  })
}

// Callable by anonymous users via security-definer RPC
export async function checkPanExists(pan) {
  const { data, error } = await supabase.rpc('check_pan_exists', { p_pan: pan })
  if (error) throw error
  return data // boolean
}
