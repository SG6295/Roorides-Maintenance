import { useState } from 'react'
import { useAuth } from '../../hooks/useAuth'
import { useSetPartScrapDefault } from '../../hooks/useInventory'
import { logAuditEvent } from '../../utils/auditLogger'
import { DEFAULT_EXCLUSION_REASON_OPTIONS } from '../../constants/scrapExclusion'
import CustomSelect from '../shared/CustomSelect'

/**
 * The "Exclude from scrap by default" cell in the Parts Catalog.
 *
 * Ticking the box does not save on its own — a default with no reason is a state
 * the DB constraint rejects and the closure modal could not pre-fill from. The
 * row sits in a pending state until a reason is picked, and that choice is what
 * commits. Unticking saves immediately and clears the reason.
 */
export default function ScrapDefaultCell({ part }) {
    const { userProfile } = useAuth()
    const setDefault = useSetPartScrapDefault()

    // True only between ticking the box and choosing a reason.
    const [awaitingReason, setAwaitingReason] = useState(false)
    const [error, setError] = useState(null)

    const isSet = part.default_exclude_from_scrap
    const checked = isSet || awaitingReason

    async function save(excludeByDefault, reason) {
        setError(null)
        try {
            await setDefault.mutateAsync({ id: part.id, excludeByDefault, reason })
            await logAuditEvent(part.id, 'parts', 'UPDATE', userProfile?.id, {
                oldData: {
                    default_exclude_from_scrap: part.default_exclude_from_scrap,
                    default_exclusion_reason:   part.default_exclusion_reason,
                },
                newData: {
                    default_exclude_from_scrap: excludeByDefault,
                    default_exclusion_reason:   excludeByDefault ? reason : null,
                },
                changedFields: ['default_exclude_from_scrap', 'default_exclusion_reason'],
            })
            // Hold the pending flag until the refetched part carries the flag
            // itself, otherwise the reason dropdown blinks out of existence
            // between the save resolving and the list arriving.
            if (!excludeByDefault) setAwaitingReason(false)
        } catch (err) {
            setError(err.message || 'Could not save.')
            setAwaitingReason(false)
        }
    }

    function toggle() {
        if (checked) {
            // Unticking a row that was never saved just abandons it.
            if (awaitingReason && !isSet) {
                setAwaitingReason(false)
                setError(null)
                return
            }
            save(false, null)
        } else {
            setAwaitingReason(true)
        }
    }

    return (
        <div className="flex items-center gap-2">
            <input
                type="checkbox"
                checked={checked}
                onChange={toggle}
                disabled={setDefault.isPending}
                className="rounded border-gray-300 text-blue-600 focus:ring-blue-500 disabled:opacity-40 shrink-0"
                aria-label={`Exclude ${part.name} from scrap by default`}
            />

            {checked && (
                <div className="min-w-[11rem]">
                    <CustomSelect
                        compact
                        value={part.default_exclusion_reason ?? ''}
                        onChange={reason => save(true, reason)}
                        options={DEFAULT_EXCLUSION_REASON_OPTIONS}
                        placeholder="Pick a reason…"
                        disabled={setDefault.isPending}
                    />
                </div>
            )}

            {error && <span className="text-xs text-red-600">{error}</span>}
        </div>
    )
}
