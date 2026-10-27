import { Popover, PopoverButton, PopoverPanel } from '@headlessui/react'
import { AdjustmentsHorizontalIcon } from '@heroicons/react/20/solid'
import { COLUMNS, DEFAULT_COLUMN_KEYS } from './columns'

/**
 * Show or hide list columns (MAIN-98). For trying column sets — nothing is saved,
 * and a reload returns to the default for everyone.
 */
export default function ColumnManager({ visibleKeys, onChange }) {
    const toggle = key =>
        onChange(visibleKeys.includes(key) ? visibleKeys.filter(k => k !== key) : [...visibleKeys, key])

    return (
        <Popover className="relative">
            <PopoverButton className="inline-flex items-center gap-1.5 text-sm px-3 py-1.5 text-gray-700 border border-gray-300 rounded-lg bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500">
                <AdjustmentsHorizontalIcon className="w-4 h-4 text-gray-500" />
                Columns ({visibleKeys.length}/{COLUMNS.length})
            </PopoverButton>
            <PopoverPanel
                anchor="bottom end"
                className="z-50 mt-1 w-64 rounded-lg bg-white shadow-lg ring-1 ring-black/5 p-3"
            >
                <div className="max-h-80 overflow-y-auto space-y-1">
                    {COLUMNS.map(c => (
                        <label key={c.key} className="flex items-center gap-2 text-sm text-gray-700 py-0.5 cursor-pointer">
                            <input
                                type="checkbox"
                                checked={visibleKeys.includes(c.key)}
                                onChange={() => toggle(c.key)}
                                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                            />
                            {c.label}
                        </label>
                    ))}
                </div>
                <div className="flex justify-between gap-2 pt-3 mt-2 border-t border-gray-100">
                    <button
                        type="button"
                        onClick={() => onChange(COLUMNS.map(c => c.key))}
                        className="text-xs text-blue-600 hover:underline"
                    >
                        Show all
                    </button>
                    <button
                        type="button"
                        onClick={() => onChange(DEFAULT_COLUMN_KEYS)}
                        className="text-xs text-gray-600 hover:underline"
                    >
                        Reset to default
                    </button>
                </div>
            </PopoverPanel>
        </Popover>
    )
}
