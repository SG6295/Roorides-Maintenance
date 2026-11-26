import { useEffect, useId, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { InformationCircleIcon } from '@heroicons/react/24/outline'

const BOX_WIDTH = 288 // w-72
const GAP = 6

/**
 * An ⓘ that shows how a figure was worked out (MAIN-164). It opens on hover, on tap or
 * click (which keeps it open until tapped again or Esc), and on keyboard focus, and is
 * announced as the button's description.
 *
 * The box is drawn on top of the page (a portal, fixed position) so a sideways-scrolling
 * chart or table can't clip it; it sits under its trigger, or above it near the bottom of
 * the screen, and is kept inside the window.
 *
 * `children` replaces the icon when the figure itself should be the trigger;
 * `triggerClassName` sizes that trigger (a chart bar needs `w-full`), and `triggerLabel`
 * names it for screen readers when it has no text of its own (a chart bar).
 */
export default function FormulaTip({ text, title = 'How this was worked out', label = 'How this was worked out', align = 'right', children, className = '', triggerClassName = '', triggerLabel }) {
    const [hover, setHover] = useState(false)
    const [pinned, setPinned] = useState(false)
    const [pos, setPos] = useState(null)
    const id = useId()
    const ref = useRef(null)
    const boxRef = useRef(null)
    const open = hover || pinned

    useEffect(() => {
        if (!pinned) return
        const onDown = e => {
            if (ref.current?.contains(e.target) || boxRef.current?.contains(e.target)) return
            setPinned(false)
        }
        document.addEventListener('mousedown', onDown)
        return () => document.removeEventListener('mousedown', onDown)
    }, [pinned])

    // Place the box against its trigger; follow scrolling while it is open.
    useLayoutEffect(() => {
        if (!open) return
        const place = () => {
            const r = ref.current?.getBoundingClientRect()
            if (!r) return
            const width = Math.min(BOX_WIDTH, window.innerWidth * 0.8)
            let left = align === 'left' ? r.left : r.right - width
            left = Math.max(8, Math.min(left, window.innerWidth - width - 8))
            const boxHeight = boxRef.current?.offsetHeight ?? 120
            const below = r.bottom + GAP
            const top = below + boxHeight > window.innerHeight - 8 && r.top - GAP - boxHeight > 8
                ? r.top - GAP - boxHeight
                : below
            setPos({ top, left, width })
        }
        place()
        window.addEventListener('scroll', place, true)
        window.addEventListener('resize', place)
        return () => {
            window.removeEventListener('scroll', place, true)
            window.removeEventListener('resize', place)
        }
    }, [open, align, text])

    if (!text) return children ?? null

    return (
        <span
            ref={ref}
            className={`relative inline-flex ${className}`}
            onMouseEnter={() => setHover(true)}
            onMouseLeave={() => setHover(false)}
        >
            <button
                type="button"
                aria-label={children ? triggerLabel : label}
                aria-describedby={open ? id : undefined}
                aria-expanded={open}
                onClick={() => setPinned(p => !p)}
                onFocus={() => setHover(true)}
                onBlur={() => setHover(false)}
                onKeyDown={e => { if (e.key === 'Escape') { setPinned(false); setHover(false) } }}
                className={children
                    ? `text-left rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 ${triggerClassName}`
                    : `p-1 rounded-full focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 ${open ? 'bg-blue-100 text-blue-700' : 'text-gray-500 hover:text-gray-700'}`}
            >
                {children ?? <InformationCircleIcon className="h-4 w-4" aria-hidden="true" />}
            </button>
            {open && createPortal(
                <span
                    ref={boxRef}
                    id={id}
                    role="tooltip"
                    style={pos ? { top: pos.top, left: pos.left, width: pos.width } : { visibility: 'hidden' }}
                    className="fixed z-50 block rounded-lg bg-gray-900 px-3.5 py-3 text-xs leading-relaxed text-gray-50 shadow-lg whitespace-normal font-normal normal-case tracking-normal text-left"
                >
                    <span className="block font-semibold mb-1">{title}</span>
                    {text}
                </span>,
                document.body
            )}
        </span>
    )
}
