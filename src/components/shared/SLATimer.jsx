import { differenceInMinutes } from 'date-fns'
import { toDate } from '../../utils/datetime'

/*
 * Optimised SLA Timer
 * Does NOT maintain internal state. Relies on parent to pass 'currentDate'.
 * This allows the parent to control the update frequency (e.g. 1 min)
 * for 1000s of rows efficiently.
 *
 * targetDate used to arrive as a bare `date` like "2026-08-20", and `new Date()` parses
 * that as UTC midnight — 05:30 IST. The countdown was aiming at half past five in the
 * morning, an instant nobody chose. Deadlines are timestamptz now (MAIN-45) and toDate()
 * handles either form.
 */
export default function SLATimer({ targetDate, currentDate }) {
    if (!targetDate || !currentDate) return null

    const target = toDate(targetDate)
    if (!target) return null

    const diffMinutes = differenceInMinutes(target, currentDate)

    const isOverdue = diffMinutes < 0
    const absMinutes = Math.abs(diffMinutes)

    const days = Math.floor(absMinutes / (60 * 24))
    const hours = Math.floor((absMinutes % (60 * 24)) / 60)
    const minutes = absMinutes % 60

    // Colors
    let color = 'blue'
    if (isOverdue) color = 'red'
    else if (days < 2) color = 'orange' // Warning

    return (
        <div className="flex items-end gap-1" title={isOverdue ? `Overdue by ${days} days` : `Due in ${days} days`}>
            {isOverdue && <span className="text-sm font-bold text-red-600 mr-1 mb-0.5">⚠️</span>}

            <TimeUnit value={days} label="d" color={color} />
            <span className={`text-xs font-bold mb-1 ${color === 'red' ? 'text-red-300' : 'text-gray-300'}`}>:</span>
            <TimeUnit value={hours} label="h" color={color} />
            <span className={`text-xs font-bold mb-1 ${color === 'red' ? 'text-red-300' : 'text-gray-300'}`}>:</span>
            <TimeUnit value={minutes} label="m" color={color} />
        </div>
    )
}

function TimeUnit({ value, label, color }) {
    const colorClasses = {
        blue: 'bg-blue-50 text-blue-700 border-blue-200',
        red: 'bg-red-50 text-red-700 border-red-200',
        orange: 'bg-orange-50 text-orange-700 border-orange-200',
    }

    return (
        <div className="flex flex-col items-center">
            <div className={`
                min-w-[24px] h-6 px-1 rounded border flex items-center justify-center 
                text-xs font-bold shadow-sm ${colorClasses[color]}
            `}>
                {value}
            </div>
            <span className="text-[10px] text-gray-500 font-medium leading-none mt-0.5 uppercase tracking-wider">{label}</span>
        </div>
    )
}
