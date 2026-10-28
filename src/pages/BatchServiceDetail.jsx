import { useState } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { XMarkIcon } from '@heroicons/react/20/solid'
import { todayLocal } from '../utils/datetime'
import { useAuth } from '../hooks/useAuth'
import { useBatchService, useSaveBatchService } from '../hooks/useBatchServices'
import { useApprovedSuppliers } from '../hooks/useSuppliers'
import { useActiveSites } from '../hooks/useSites'
import { useVehicles } from '../hooks/useVehicles'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import SearchableSelect from '../components/shared/SearchableSelect'
import CustomSelect from '../components/shared/CustomSelect'
import DocumentUpload from '../components/suppliers/DocumentUpload'
import InvoiceDetailsFields, { InvoiceDetailsReadOnly } from '../components/outsource-invoices/InvoiceDetailsFields'
import {
    EMPTY_INVOICE_FORM,
    invoiceFormFromRow,
    invoiceFormToRow,
    validateInvoiceForm,
} from '../components/outsource-invoices/invoiceForm'
import { fmtMoney, fmtPaise } from '../components/outsource-invoices/format'
import { formatSiteLabel } from '../utils/siteLabel'
import { splitEvenly, linesSummary } from '../utils/batchSplit'

const EXEC_ROLES = ['maintenance_exec', 'super_admin']

const inputClass = hasError =>
    `w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${hasError ? 'border-red-400' : 'border-gray-300'}`

/**
 * A multi-vehicle outsource invoice (MAIN-99): one vendor invoice covering work on many
 * vehicles, recorded with no ticket and no job card. `/batch-invoices/new` creates one;
 * `/batch-invoices/:id` edits it until finance records a payment, and is read-only
 * after that and for finance.
 */
export default function BatchServiceDetail() {
    const { id } = useParams()
    const isNew = id === 'new'
    const { data: batch, isLoading, error } = useBatchService(isNew ? null : id)

    if (!isNew && isLoading) return <TicketDetailSkeleton />

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[
                { label: 'Outsource Invoices', href: '/outsource-invoices' },
                { label: isNew ? 'New multi-vehicle invoice' : 'Multi-vehicle invoice' },
            ]} />
            <div className="max-w-3xl mx-auto px-4 sm:px-6 py-6 space-y-4">
                {error ? (
                    <p className="text-sm text-red-600">Could not load this invoice: {error.message}</p>
                ) : (
                    // Keyed by batch, not by its updated_at: the form already holds what it just
                    // saved, and a remount on every save would drop the "Saved." confirmation.
                    <BatchForm key={batch?.id ?? 'new'} batch={isNew ? null : batch} />
                )}
            </div>
        </div>
    )
}

