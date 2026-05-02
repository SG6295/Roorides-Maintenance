import { Link } from 'react-router-dom'
import { format, addDays } from 'date-fns'
import SLATimer from '../shared/SLATimer'

// Supabase returns timestamptz without 'Z', causing JS to parse as local time instead of UTC.
// Appending 'Z' forces correct UTC interpretation.
const parseUTC = (ts) => ts ? new Date(ts.endsWith('Z') || ts.includes('+') ? ts : ts + 'Z') : null

export default function TicketCard({ ticket, currentDate, acceptanceSLADays = 1 }) {
    let acceptanceDeadline = null
    if (ticket.status === 'Pending' || ticket.status === 'New') {
        acceptanceDeadline = addDays(parseUTC(ticket.created_at), acceptanceSLADays)
    }

    return (
        <Link
            to={`/tickets/${ticket.id}`}
            className="block bg-white rounded-lg shadow border border-gray-200 card-hover p-4 sm:p-5 active:scale-[0.99] transition-transform relative"
        >
            {/* SLA Timer - Absolute Top Right */}
            <div className="absolute top-4 right-4">
                <SLABadge
                    ticket={ticket}
                    currentDate={currentDate}
                    acceptanceDeadline={acceptanceDeadline}
                />
            </div>

            <div className="flex flex-col sm:flex-row justify-between items-start gap-4 mb-3">
                <div className="flex-1 min-w-0 pr-24 w-full">
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
                <div className="ml-auto text-right">
                    <div className="text-gray-900 font-medium mb-0.5">
                        {ticket.supervisor_name}
                    </div>
                    <div className="text-gray-500">
                        {format(parseUTC(ticket.created_at), 'MMM d, yyyy h:mm a')}
                    </div>
                </div>
            </div>
        </Link>
    )
}

function StatusBadge({ status }) {
    const colors = {
        'New': 'bg-yellow-100 text-yellow-800',
        'Accepted': 'bg-blue-100 text-blue-800',
        'Work In Progress': 'bg-purple-100 text-purple-800',
        'Resolved': 'bg-green-100 text-green-800',
        'Closed': 'bg-gray-100 text-gray-800',
        'Rejected': 'bg-red-100 text-red-800',
    }

    return (
        <span className={`text-xs px-2 py-0.5 rounded ${colors[status] || 'bg-gray-100 text-gray-800'}`}>
            {status}
        </span>
    )
}

function SLABadge({ ticket, currentDate, acceptanceDeadline }) {
    if ((ticket.status === 'Pending' || ticket.status === 'New') && acceptanceDeadline) {
        return <SLATimer targetDate={acceptanceDeadline} currentDate={currentDate} />
    }

    if (ticket.final_sla_end_date) {
        return <SLATimer targetDate={ticket.final_sla_end_date} currentDate={currentDate} />
    }

    return null
}
