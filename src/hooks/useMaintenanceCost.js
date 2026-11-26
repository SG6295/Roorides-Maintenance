import { useQuery, keepPreviousData } from '@tanstack/react-query'
import { supabase } from '../lib/supabase'
import { linesFromResponse } from '../utils/maintenanceCost'

/**
 * Maintenance cost lines (MAIN-164) for a period, optionally one vehicle. The database
 * returns them in one compact response (get_maintenance_cost) — the fleet has ~12,000
 * lines, more than the API's 1,000-row pages. Exec, super_admin and finance only.
 * All arithmetic is in src/utils/maintenanceCost.js.
 */
export function useMaintenanceCost({ start, end, vehicle = null } = {}, { enabled = true } = {}) {
    return useQuery({
        queryKey: ['maintenance_cost', start, end, vehicle],
        queryFn: async () => {
            const { data, error } = await supabase.rpc('get_maintenance_cost', {
                p_filters: { from: start, to: end, ...(vehicle ? { vehicle } : {}) },
            })
            if (error) throw error
            return linesFromResponse(data)
        },
        enabled: enabled && !!start && !!end,
        placeholderData: keepPreviousData,
        staleTime: 5 * 60 * 1000,
    })
}

/** The vehicle itself: company, make/model, year, status and the sites it is linked to. */
export function useVehicleByRegistration(registration) {
    return useQuery({
        queryKey: ['vehicle_by_registration', registration],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('vehicles')
                .select('id, registration_number, make, model, year, is_active, company, vehicle_sites(site_name)')
                .eq('registration_number', registration)
                .maybeSingle()
            if (error) throw error
            return data
        },
        enabled: !!registration,
    })
}

/**
 * Every job card of a vehicle with everything its work history row shows — tickets,
 * issues, labour per technician, spares with their cost and any transfer, the
 * outsourced invoice and the odometer — so nothing has to be opened to be seen.
 */
export function useVehicleWorkHistory(registration) {
    return useQuery({
        queryKey: ['vehicle_work_history', registration],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('job_cards')
                .select(`
                    id, job_card_number, created_at, completed_at, status, type, site, odometer,
                    value:job_card_value,
                    location:location_id(name),
                    supplier:supplier_id(entity_name),
                    invoice:outsource_invoices(invoice_no, approved_amount, finance_payment_status, date_of_activity),
                    issues(
                        id, description, category, status, labour_hours, created_at,
                        ticket:ticket_id(ticket_number),
                        issue_labour(id, hours, technician:technician_id(id, name, employee_id)),
                        issue_parts(id, quantity_used, added_at, cost:spare_cost, transfer:spare_transfer, part:part_id(name, unit))
                    )
                `)
                .eq('vehicle_number', registration)
                .order('created_at', { ascending: false })
            if (error) throw error
            return data || []
        },
        enabled: !!registration,
    })
}

/** The vehicle's tickets, with whether each reached a job card. */
export function useVehicleTickets(registration) {
    return useQuery({
        queryKey: ['vehicle_tickets', registration],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('tickets')
                .select('id, ticket_number, created_at, status, issues(job_card_id)')
                .eq('vehicle_number', registration)
            if (error) throw error
            return data || []
        },
        enabled: !!registration,
    })
}
