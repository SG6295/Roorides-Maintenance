import { useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'

export class ScrapRPCError extends Error {
    constructor(payload) {
        super(payload.error_message || 'Scrap RPC error')
        this.name = 'ScrapRPCError'
        this.errorCode = payload.error_code
        this.details = payload.details
    }
}

export function useCloseJobCardWithScrap() {
    const queryClient = useQueryClient()

    return useMutation({
        mutationFn: async ({ jobCardId, remarks, scrapDecisions }) => {
            const { data, error } = await supabase.rpc('close_job_card_with_scrap', {
                p_job_card_id:     jobCardId,
                p_remarks:         remarks || null,
                p_scrap_decisions: scrapDecisions,
            })

            if (error) {
                // RAISE EXCEPTION puts JSON in error.message — try to parse it
                try {
                    const parsed = JSON.parse(error.message)
                    if (parsed.error_code) throw new ScrapRPCError(parsed)
                } catch (parseErr) {
                    if (parseErr instanceof ScrapRPCError) throw parseErr
                }
                throw error
            }

            return data
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['job_card'] })
            queryClient.invalidateQueries({ queryKey: ['job_cards'] })
        },
    })
}
