import { useState } from 'react'
import { useParams, useNavigate, Link, Navigate } from 'react-router-dom'
import { XMarkIcon } from '@heroicons/react/20/solid'
import { todayLocal } from '../utils/datetime'
import { useAuth } from '../hooks/useAuth'
import {
    useBatchService,
    useBatchNumberById,
    useSaveBatchService,
    useCancelBatchService,
    useRestoreBatchService,
    useOutsourceJobCardsForVehicles,
} from '../hooks/useBatchServices'
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
import { fmtMoney, fmtPaise, fmtDate } from '../components/outsource-invoices/format'
import { formatSiteLabel } from '../utils/siteLabel'
import { formatBatchNumber, batchPath, parseBatchNumber } from '../utils/batchNumber'
import { lineAmount, linesSummary } from '../utils/batchSplit'
import { BATCH_WORK_TYPES, OTHER_WORK_TYPE, workTypeLabel } from '../constants/batchWorkTypes'

const EXEC_ROLES = ['maintenance_exec', 'super_admin']

const WORK_TYPE_OPTIONS = BATCH_WORK_TYPES.map(t => ({ value: t, label: t === OTHER_WORK_TYPE ? 'Other (specify)' : t }))

// A client-side key per line: a vehicle can now have several lines, so its number no
// longer identifies one, and a new line has no id until it is saved.
let nextLineKey = 0
const newLine = fields => ({
    key: `line-${nextLineKey++}`,
    id: null,
    site: '',
    work_type: '',
    work_type_other: '',
    rate: '',
    quantity: '1',
    job_card_id: '',
    linked_job_card: null,
    ...fields,
})

const inputClass = hasError =>
    `w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${hasError ? 'border-red-400' : 'border-gray-300'}`

/**
 * A multi-vehicle outsource invoice (MAIN-99): one vendor invoice covering work on many
 * vehicles, recorded with no ticket and no job card. Each line is one vehicle and one
 * kind of work, priced rate × quantity (MAIN-112). `/multi-vehicle-invoices/new` creates
 * one; `/multi-vehicle-invoices/MVI-12` edits it until finance records a payment, and is
 * read-only after that and for finance.
 */
