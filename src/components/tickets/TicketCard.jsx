import { useState } from 'react'
import { Link } from 'react-router-dom'
import { format, differenceInDays, addDays, isWeekend, isSameDay } from 'date-fns'
import SLATimer from '../shared/SLATimer'
import TicketRating from './TicketRating'
import { logAuditEvent } from '../../utils/auditLogger'
import { useAuth } from '../../hooks/useAuth'
import { supabase } from '../../lib/supabase'

export default function TicketCard({ ticket, currentDate, assignmentSLADays = 1, onUpdate }) {
    const { user } = useAuth()
    const [isRating, setIsRating] = useState(false)

    // Compute assignment deadline for New/Pending tickets
    let assignmentDeadline = null
    if (ticket.status === 'Pending' || ticket.status === 'New') {
        assignmentDeadline = addDays(new Date(ticket.created_at), assignmentSLADays)
    }

    const handleRate = async (rating) => {
        if (user?.id !== ticket.created_by_user_id) {
            alert('Only the ticket creator can provide a rating.')
            return
        }

        setIsRating(true)
        try {
            const { error } = await supabase
                .from('tickets')
                .update({
                    rating,
                    rated_at: new Date().toISOString()
                })
                .eq('id', ticket.id)
            // Double check RLS or backend constraint if redundant
            // .eq('created_by_user_id', user.id) 

            if (error) throw error

            // Log to Audit History
            await logAuditEvent(
                ticket.id,
                'tickets',
                'UPDATE',
                user.id,
                {
                    oldData: { rating: ticket.rating || 'none' },
                    newData: { rating: rating },
                    changedFields: ['rating', 'rated_at']
                }
            )

            if (onUpdate) onUpdate()
        } catch (err) {
            console.error('Error rating ticket:', err)
            alert('Failed to save rating')
        } finally {
            setIsRating(false)
        }
    }

    return (
        <Link
            to={`/tickets/${ticket.id}`}
            className="block bg-white rounded-lg shadow border border-gray-200 card-hover p-4 sm:p-5 active:scale-[0.99] transition-transform relative"
        >
            {/* SLA Badge/Timer/Rating - Absolute Top Right */}
            <div className="absolute top-4 right-4" onClick={(e) => e.preventDefault()}>
                <SLABadge
                    ticket={ticket}
                    currentDate={currentDate}
                    assignmentDeadline={assignmentDeadline}
                    interactions={{
                        isCreator: user?.id === ticket.created_by_user_id,
                        onRate: handleRate,
                        isRating: isRating
                    }}
                />
            </div>

            <div className="flex flex-col sm:flex-row justify-between items-start gap-4 mb-3">
                <div className="flex-1 min-w-0 pr-24 w-full"> {/* Increased padding for Rating component */}
                    <div className="flex items-center gap-2 mb-2 flex-wrap">
                        <span className="font-semibold text-gray-900 text-base">
                            #{ticket.ticket_number}
                        </span>
                        <StatusBadge status={ticket.status} />
                    </div>
                    <h3 className="text-lg font-semibold text-gray-900 mb-2">
                        {ticket.vehicle_number}
                    </h3>
                    <p className="text-sm text-gray-600 line-clamp-2 leading-relaxed">
                        {ticket.initial_remarks || ticket.complaint}
                    </p>
                </div>
            </div>

            <div className="flex flex-wrap gap-2 text-xs text-gray-600 mt-2 sm:mt-4 pt-3 border-t border-gray-200">
                <span className="bg-gray-100 px-2.5 py-1.5 rounded font-medium">
                    {ticket.site}
                </span>
                {ticket.impact && (
                    <span className={`px-2.5 py-1.5 rounded font-medium ${ticket.impact === 'Major'
                        ? 'bg-orange-100 text-orange-800'
                        : 'bg-blue-100 text-blue-800'
                        }`}>
                        {ticket.impact}
                    </span>
                )}
                <div className="ml-auto text-right">
                    <div className="text-gray-900 font-medium mb-0.5">
                        {ticket.supervisor_name}
                    </div>
                    <div className="text-gray-500">
                        {format(new Date(ticket.created_at), 'MMM d, yyyy h:mm a')}
                    </div>
                </div>
            </div>
        </Link>
    )
}

function StatusBadge({ status }) {
    const colors = {
        'New': 'bg-yellow-100 text-yellow-800',
        'Pending': 'bg-yellow-100 text-yellow-800', // Legacy
        'Accepted': 'bg-blue-100 text-blue-800',
        'Team Assigned': 'bg-blue-100 text-blue-800', // Legacy
        'Work in Progress': 'bg-purple-100 text-purple-800', // Note: TicketDetail uses 'Work In Progress' (Capital I), ensuring consistency
        'Work In Progress': 'bg-purple-100 text-purple-800',
        'Resolved': 'bg-green-100 text-green-800',
        'Completed': 'bg-green-100 text-green-800', // Legacy
        'Closed': 'bg-gray-100 text-gray-800',
        'Rejected': 'bg-red-100 text-red-800',
    }

    return (
        <span className={`text-xs px-2 py-0.5 rounded ${colors[status] || 'bg-gray-100 text-gray-800'}`}>
            {status}
        </span>
    )
}

function SLABadge({ ticket, currentDate, assignmentDeadline, interactions }) {
    // 1. Check Assignment SLA (New/Pending Tickets)
    if ((ticket.status === 'Pending' || ticket.status === 'New') && assignmentDeadline) {
        return <SLATimer targetDate={assignmentDeadline} currentDate={currentDate} />
    }

    // 2. Check Rating (Completed Tickets)
    if (ticket.status === 'Completed' || ticket.status === 'Closed') {
        const { isCreator, onRate, isRating } = interactions

        return (
            <TicketRating
                rating={ticket.rating}
                onRate={onRate}
                disabled={!isCreator}
                isUpdating={isRating}
            />
        )
    }

    // 3. Active Ticket Logic (Assigned/WIP) - Show SLA Timer
    if (ticket.sla_end_date) {
        return <SLATimer targetDate={ticket.sla_end_date} currentDate={currentDate} />
    }

    return null
}
