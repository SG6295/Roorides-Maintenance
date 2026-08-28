import { useQuery, useMutation, useQueryClient, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export function useSuppliers(filters = {}) {
  return useQuery({
    queryKey: ['suppliers', filters],
    // A new search term is a new cache key with nothing in it. Without this the table
    // blanks to a spinner on every refetch; with it the previous rows stay put until
    // the new ones arrive. Pairs with useDebouncedValue at the call site.
    placeholderData: keepPreviousData,
    queryFn: async () => {
      let query = supabase
        .from('suppliers')
        .select('id, created_at, status, email, entity_name, entity_type, pan_number, nature_of_work, submitted_by, created_via')
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

// Minimal approved-supplier list for the outsource assignment dropdown.
// Keyed separately so Quick Add mutations can invalidate it precisely.
export function useApprovedSuppliers() {
  return useQuery({
    queryKey: ['suppliers', 'approved'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('id, entity_name, nature_of_work, owner_contact, created_via')
        .eq('status', 'approved')
        .order('entity_name')
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
      queryClient.invalidateQueries({ queryKey: ['suppliers', 'approved'] })
    },
  })
}

// Inserts a quick-add supplier row (approved, created_via='quick_add').
// Caller must provide created_by (user UUID) and submitted_by (user name/email)
// from the auth context — the hook doesn't read auth state itself.
// On success, invalidates the approved-suppliers dropdown cache.
export function useQuickAddSupplier() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async ({
      entity_name,
      owner_name,
      owner_contact,
      registered_office_address,
      nature_of_work,
      created_by,
      submitted_by,
    }) => {
      const { data, error } = await supabase
        .from('suppliers')
        .insert([{
          entity_name,
          owner_name,
          owner_contact,
          registered_office_address,
          nature_of_work,
          status: 'approved',
          created_via: 'quick_add',
          created_by,
          submitted_by,
        }])
        .select('id, entity_name, nature_of_work, owner_contact, created_via')
        .single()
      if (error) throw error
      return data
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['suppliers'] })
    },
  })
}

// Callable by anonymous users via security-definer RPC
export async function checkPanExists(pan) {
  const { data, error } = await supabase.rpc('check_pan_exists', { p_pan: pan })
  if (error) throw error
  return data // boolean
}