function BatchForm({ batch }) {
    const navigate = useNavigate()
    const { userProfile } = useAuth()
    const save = useSaveBatchService()
    const { data: suppliers = [] } = useApprovedSuppliers()
    const { data: sites = [] } = useActiveSites()
    const { data: vehicles = [] } = useVehicles({ active: 'active' })
    const todayStr = todayLocal()

    const [description, setDescription] = useState(batch?.description ?? '')
    const [supplierId, setSupplierId] = useState(batch?.supplier_id ?? '')
    const [invoiceUrl, setInvoiceUrl] = useState(batch?.invoice_url ?? '')
    const [invoiceForm, setInvoiceForm] = useState(batch?.invoice ? invoiceFormFromRow(batch.invoice) : EMPTY_INVOICE_FORM)
    const [lines, setLines] = useState(
        () => (batch?.vehicles ?? []).map(v => ({ vehicle_number: v.vehicle_number, site: v.site ?? '', amount: String(v.amount) })),
    )
    const [showErrors, setShowErrors] = useState(false)
    const [saveError, setSaveError] = useState(null)
    const [saved, setSaved] = useState(false)

    const isExec = EXEC_ROLES.includes(userProfile?.role)
    // A cancelled payment (failed transaction, refunded) does not lock the invoice.
    const hasPayments = (batch?.invoice?.payments ?? []).some(p => p.status !== 'Cancelled')
    if (batch && (!isExec || hasPayments)) return <BatchReadOnly batch={batch} lockedByPayment={isExec && hasPayments} />

    const invoiceErrs = validateInvoiceForm(invoiceForm, todayStr)
    const summary = linesSummary(lines, invoiceForm.approvedAmount)
    const errors = {
        ...(description.trim() ? {} : { description: 'Required' }),
        ...(supplierId ? {} : { supplier: 'Required' }),
        ...(invoiceUrl ? {} : { invoiceUrl: 'Upload the invoice' }),
    }
    const linesWithoutSite = lines.filter(l => !l.site).length
    const linesAddUp = lines.length > 0 && summary.invalid.length === 0 && summary.difference === 0
    const linesReady = linesAddUp && linesWithoutSite === 0
    const isValid = Object.keys(invoiceErrs).length === 0 && Object.keys(errors).length === 0 && linesReady

    // Each vehicle's current site links. A line's site is fixed when its vehicle has one
    // site and a choice among them when it has several; the database only requires that
    // one is set, since these links are rebuilt nightly and a bus can move after the work.
    const vehicleSites = new Map(vehicles.map(v => [v.registration_number, (v.vehicle_sites ?? []).map(s => s.site_name)]))
    const siteByName = new Map(sites.map(s => [s.name, s]))
    const siteOptionsFor = line => {
        const own = vehicleSites.get(line.vehicle_number) ?? []
        // A vehicle with no site links can be at any active site.
        const names = own.length > 0 ? own : sites.map(s => s.name)
        const options = names.map(name => ({ value: name, label: siteByName.has(name) ? formatSiteLabel(siteByName.get(name)) : name }))
        // A saved site the bus has since moved away from stays selectable, so the line
        // still shows it and the batch can be saved without re-choosing.
        if (line.site && !names.includes(line.site)) {
            options.unshift({ value: line.site, label: `${line.site} (no longer linked to this vehicle)` })
        }
        return options
    }

    const usedVehicles = new Set(lines.map(l => l.vehicle_number))
    const vehicleOptions = vehicles
        .filter(v => !usedVehicles.has(v.registration_number))
        .map(v => ({
            value: v.registration_number,
            label: v.registration_number,
            badge: v.vehicle_sites?.map(s => s.site_name).join(', ') || undefined,
        }))

    const addVehicle = vehicleNumber => {
        if (!vehicleNumber || usedVehicles.has(vehicleNumber)) return
        const own = vehicleSites.get(vehicleNumber) ?? []
        setLines(prev => [...prev, { vehicle_number: vehicleNumber, site: own.length === 1 ? own[0] : '', amount: '' }])
    }
    const setLineAmount = (i, amount) => setLines(prev => prev.map((l, j) => (j === i ? { ...l, amount } : l)))
    const setLineSite = (i, site) => setLines(prev => prev.map((l, j) => (j === i ? { ...l, site } : l)))
    const removeLine = i => setLines(prev => prev.filter((_, j) => j !== i))
    const evenSplit = splitEvenly(invoiceForm.approvedAmount, lines.length)
    const applyEvenSplit = () => setLines(prev => prev.map((l, i) => ({ ...l, amount: evenSplit[i] })))

    const handleSave = async () => {
        setSaveError(null)
        setSaved(false)
        if (!isValid) {
            setShowErrors(true)
            return
        }
        try {
            const savedId = await save.mutateAsync({
                batchId: batch?.id,
                batch: { description: description.trim(), supplier_id: supplierId, invoice_url: invoiceUrl },
                invoice: invoiceFormToRow(invoiceForm),
                lines: lines.map(l => ({ vehicle_number: l.vehicle_number, site: l.site, amount: l.amount })),
            })
            if (batch) setSaved(true)
            else navigate(`/batch-invoices/${savedId}`, { replace: true })
        } catch (e) {
            setSaveError(e.message)
        }
    }

    return (
        <>
            <h1 className="text-xl font-bold text-gray-900">
                {batch ? 'Multi-vehicle invoice' : 'New multi-vehicle invoice'}
            </h1>
            <p className="text-sm text-gray-500 -mt-2">
                One vendor invoice covering several vehicles. No ticket or job card is created; each vehicle's history shows its share.
            </p>

            {/* ── Work ─────────────────────────────────────────────────────── */}
            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4 space-y-3">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider">Work</h2>
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        What was done <span className="text-red-500">*</span>
                    </label>
                    <input
                        type="text"
                        value={description}
                        maxLength={200}
                        onChange={e => setDescription(e.target.value)}
                        placeholder="e.g. Hub greasing"
                        className={inputClass(showErrors && errors.description)}
                    />
                    {showErrors && errors.description && <p className="text-xs text-red-600 mt-0.5">{errors.description}</p>}
                </div>
                <div>
                    <label className="block text-xs font-medium text-gray-600 mb-1">
                        Vendor <span className="text-red-500">*</span>
                    </label>
                    <SearchableSelect
                        value={supplierId}
                        onChange={setSupplierId}
                        options={suppliers.map(s => ({ value: s.id, label: s.entity_name }))}
                        showAllOnFocus
                        placeholder="Search suppliers..."
                        error={showErrors && errors.supplier}
                    />
                    {showErrors && errors.supplier && <p className="text-xs text-red-600 mt-0.5">{errors.supplier}</p>}
                </div>
            </section>

            {/* ── Vehicles ─────────────────────────────────────────────────── */}
            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4 space-y-3">
                <div className="flex items-center justify-between">
                    <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider">
                        Vehicles {lines.length > 0 && <span className="text-gray-400 normal-case">({lines.length})</span>}
                    </h2>
                    <button
                        type="button"
                        onClick={applyEvenSplit}
                        disabled={evenSplit.length === 0}
                        title={evenSplit.length === 0 ? 'Enter the approved amount and add vehicles first' : undefined}
                        className="text-xs px-2.5 py-1 text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                        Split approved amount evenly
                    </button>
                </div>

                <SearchableSelect
                    value=""
                    onChange={addVehicle}
                    options={vehicleOptions}
                    placeholder="Search a registration number to add it..."
                />

                {lines.length === 0 ? (
                    <p className={`text-xs ${showErrors ? 'text-red-600' : 'text-gray-400 italic'}`}>No vehicles added yet.</p>
                ) : (
                    <table className="min-w-full text-sm">
                        <thead>
                            <tr className="text-xs text-gray-500 uppercase tracking-wide">
                                <th className="text-left font-medium py-1">Vehicle</th>
                                <th className="text-left font-medium py-1 px-2">Site</th>
                                <th className="text-right font-medium py-1 w-36">Amount (₹)</th>
                                <th className="w-8" />
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {lines.map((line, i) => (
                                <tr key={line.vehicle_number}>
                                    <td className="py-1.5 font-mono text-gray-800 whitespace-nowrap">{line.vehicle_number}</td>
                                    <td className="py-1.5 px-2 min-w-[12rem]">
                                        {(vehicleSites.get(line.vehicle_number)?.length ?? 0) === 1
                                            && (!line.site || line.site === vehicleSites.get(line.vehicle_number)[0]) ? (
                                            // The vehicle's only site, filled in and not editable.
                                            <span className="text-sm text-gray-700" title="This vehicle is linked to one site">
                                                {line.site || vehicleSites.get(line.vehicle_number)[0]}
                                            </span>
                                        ) : (
                                            <CustomSelect
                                                value={line.site}
                                                onChange={site => setLineSite(i, site)}
                                                options={siteOptionsFor(line)}
                                                placeholder="Select site…"
                                                error={showErrors && !line.site}
                                                compact
                                            />
                                        )}
                                    </td>
                                    <td className="py-1.5">
                                        <input
                                            type="number"
                                            min="0.01"
                                            step="0.01"
                                            value={line.amount}
                                            onChange={e => setLineAmount(i, e.target.value)}
                                            placeholder="0.00"
                                            aria-label={`Amount for ${line.vehicle_number}`}
                                            className={`${inputClass(showErrors && summary.invalid.includes(i))} text-right py-1`}
                                        />
                                    </td>
                                    <td className="py-1.5 pl-2">
                                        <button
                                            type="button"
                                            onClick={() => removeLine(i)}
                                            aria-label={`Remove ${line.vehicle_number}`}
                                            className="p-1 rounded text-gray-400 hover:text-red-600 hover:bg-red-50"
                                        >
                                            <XMarkIcon className="w-4 h-4" />
                                        </button>
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}

                {lines.length > 0 && <LinesTotal summary={summary} linesWithoutSite={linesWithoutSite} />}
            </section>

            {/* ── Invoice details + file ───────────────────────────────────── */}
            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">Invoice Details</h2>
                <InvoiceDetailsFields
                    form={invoiceForm}
                    setForm={setInvoiceForm}
                    errors={invoiceErrs}
                    showErrors={showErrors}
                    todayStr={todayStr}
                />
            </section>

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">Invoice</h2>
                <DocumentUpload
                    label=""
                    required
                    value={invoiceUrl}
                    onChange={url => setInvoiceUrl(url || '')}
                    accept=".pdf,.jpg,.jpeg,.png"
                />
                {showErrors && errors.invoiceUrl && <p className="mt-2 text-xs text-red-600">{errors.invoiceUrl}</p>}
            </section>

            {saveError && <p className="text-sm text-red-600">{saveError}</p>}
            {saved && <p className="text-sm text-green-700">Saved.</p>}

            <button
                type="button"
                onClick={handleSave}
                disabled={save.isPending || !linesReady}
                className="w-full py-3 rounded-xl text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed"
            >
                {save.isPending ? 'Saving…' : batch ? 'Save changes' : 'Save multi-vehicle invoice'}
            </button>
            {!linesReady && (
                <p className="text-xs text-gray-500 text-center -mt-2">
                    Save is enabled once every vehicle has a site and an amount, and the amounts add up to the approved amount.
                </p>
            )}
        </>
    )
}

/**
 * Running total of the vehicle lines against the approved amount. Missing amounts and
 * sites are named before the total is judged: a blank line counts for nothing, so the
 * others can add up while a vehicle still has no amount.
 */
function LinesTotal({ summary, linesWithoutSite }) {
    const { total, approved, difference, invalid } = summary
    const plural = n => `${n} vehicle${n === 1 ? '' : 's'}`
    let status
    if (invalid.length > 0) status = <span className="text-amber-700">{plural(invalid.length)} need{invalid.length === 1 ? 's' : ''} an amount</span>
    else if (linesWithoutSite > 0) status = <span className="text-amber-700">{plural(linesWithoutSite)} need{linesWithoutSite === 1 ? 's' : ''} a site</span>
    else if (!Number.isFinite(approved) || approved === 0) status = <span className="text-gray-500">Enter the approved amount</span>
    else if (difference === 0) status = <span className="text-green-700">✓ Adds up to the approved amount</span>
    else if (difference > 0) status = <span className="text-amber-700">{fmtPaise(difference)} left to allocate</span>
    else status = <span className="text-red-600">{fmtPaise(-difference)} over the approved amount</span>

    return (
        <div className="flex items-center justify-between border-t border-gray-100 pt-2 text-sm">
            <span className="text-gray-700">
                Total <span className="font-semibold">{fmtPaise(total)}</span>
                {Number.isFinite(approved) && approved > 0 && <> of {fmtPaise(approved)}</>}
            </span>
            {status}
        </div>
    )
}

function BatchReadOnly({ batch, lockedByPayment }) {
    return (
        <>
            <h1 className="text-xl font-bold text-gray-900">Multi-vehicle invoice</h1>
            {lockedByPayment && (
                <p className="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
                    Finance has recorded a payment against this invoice, so it can no longer be edited.
                </p>
            )}

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">Work</h2>
                <div className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
                    {[
                        ['What was done', batch.description],
                        ['Vendor', batch.supplier?.entity_name || '—'],
                    ].map(([label, value]) => (
                        <div key={label}>
                            <p className="text-xs text-gray-500 mb-0.5">{label}</p>
                            <p className="font-medium text-gray-900">{value}</p>
                        </div>
                    ))}
                </div>
            </section>

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                    Vehicles <span className="text-gray-400 normal-case">({batch.vehicles.length})</span>
                </h2>
                <table className="min-w-full text-sm">
                    <tbody className="divide-y divide-gray-100">
                        {batch.vehicles.map(v => (
                            <tr key={v.id}>
                                <td className="py-1.5">
                                    <Link to={`/vehicles/${encodeURIComponent(v.vehicle_number)}`} className="font-mono text-blue-600 hover:underline">
                                        {v.vehicle_number}
                                    </Link>
                                </td>
                                <td className="py-1.5 px-2 text-gray-700">{v.site || '—'}</td>
                                <td className="py-1.5 text-right text-gray-800">{fmtMoney(v.amount)}</td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </section>

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">Invoice Details</h2>
                <InvoiceDetailsReadOnly invoice={batch.invoice} />
            </section>

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">Invoice</h2>
                <a
                    href={batch.invoice_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-1.5 text-sm text-blue-600 hover:underline"
                >
                    View uploaded invoice →
                </a>
            </section>
        </>
    )
}
