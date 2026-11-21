import { duplicatePartMessage } from '../../utils/partName'

/**
 * Shown when a typed part name is already in the catalog (MAIN-148). `onUse` picks the
 * existing part instead; without it (renaming in the Parts Catalog) only the message shows.
 */
export default function DuplicatePartNotice({ part, onUse }) {
    return (
        <div className="text-xs text-red-600">
            <span>{duplicatePartMessage(part)}</span>
            {part && onUse && (
                <button
                    type="button"
                    onClick={() => onUse(part)}
                    className="ml-2 font-medium text-blue-700 underline hover:text-blue-800"
                >
                    Use '{part.name.trim()}'
                </button>
            )}
        </div>
    )
}
