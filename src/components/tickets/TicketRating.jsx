import { useState } from 'react'
import { FaceSmileIcon as FaceSmileOutline, FaceFrownIcon as FaceFrownOutline } from '@heroicons/react/24/outline'
import { FaceSmileIcon as FaceSmileSolid, FaceFrownIcon as FaceFrownSolid } from '@heroicons/react/24/solid'
// Heroicons v2 doesn't have a specific "Neutral" face in outline/solid set that matches perfectly, 
// so we might use FaceSmile for Good, and maybe just a generic circle or create a custom SVG for neutral?
// Actually simpler: Use Emojis as requested (more expressive) or find closest icons.
// User specifically asked for "green happy smiley, yellow neutral smiley & red sad smiley".
// Let's use SVGs to ensure they look "pro" but colored.

const RatingIcon = ({ type, selected, onClick, disabled }) => {
    let colorClass = ''
    let Icon = null

    if (type === 'good') {
        colorClass = selected ? 'text-green-500' : 'text-gray-300 hover:text-green-400'
        Icon = selected ? FaceSmileSolid : FaceSmileOutline
    } else if (type === 'bad') {
        colorClass = selected ? 'text-red-500' : 'text-gray-300 hover:text-red-400'
        Icon = selected ? FaceFrownSolid : FaceFrownOutline
    } else {
        // Neutral - Custom SVG or reusable helper
        colorClass = selected ? 'text-yellow-500' : 'text-gray-300 hover:text-yellow-400'
        // Using FaceSmile but flat mouth for neutral if possible, or just standard "Minus" icon?
        // Let's use a custom SVG for neutral face to match the style
        Icon = ({ className }) => (
            <svg xmlns="http://www.w3.org/2000/svg" fill={selected ? "currentColor" : "none"} viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className={className}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M15.182 15.182a4.5 4.5 0 01-6.364 0M21 12a9 9 0 11-18 0 9 9 0 0118 0zM9.75 9.75c0 .414-.168.75-.375.75S9 10.164 9 9.75 9.168 9 9.375 9s.375.336.375.75zm6.75 0c0 .414-.168.75-.375.75s-.375-.336-.375-.75.168-.75.375-.75.375.336.375.75z" />
            </svg>
        )
        // Wait, the path above is for Smile. Let's make a straight mouth.
        Icon = ({ className }) => (
            <svg xmlns="http://www.w3.org/2000/svg" fill={selected ? "currentColor" : "none"} viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className={className}>
                <path strokeLinecap="round" strokeLinejoin="round" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 10h.01M15 10h.01" />
                <path strokeLinecap="round" strokeLinejoin="round" d="M9 15h6" />
            </svg>
        )
    }

    return (
        <button
            type="button"
            onClick={onClick}
            disabled={disabled}
            className={`transition-colors duration-200 ${colorClass} ${disabled ? 'cursor-default opacity-100' : 'cursor-pointer transform hover:scale-110'}`}
        >
            <Icon className="h-8 w-8 sm:h-10 sm:w-10" aria-hidden="true" />
        </button>
    )
}

export default function TicketRating({ rating, onRate, disabled, isUpdating }) {
    // If disabled and no rating, show text? Or just show empty icons?
    // User said: "Rating pending/ display a smiley"

    if (disabled && !rating) {
        return (
            <div className="flex items-center text-gray-400 text-sm italic">
                <span>Rating pending</span>
            </div>
        )
    }

    return (
        <div className="flex items-center space-x-4">
            <RatingIcon
                type="good"
                selected={rating === 'good'}
                onClick={() => !disabled && onRate('good')}
                disabled={disabled}
            />
            <RatingIcon
                type="ok"
                selected={rating === 'ok'}
                onClick={() => !disabled && onRate('ok')}
                disabled={disabled}
            />
            <RatingIcon
                type="bad"
                selected={rating === 'bad'}
                onClick={() => !disabled && onRate('bad')}
                disabled={disabled}
            />
            {isUpdating && <span className="text-xs text-gray-500 animate-pulse">Saving...</span>}
        </div>
    )
}