export default function BatchServiceDetail() {
    const { number } = useParams()
    const isNew = number === 'new'
    const batchNumber = isNew ? null : parseBatchNumber(number)
    const { data: batch, isLoading, error } = useBatchService(batchNumber)

    if (!isNew && batchNumber && isLoading) return <TicketDetailSkeleton />
    const notFound = !isNew && (!batchNumber || batch === null)

    return (
        <div className="min-h-screen bg-gray-50">
            <Navigation breadcrumbs={[
                { label: 'Outsource Invoices', href: '/outsource-invoices' },
                { label: isNew ? 'New multi-vehicle invoice' : formatBatchNumber(batchNumber ?? number) },
            ]} />
            <div className="max-w-5xl mx-auto px-4 sm:px-6 py-6 space-y-4">
                {error ? (
                    <p className="text-sm text-red-600">Could not load this invoice: {error.message}</p>
                ) : notFound ? (
                    <p className="text-sm text-gray-600">There is no multi-vehicle invoice {number}.</p>
                ) : (
                    // Keyed by batch, not by its updated_at: the form already holds what it just
                    // saved, and a remount on every save would drop the "Saved." confirmation.
                    // The status is in the key because cancelling and restoring change the lines'
                    // job card links outside the form.
                    <BatchForm key={batch ? `${batch.id}-${batch.status}` : 'new'} batch={isNew ? null : batch} />
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

    const [supplierId, setSupplierId] = useState(batch?.supplier_id ?? '')
    const [invoiceUrl, setInvoiceUrl] = useState(batch?.invoice_url ?? '')
    const [invoiceForm, setInvoiceForm] = useState(batch?.invoice ? invoiceFormFromRow(batch.invoice) : EMPTY_INVOICE_FORM)
    const [lines, setLines] = useState(
        () => (batch?.vehicles ?? []).map(v => newLine({
            id: v.id,
            vehicle_number: v.vehicle_number,
            site: v.site ?? '',
            work_type: v.work_type ?? '',
            work_type_other: v.work_type_other ?? '',
            rate: v.rate != null ? String(v.rate) : '',
            quantity: v.quantity != null ? String(v.quantity) : '1',
            job_card_id: v.job_card_id ?? '',
            linked_job_card: v.linked_job_card,
        })),
    )
    const [rateForAll, setRateForAll] = useState('')
    const [showErrors, setShowErrors] = useState(false)
    const [saveError, setSaveError] = useState(null)
    const [saved, setSaved] = useState(false)

    const { data: jobCards = [] } = useOutsourceJobCardsForVehicles(lines.map(l => l.vehicle_number))

    const isExec = EXEC_ROLES.includes(userProfile?.role)
    // A cancelled payment (failed transaction, refunded) does not lock the invoice.
    const hasPayments = (batch?.invoice?.payments ?? []).some(p => p.status !== 'Cancelled')
    const cancelled = batch?.status === 'Cancelled'
    if (batch && (!isExec || hasPayments || cancelled)) {
        return <BatchReadOnly batch={batch} lockedByPayment={isExec && hasPayments && !cancelled} canRestore={isExec && cancelled} />
    }

    const invoiceErrs = validateInvoiceForm(invoiceForm, todayStr)
    const summary = linesSummary(lines, invoiceForm.approvedAmount)
    const errors = {
        ...(supplierId ? {} : { supplier: 'Required' }),
        ...(invoiceUrl ? {} : { invoiceUrl: 'Upload the invoice' }),
    }

    // What each line still lacks. The database checks the same things.
    const isOther = line => line.work_type === OTHER_WORK_TYPE
    const lacksWork = line => !line.work_type || (isOther(line) && !line.work_type_other.trim())
    const lacksJobCard = line => isOther(line) && !line.job_card_id
    // A vehicle may have one line per standard work type; Other repeats freely.
    const duplicateKeys = new Set()
    const seen = new Map()
    for (const line of lines) {
        if (!line.work_type || isOther(line)) continue
        const k = `${line.vehicle_number}|${line.work_type}`
        if (seen.has(k)) { duplicateKeys.add(seen.get(k)); duplicateKeys.add(line.key) }
        else seen.set(k, line.key)
    }
    const problems = {
        work: lines.filter(lacksWork).length,
        site: lines.filter(l => !l.site).length,
        jobCard: lines.filter(lacksJobCard).length,
        duplicate: duplicateKeys.size,
    }
    const linesAddUp = lines.length > 0 && summary.invalid.length === 0 && summary.difference === 0
    const linesReady = linesAddUp && Object.values(problems).every(n => n === 0)
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

    // Already-added vehicles stay pickable: a bus can need a second line for other work.
    const vehicleOptions = vehicles.map(v => ({
        value: v.registration_number,
        label: v.registration_number,
        badge: v.vehicle_sites?.map(s => s.site_name).join(', ') || undefined,
    }))

    const addVehicle = vehicleNumber => {
        if (!vehicleNumber) return
        const own = vehicleSites.get(vehicleNumber) ?? []
        setLines(prev => [...prev, newLine({ vehicle_number: vehicleNumber, site: own.length === 1 ? own[0] : '' })])
    }
    const setLine = (key, fields) => setLines(prev => prev.map(l => (l.key === key ? { ...l, ...fields } : l)))
    const removeLine = key => setLines(prev => prev.filter(l => l.key !== key))
    const rateForAllValid = Number.isFinite(lineAmount({ rate: rateForAll, quantity: '1' }))
    const applyRateToAll = () => setLines(prev => prev.map(l => ({ ...l, rate: rateForAll })))

    const handleSave = async () => {
        setSaveError(null)
        setSaved(false)
        if (!isValid) {
            setShowErrors(true)
            return
        }
        try {
            const savedNumber = await save.mutateAsync({
                batchId: batch?.id,
                batch: { supplier_id: supplierId, invoice_url: invoiceUrl },
                invoice: invoiceFormToRow(invoiceForm),
                lines: lines.map(l => ({
                    id: l.id,
                    vehicle_number: l.vehicle_number,
                    site: l.site,
                    work_type: l.work_type,
                    work_type_other: isOther(l) ? l.work_type_other.trim() : null,
                    rate: l.rate,
                    quantity: l.quantity,
                    job_card_id: l.job_card_id || null,
                })),
            })
            if (batch) setSaved(true)
            else navigate(batchPath(savedNumber), { replace: true })
        } catch (e) {
            setSaveError(e.message)
        }
    }

    return (
        <>
            <h1 className="text-xl font-bold text-gray-900">
                {batch ? `Multi-vehicle invoice ${formatBatchNumber(batch.batch_number)}` : 'New multi-vehicle invoice'}
            </h1>
            <p className="text-sm text-gray-500 -mt-2">
                One vendor invoice covering several vehicles. No ticket or job card is created; each vehicle's history shows its work.
            </p>

            {/* ── Vendor ───────────────────────────────────────────────────── */}
            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
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
            </section>

            {/* ── Vehicles and work ────────────────────────────────────────── */}
            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4 space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                    <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider">
                        Vehicles and work {lines.length > 0 && <span className="text-gray-400 normal-case">({lines.length})</span>}
                    </h2>
                    <div className="flex items-center gap-1.5">
                        <input
                            type="number"
                            min="0.01"
                            step="0.01"
                            value={rateForAll}
                            onChange={e => setRateForAll(e.target.value)}
                            placeholder="Rate ₹"
                            aria-label="Rate to apply to all lines"
                            className="w-24 text-xs border border-gray-300 rounded-lg px-2 py-1 text-right focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                        <button
                            type="button"
                            onClick={applyRateToAll}
                            disabled={!rateForAllValid || lines.length === 0}
                            title={lines.length === 0 ? 'Add vehicles first' : !rateForAllValid ? 'Enter a rate first' : undefined}
                            className="text-xs px-2.5 py-1 text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 disabled:opacity-40 disabled:cursor-not-allowed"
                        >
                            Apply rate to all lines
                        </button>
                    </div>
                </div>

                <SearchableSelect
                    value=""
                    onChange={addVehicle}
                    options={vehicleOptions}
                    placeholder="Search a registration number to add a line..."
                />

                {lines.length === 0 ? (
                    <p className={`text-xs ${showErrors ? 'text-red-600' : 'text-gray-400 italic'}`}>No vehicles added yet.</p>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="min-w-full text-sm">
                            <thead>
                                <tr className="text-xs text-gray-500 uppercase tracking-wide">
                                    <th className="text-left font-medium py-1">Vehicle</th>
                                    <th className="text-left font-medium py-1 px-2">Site</th>
                                    <th className="text-left font-medium py-1 px-2">Type of work</th>
                                    <th className="text-right font-medium py-1 px-2">Rate (₹)</th>
                                    <th className="text-right font-medium py-1 px-2">Qty</th>
                                    <th className="text-right font-medium py-1 px-2">Amount</th>
                                    <th className="text-left font-medium py-1 px-2">Job card</th>
                                    <th className="w-8" />
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                                {lines.map((line, i) => {
                                    const amount = lineAmount(line)
                                    const own = vehicleSites.get(line.vehicle_number) ?? []
                                    const duplicate = duplicateKeys.has(line.key)
                                    return (
                                        <tr key={line.key} className="align-top">
                                            <td className="py-1.5 font-mono text-gray-800 whitespace-nowrap">{line.vehicle_number}</td>
                                            <td className="py-1.5 px-2 min-w-[11rem]">
                                                {own.length === 1 && (!line.site || line.site === own[0]) ? (
                                                    // The vehicle's only site, filled in and not editable.
                                                    <span className="text-sm text-gray-700" title="This vehicle is linked to one site">
                                                        {line.site || own[0]}
                                                    </span>
                                                ) : (
                                                    <CustomSelect
                                                        value={line.site}
                                                        onChange={site => setLine(line.key, { site })}
                                                        options={siteOptionsFor(line)}
                                                        placeholder="Select site…"
                                                        error={showErrors && !line.site}
                                                        compact
                                                    />
                                                )}
                                            </td>
                                            <td className="py-1.5 px-2 min-w-[10rem] space-y-1">
                                                <CustomSelect
                                                    value={line.work_type}
                                                    onChange={work_type => setLine(line.key, { work_type })}
                                                    options={WORK_TYPE_OPTIONS}
                                                    placeholder="Select work…"
                                                    error={(showErrors && !line.work_type) || duplicate}
                                                    compact
                                                />
                                                {isOther(line) && (
                                                    <input
                                                        type="text"
                                                        value={line.work_type_other}
                                                        maxLength={100}
                                                        onChange={e => setLine(line.key, { work_type_other: e.target.value })}
                                                        placeholder="What was done?"
                                                        aria-label={`Work done on ${line.vehicle_number}`}
                                                        className={`${inputClass(showErrors && !line.work_type_other.trim())} text-xs py-1.5`}
                                                    />
                                                )}
                                                {duplicate && <p className="text-xs text-red-600">Already on this invoice for this vehicle</p>}
                                            </td>
                                            <td className="py-1.5 px-2 min-w-[6.5rem]">
                                                <input
                                                    type="number"
                                                    min="0.01"
                                                    step="0.01"
                                                    value={line.rate}
                                                    onChange={e => setLine(line.key, { rate: e.target.value })}
                                                    placeholder="0.00"
                                                    aria-label={`Rate for ${line.vehicle_number}`}
                                                    className={`${inputClass(showErrors && summary.invalid.includes(i))} text-right py-1`}
                                                />
                                            </td>
                                            <td className="py-1.5 px-2 min-w-[4.5rem]">
                                                <input
                                                    type="number"
                                                    min="1"
                                                    step="1"
                                                    value={line.quantity}
                                                    onChange={e => setLine(line.key, { quantity: e.target.value })}
                                                    aria-label={`Quantity for ${line.vehicle_number}`}
                                                    className={`${inputClass(showErrors && summary.invalid.includes(i))} text-right py-1`}
                                                />
                                            </td>
                                            <td className="py-1.5 px-2 text-right text-gray-800 whitespace-nowrap pt-2.5">
                                                {Number.isFinite(amount) ? fmtPaise(amount) : '—'}
                                            </td>
                                            <td className="py-1.5 px-2 min-w-[13rem]">
                                                <JobCardPicker
                                                    line={line}
                                                    jobCards={jobCards}
                                                    required={isOther(line)}
                                                    showError={showErrors && lacksJobCard(line)}
                                                    onChange={job_card_id => setLine(line.key, { job_card_id })}
                                                />
                                            </td>
                                            <td className="py-1.5 pl-2">
                                                <button
                                                    type="button"
                                                    onClick={() => removeLine(line.key)}
                                                    aria-label={`Remove line for ${line.vehicle_number}`}
                                                    className="p-1 rounded text-gray-400 hover:text-red-600 hover:bg-red-50"
                                                >
                                                    <XMarkIcon className="w-4 h-4" />
                                                </button>
                                            </td>
                                        </tr>
                                    )
                                })}
                            </tbody>
                        </table>
                    </div>
                )}

                {lines.length > 0 && <LinesTotal summary={summary} problems={problems} />}
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
                    Save is enabled once every line has a site, a type of work, a rate and a quantity (and a job card for Other), and the amounts add up to the approved amount.
                </p>
            )}

            {batch && <CancelInvoice batch={batch} />}
        </>
    )
}

/**
 * Cancelling a multi-vehicle invoice, with a required reason (MAIN-112). Only offered
 * while no payment is recorded — the page is read-only after that — and it releases the
 * invoice's job card links. It can be restored later.
 */
function CancelInvoice({ batch }) {
    const cancel = useCancelBatchService()
    const [open, setOpen] = useState(false)
    const [reason, setReason] = useState('')
    const [error, setError] = useState(null)

    const handleCancel = async () => {
        setError(null)
        try {
            await cancel.mutateAsync({ batchId: batch.id, reason: reason.trim() })
        } catch (e) {
            setError(e.message)
        }
    }

    if (!open) {
        return (
            <div className="text-center">
                <button
                    type="button"
                    onClick={() => setOpen(true)}
                    className="text-sm text-red-600 hover:underline"
                >
                    Cancel this invoice…
                </button>
            </div>
        )
    }

    return (
        <section className="bg-white rounded-xl shadow-sm border border-red-200 p-4 space-y-2">
            <h2 className="text-sm font-semibold text-red-700">Cancel {formatBatchNumber(batch.batch_number)}</h2>
            <p className="text-xs text-gray-600">
                The invoice stays in the list, marked Cancelled, but can no longer be edited or paid. Its job card links are removed.
                You can restore it later.
            </p>
            <textarea
                value={reason}
                onChange={e => setReason(e.target.value)}
                rows={2}
                maxLength={500}
                placeholder="Reason for cancelling (required)"
                aria-label="Reason for cancelling"
                className={inputClass(false)}
            />
            {error && <p className="text-xs text-red-600">{error}</p>}
            <div className="flex gap-2 justify-end">
                <button
                    type="button"
                    onClick={() => { setOpen(false); setReason(''); setError(null) }}
                    className="text-sm px-3 py-1.5 rounded-lg border border-gray-300 text-gray-700 hover:bg-gray-50"
                >
                    Keep invoice
                </button>
                <button
                    type="button"
                    onClick={handleCancel}
                    disabled={!reason.trim() || cancel.isPending}
                    className="text-sm px-3 py-1.5 rounded-lg bg-red-600 text-white hover:bg-red-700 disabled:opacity-40 disabled:cursor-not-allowed"
                >
                    {cancel.isPending ? 'Cancelling…' : 'Cancel invoice'}
                </button>
            </div>
        </section>
    )
}

/**
 * Restoring a cancelled invoice. Cancelling released its job card links, so each Other
 * line must be linked again (the other lines may be); the database checks the same.
 */
function RestoreInvoice({ batch }) {
    const restore = useRestoreBatchService()
    const { data: jobCards = [] } = useOutsourceJobCardsForVehicles(batch.vehicles.map(v => v.vehicle_number))
    const [links, setLinks] = useState({})
    const [error, setError] = useState(null)

    const isOther = v => v.work_type === OTHER_WORK_TYPE
    const missing = batch.vehicles.filter(v => isOther(v) && !links[v.id]).length

    const handleRestore = async () => {
        setError(null)
        try {
            await restore.mutateAsync({
                batchId: batch.id,
                links: Object.entries(links).filter(([, jc]) => jc).map(([id, job_card_id]) => ({ id, job_card_id })),
            })
        } catch (e) {
            setError(e.message)
        }
    }

    return (
        <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4 space-y-3">
            <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider">Restore this invoice</h2>
            <p className="text-xs text-gray-600">
                Cancelling removed the job card links. Link a job card for every Other line (required); the rest are optional.
            </p>
            <table className="min-w-full text-sm">
                <tbody className="divide-y divide-gray-100">
                    {batch.vehicles.map(v => (
                        <tr key={v.id} className="align-top">
                            <td className="py-1.5 font-mono text-gray-800 whitespace-nowrap">{v.vehicle_number}</td>
                            <td className="py-1.5 px-2 text-gray-700">{workTypeLabel(v)}</td>
                            <td className="py-1.5 px-2 min-w-[14rem]">
                                <JobCardPicker
                                    line={{ ...v, job_card_id: links[v.id] ?? '', linked_job_card: null }}
                                    jobCards={jobCards}
                                    required={isOther(v)}
                                    showError={false}
                                    onChange={jc => setLinks(prev => ({ ...prev, [v.id]: jc }))}
                                />
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
            {error && <p className="text-xs text-red-600">{error}</p>}
            <div className="flex items-center justify-end gap-3">
                {missing > 0 && (
                    <span className="text-xs text-amber-700">{missing} Other line{missing === 1 ? '' : 's'} still need{missing === 1 ? 's' : ''} a job card</span>
                )}
                <button
                    type="button"
                    onClick={handleRestore}
                    disabled={missing > 0 || restore.isPending}
                    className="text-sm px-3 py-1.5 rounded-lg bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-40 disabled:cursor-not-allowed"
                >
                    {restore.isPending ? 'Restoring…' : 'Restore invoice'}
                </button>
            </div>
        </section>
    )
}

/**
 * The outsourced job card a line belongs to, from that vehicle's open cards and those
 * completed in the last 60 days, searchable by number or by issue text. A saved link
 * outside that window is kept as an option so the line still shows it.
 */
function JobCardPicker({ line, jobCards, required, showError, onChange }) {
    const options = jobCards
        .filter(c => c.vehicle_number === line.vehicle_number)
        // Open (and invoice-pending) cards first, newest first within each.
        .sort((a, b) => (a.status === 'Completed') - (b.status === 'Completed'))
        .map(c => ({
            value: c.id,
            label: `#${c.job_card_number} · ${c.status}`,
            badge: c.status === 'Completed' ? `closed ${fmtDate(c.completed_at)}` : `opened ${fmtDate(c.created_at)}`,
            searchText: (c.issues ?? []).map(i => `${i.category ?? ''} ${i.description ?? ''}`).join(' '),
        }))
    if (line.job_card_id && !options.some(o => o.value === line.job_card_id) && line.linked_job_card) {
        options.unshift({
            value: line.job_card_id,
            label: `#${line.linked_job_card.job_card_number} · ${line.linked_job_card.status}`,
        })
    }

    if (options.length === 0) {
        return (
            <p className={`text-xs pt-1.5 ${showError ? 'text-red-600' : 'text-gray-400 italic'}`}>
                No outsourced job card for this vehicle{required ? ' — needed for Other' : ''}
            </p>
        )
    }

    return (
        <SearchableSelect
            value={line.job_card_id}
            onChange={onChange}
            options={options}
            showAllOnFocus
            pinnedOption={line.job_card_id && !required ? { value: '', label: 'No job card' } : null}
            placeholder={required ? 'Required — search…' : 'Optional — search…'}
            error={showError ? { message: 'Required for Other' } : undefined}
        />
    )
}

/**
 * Running total of the vehicle lines against the approved amount. What lines still lack
 * is named before the total is judged: an unusable line counts for nothing, so the
 * others can add up while a vehicle still has no rate.
 */
function LinesTotal({ summary, problems }) {
    const { total, approved, difference, invalid } = summary
    const plural = n => `${n} line${n === 1 ? '' : 's'}`
    const need = (n, what) => <span className="text-amber-700">{plural(n)} need{n === 1 ? 's' : ''} {what}</span>
    let status
    if (problems.duplicate > 0) status = <span className="text-red-600">The same vehicle has the same work twice</span>
    else if (problems.work > 0) status = need(problems.work, 'a type of work')
    else if (invalid.length > 0) status = need(invalid.length, 'a rate and quantity')
    else if (problems.site > 0) status = need(problems.site, 'a site')
    else if (problems.jobCard > 0) status = need(problems.jobCard, 'a job card')
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

function BatchReadOnly({ batch, lockedByPayment, canRestore }) {
    return (
        <>
            <h1 className="text-xl font-bold text-gray-900 flex items-center gap-2">
                Multi-vehicle invoice {formatBatchNumber(batch.batch_number)}
                {batch.status === 'Cancelled' && (
                    <span className="px-2 py-0.5 rounded text-xs font-semibold bg-red-100 text-red-700">Cancelled</span>
                )}
            </h1>
            {batch.status === 'Cancelled' && (
                <p className="text-sm text-red-800 bg-red-50 border border-red-200 rounded-lg px-3 py-2">
                    Cancelled{batch.cancelled_at && ` on ${fmtDate(batch.cancelled_at)}`}. Reason: {batch.cancel_reason}
                    <span className="block text-xs text-red-700 mt-0.5">It cannot be edited or paid. The invoice history shows who cancelled it.</span>
                </p>
            )}
            {lockedByPayment && (
                <p className="text-sm text-amber-800 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
                    Finance has recorded a payment against this invoice, so it can no longer be edited or cancelled.
                    To cancel it, finance must first cancel the payment.
                </p>
            )}
            {canRestore && <RestoreInvoice batch={batch} />}

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <p className="text-xs text-gray-500 mb-0.5">Vendor</p>
                <p className="text-sm font-medium text-gray-900">{batch.supplier?.entity_name || '—'}</p>
            </section>

            <section className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                    Vehicles and work <span className="text-gray-400 normal-case">({batch.vehicles.length})</span>
                </h2>
                <div className="overflow-x-auto">
                    <table className="min-w-full text-sm">
                        <thead>
                            <tr className="text-xs text-gray-500 uppercase tracking-wide">
                                <th className="text-left font-medium py-1">Vehicle</th>
                                <th className="text-left font-medium py-1 px-2">Site</th>
                                <th className="text-left font-medium py-1 px-2">Type of work</th>
                                <th className="text-right font-medium py-1 px-2">Rate × Qty</th>
                                <th className="text-right font-medium py-1 px-2">Amount</th>
                                <th className="text-left font-medium py-1 px-2">Job card</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {batch.vehicles.map(v => (
                                <tr key={v.id}>
                                    <td className="py-1.5">
                                        <Link to={`/vehicles/${encodeURIComponent(v.vehicle_number)}`} className="font-mono text-blue-600 hover:underline">
                                            {v.vehicle_number}
                                        </Link>
                                    </td>
                                    <td className="py-1.5 px-2 text-gray-700">{v.site || '—'}</td>
                                    <td className="py-1.5 px-2 text-gray-700">{workTypeLabel(v)}</td>
                                    <td className="py-1.5 px-2 text-right text-gray-600 whitespace-nowrap">
                                        {v.rate != null ? `${fmtMoney(v.rate)} × ${v.quantity}` : '—'}
                                    </td>
                                    <td className="py-1.5 px-2 text-right text-gray-800">{fmtMoney(v.amount)}</td>
                                    <td className="py-1.5 px-2">
                                        {v.linked_job_card ? (
                                            <Link to={`/job-cards/${v.linked_job_card.job_card_number}`} className="text-blue-600 hover:underline">
                                                #{v.linked_job_card.job_card_number}
                                            </Link>
                                        ) : '—'}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                </div>
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

/**
 * `/batch-invoices/:id` — links made before multi-vehicle invoices had MVI numbers —
 * forwards to the numbered page.
 */
export function LegacyBatchRedirect() {
    const { id } = useParams()
    const isNew = id === 'new'
    const { data: batchNumber, isLoading } = useBatchNumberById(isNew ? null : id)
    if (isNew) return <Navigate to="/multi-vehicle-invoices/new" replace />
    if (isLoading) return <TicketDetailSkeleton />
    return <Navigate to={batchNumber ? batchPath(batchNumber) : '/outsource-invoices'} replace />
}
