import { useState, useEffect } from 'react'
import { Fragment } from 'react'
import { useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { formatAs, todayLocal } from '../utils/datetime'
import { Listbox, ListboxButton, ListboxOption, ListboxOptions, Transition } from '@headlessui/react'
import { useAuth } from '../hooks/useAuth'
import { useJobCard, useUpdateJobCard } from '../hooks/useJobCards'
import { useOutsourceInvoice, useUpsertOutsourceInvoice, useFinalizeOutsourceInvoice } from '../hooks/useOutsourceInvoices'
import { useApprovedSuppliers } from '../hooks/useSuppliers'
import { usePartStock } from '../hooks/useInventory'
import { useWorkshopLocations } from '../hooks/useWorkshopLocations'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import SearchableSelect from '../components/shared/SearchableSelect'
import CustomSelect from '../components/shared/CustomSelect'
import InvoiceDetailsFields, { InvoiceDetailsReadOnly } from '../components/outsource-invoices/InvoiceDetailsFields'
import {
    EMPTY_INVOICE_FORM,
    invoiceFormFromRow,
    invoiceFormToRow,
    isInvoiceFormEmpty,
    validateInvoiceForm,
} from '../components/outsource-invoices/invoiceForm'
import DocumentUpload from '../components/suppliers/DocumentUpload'
import QuickAddSupplierModal from '../components/suppliers/QuickAddSupplierModal'
import ScrapDecisionModal from '../components/job-cards/ScrapDecisionModal'
import { supabase } from '../lib/supabase'
import IssueWorkCard from '../components/job-cards/IssueWorkCard'
import LinkedBatchInvoices from '../components/job-cards/LinkedBatchInvoices'
import { useJobCardBatchLines } from '../hooks/useBatchServices'
import { formatBatchNumber } from '../utils/batchNumber'

import {
    UserIcon,
    TruckIcon,
    PencilIcon,
    ClipboardDocumentListIcon,
    BuildingOffice2Icon,
    LockClosedIcon,
} from '@heroicons/react/24/outline'
import { ChevronUpDownIcon, CheckIcon } from '@heroicons/react/20/solid'

const JOB_LOCATION_OPTIONS = [
    { value: 'InHouse', label: 'In-house' },
    { value: 'Outsource', label: 'Outsource' },
]

const QUICK_ADD_SENTINEL = '__quick_add__'

export default function JobCardDetail() {
    const { id } = useParams()
    const { userProfile } = useAuth()

    const { data: jobCard, isLoading } = useJobCard(id)
    const updateJobCard = useUpdateJobCard()
    // In-house work draws from this card's workshop, so the picker must show that
    // workshop's stock rather than the company-wide total.
    const { data: parts = [] } = usePartStock(jobCard?.location_id)
    const { data: approvedSuppliers = [] } = useApprovedSuppliers()
    const { data: workshopLocations = [] } = useWorkshopLocations()

    const isExec = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)
    // Multi-vehicle invoice lines linked to this card (MAIN-112). While any exist the
    // card must stay outsourced; the database refuses the switch too.
    const { data: linkedBatchLines = [], isLoading: batchLinesLoading } = useJobCardBatchLines(jobCard?.id, { enabled: isExec })
    const isMechanic = ['mechanic', 'electrician', 'maintenance_exec', 'super_admin'].includes(userProfile?.role)

    // Mechanic assignment
    const [remarks, setRemarks] = useState('')
    const [assigningMechanic, setAssigningMechanic] = useState(false)
    const [selectedMechanicId, setSelectedMechanicId] = useState('')

    // Odometer editing
    const [editingOdometer, setEditingOdometer] = useState(false)
    const [odometerValue, setOdometerValue] = useState('')

    // Job Location editing
    const [editingJobLocation, setEditingJobLocation] = useState(false)
    const [pendingType, setPendingType] = useState('')

    // Workshop editing
    const [editingWorkshop, setEditingWorkshop] = useState(false)
    const [pendingWorkshopId, setPendingWorkshopId] = useState('')

    // Supplier assignment
    const [editingSupplier, setEditingSupplier] = useState(false)
    const [selectedSupplierId, setSelectedSupplierId] = useState('')
    const [showQuickAddModal, setShowQuickAddModal] = useState(false)
    const [showScrapModal, setShowScrapModal] = useState(false)
    const [invoicePendingMode, setInvoicePendingMode] = useState(false)
    const [scrapRaceError, setScrapRaceError] = useState(null)

    const [invoiceForm, setInvoiceForm] = useState(EMPTY_INVOICE_FORM)
    const [showInvoiceErrors, setShowInvoiceErrors] = useState(false)

    // Local, not UTC: toISOString() still says yesterday until 05:30 IST, which caps the
    // date picker a day short and rejects an invoice dated today.
    const todayStr = todayLocal()

    useEffect(() => {
        if (jobCard) {
            setRemarks(jobCard.remarks || '')
            setSelectedMechanicId(jobCard.assigned_mechanic_id || '')
            setSelectedSupplierId(jobCard.supplier_id || '')
            setOdometerValue(jobCard.odometer != null ? String(jobCard.odometer) : '')
        }
    }, [jobCard])

    const { data: mechanics = [] } = useQuery({
        queryKey: ['mechanics'],
        queryFn: async () => {
            const { data, error } = await supabase
                .from('users')
                .select('id, name, contact')
                .eq('role', 'mechanic')
                .eq('is_active', true)
                .order('name')
            if (error) throw error
            return data
        },
        enabled: isExec,
    })

    const { data: existingInvoice } = useOutsourceInvoice(
        jobCard?.type === 'Outsource' ? jobCard?.id : null
    )
    const upsertInvoice = useUpsertOutsourceInvoice()
    const finalizeInvoice = useFinalizeOutsourceInvoice()

    useEffect(() => {
        if (!existingInvoice) return
        setInvoiceForm(invoiceFormFromRow(existingInvoice))
    }, [existingInvoice])

    if (isLoading) return <TicketDetailSkeleton />
    if (!jobCard) return <div className="p-8 text-center">Job Card not found</div>

    // ── Handlers ──────────────────────────────────────────────────────────────

    const handleAssignMechanic = async () => {
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { assigned_mechanic_id: selectedMechanicId || null }
            })
            setAssigningMechanic(false)
        } catch (e) {
            alert('Failed to assign mechanic: ' + e.message)
        }
    }

    const handleSaveJobLocation = async () => {
        if (pendingType === jobCard.type) {
            setEditingJobLocation(false)
            return
        }
        try {
            if (pendingType === 'InHouse' && (jobCard.supplier_id || jobCard.invoice_url)) {
                if (!window.confirm('This will clear the assigned supplier and invoice. Continue?')) return
                await updateJobCard.mutateAsync({
                    id: jobCard.id,
                    updates: { type: 'InHouse', supplier_id: null, invoice_url: null },
                })
            } else if (pendingType === 'Outsource' && jobCard.assigned_mechanic_id) {
                if (!window.confirm('This will clear the assigned mechanic. Continue?')) return
                await updateJobCard.mutateAsync({
                    id: jobCard.id,
                    updates: { type: 'Outsource', assigned_mechanic_id: null },
                })
            } else {
                await updateJobCard.mutateAsync({
                    id: jobCard.id,
                    updates: { type: pendingType },
                })
            }
            setEditingJobLocation(false)
        } catch (e) {
            alert('Failed to update job location: ' + e.message)
        }
    }

    const handleSaveWorkshop = async () => {
        if (!pendingWorkshopId || pendingWorkshopId === jobCard.location_id) {
            setEditingWorkshop(false)
            return
        }
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { location_id: pendingWorkshopId },
            })
            setEditingWorkshop(false)
        } catch (e) {
            // The DB refuses the move once parts have been issued from the old workshop.
            alert(e.message)
        }
    }

    const handleSupplierSelect = (value) => {
        if (value === QUICK_ADD_SENTINEL) {
            setShowQuickAddModal(true)
            return
        }
        setSelectedSupplierId(value)
    }

    const handleSaveSupplier = async () => {
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { supplier_id: selectedSupplierId || null },
            })
            setEditingSupplier(false)
        } catch (e) {
            alert('Failed to assign supplier: ' + e.message)
        }
    }

    const handleQuickAddSuccess = async (newSupplier) => {
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { supplier_id: newSupplier.id },
            })
            setEditingSupplier(false)
        } catch (e) {
            alert('Failed to link supplier: ' + e.message)
        }
    }

    // The invoice details are optional, but once started they must be complete — a half
    // invoice is never saved. Returns false when the form is incomplete or the save failed.
    const saveInvoiceIfEntered = async () => {
        if (isInvoiceFormEmpty(invoiceForm)) return true
        if (Object.keys(validateInvoiceForm(invoiceForm, todayStr)).length > 0) {
            setShowInvoiceErrors(true)
            return false
        }
        try {
            await upsertInvoice.mutateAsync({
                jobCardId: jobCard.id,
                userId: userProfile?.id,
                data: invoiceFormToRow(invoiceForm),
            })
            return true
        } catch (e) {
            alert('Failed to save invoice details: ' + e.message)
            return false
        }
    }

    const handleCompleteJobCard = async () => {
        if (jobCard.type === 'Outsource' && !(await saveInvoiceIfEntered())) return
        setInvoicePendingMode(closesAsInvoicePending)
        setShowScrapModal(true)
    }

    const handleFinalizeInvoice = async () => {
        if (!(await saveInvoiceIfEntered())) return
        try {
            await finalizeInvoice.mutateAsync({ jobCardId: jobCard.id })
        } catch (e) {
            alert('Failed to finalize invoice: ' + e.message)
        }
    }

    const handleReopenJobCard = async () => {
        if (!window.confirm('Reopen this Job Card? This will allow parts and labour to be updated.')) return
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { status: 'Open', completed_at: null },
            })
        } catch (e) {
            alert('Failed to reopen job card')
        }
    }

    const handleSaveRemarks = async () => {
        try {
            await updateJobCard.mutateAsync({ id: jobCard.id, updates: { remarks } })
            alert('Remarks saved')
        } catch (e) {
            alert('Failed to save')
        }
    }

    const handleSaveOdometer = async () => {
        const parsed = odometerValue === '' ? null : parseInt(odometerValue, 10)
        if (odometerValue !== '' && (isNaN(parsed) || parsed < 0)) return
        try {
            await updateJobCard.mutateAsync({ id: jobCard.id, updates: { odometer: parsed } })
            setEditingOdometer(false)
        } catch (e) {
            alert('Failed to save odometer: ' + e.message)
        }
    }

    // ── Derived values ────────────────────────────────────────────────────────

    const totalIssues = jobCard.issues?.length || 0
    const completedIssues = jobCard.issues?.filter(i => i.status === 'Done').length || 0
    const progress = totalIssues > 0 ? (completedIssues / totalIssues) * 100 : 0
    const isAllDone = totalIssues > 0 && totalIssues === completedIssues
    const isOutsource = jobCard.type === 'Outsource'
    const invoiceErrs = isOutsource ? validateInvoiceForm(invoiceForm, todayStr) : {}
    const invoiceValid = Object.keys(invoiceErrs).length === 0
    const invoicePartial = isOutsource && !invoiceValid && !isInvoiceFormEmpty(invoiceForm)
    const hasOwnInvoice = !!jobCard.invoice_url && invoiceValid
    // A linked multi-vehicle invoice line bills the work, so the card closes fully without
    // an invoice of its own. Otherwise a card without one closes as Invoice Pending.
    const isBatchLinked = linkedBatchLines.length > 0
    const closesAsInvoicePending = isOutsource && !hasOwnInvoice && !isBatchLinked
    const hasSupplier = isOutsource ? !!jobCard.supplier_id : true
    const supplierMissing = isExec && jobCard.status === 'Open' && !hasSupplier
    // A cancelled payment (failed transaction, refunded) does not lock the card.
    const hasPayments = (existingInvoice?.payments ?? []).some(p => p.status !== 'Cancelled')
    const canComplete = isAllDone && hasSupplier && !invoicePartial
    const isInvoicePending = jobCard.status === 'Completed - Invoice Pending'
    const canFinalize = isInvoicePending && !invoicePartial && (hasOwnInvoice || isBatchLinked)
    // Shown as text under the disabled button — a hover tooltip appears too slowly to help.
    const completeBlockedReason = !isAllDone
        ? 'Mark all issues as Done first'
        : !hasSupplier
        ? 'Assign a supplier before completing'
        : invoicePartial
        ? 'Finish the invoice details, or clear them to close as Invoice Pending'
        : ''
    const finalizeBlockedReason = canFinalize
        ? ''
        : invoicePartial
        ? 'Finish the invoice details, or clear them'
        : !jobCard.invoice_url
        ? 'Upload the invoice file first'
        : 'Fill in all required invoice details'
    // Only an exec can save the invoice details or upload the file (finance can view
    // the card but not write to it), so everyone else sees both read-only.
    const invoiceReadOnly = jobCard.status === 'Completed' || !isExec

    const jobLocationLabel = jobCard.type === 'InHouse' ? 'In-house' : 'Outsource'

    // Once an in-house card has issued parts, its stock has already left the current
    // workshop, so the DB refuses a move. Reflect that in the UI rather than letting
    // the exec try and hit an error.
    const workshopLocked =
        !isOutsource && (jobCard.issues || []).some(i => (i.issue_parts || []).length > 0)
    const typeLockedBy = isOutsource && linkedBatchLines.length > 0
        ? [...new Set(linkedBatchLines.map(l => formatBatchNumber(l.batch.batch_number)))].join(', ')
        : null

    return (
        <div className="min-h-screen bg-gray-50 pb-16">
            <Navigation
                breadcrumbs={[
                    { label: 'Job Cards', href: '/job-cards' },
                    { label: `Job Card #${jobCard.job_card_number}` },
                ]}
            />

            <div className="max-w-2xl mx-auto px-4 py-4 space-y-4">

                {scrapRaceError && (
                    <div className="rounded-lg bg-amber-50 border border-amber-200 px-4 py-3 flex items-start justify-between gap-3">
                        <p className="text-sm text-amber-800">{scrapRaceError}</p>
                        <button
                            type="button"
                            onClick={() => setScrapRaceError(null)}
                            className="text-amber-500 hover:text-amber-700 shrink-0 text-lg leading-none"
                        >
                            &times;
                        </button>
                    </div>
                )}

                {/* ── Header Card ──────────────────────────────────────────── */}
                <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">

                    {/* Title row */}
                    <div className="flex items-center justify-between mb-3">
                        <div className="flex items-center gap-2">
                            <h1 className="text-xl font-bold text-gray-900">
                                Job Card #{jobCard.job_card_number}
                            </h1>
                            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                                jobCard.status === 'Completed'
                                    ? 'bg-green-100 text-green-800'
                                    : jobCard.status === 'Completed - Invoice Pending'
                                    ? 'bg-amber-100 text-amber-800'
                                    : 'bg-blue-100 text-blue-800'
                            }`}>
                                {jobCard.status === 'Completed - Invoice Pending' ? 'Invoice Pending' : jobCard.status}
                            </span>
                        </div>
                        <span className="text-xs text-gray-500">
                            {formatAs(jobCard.created_at, 'MMM d, yyyy')}
                        </span>
                    </div>

                    {/* Info pills */}
                    <div className="flex flex-wrap gap-2 mb-4">

                        {/* Vehicle number — unchanged */}
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                            <TruckIcon className="w-4 h-4 text-gray-600" />
                            {jobCard.vehicle_number}
                        </span>

                        {/* ── Job Location pill ─────────────────────────────── */}
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                            {editingJobLocation ? (
                                <span className="flex items-center gap-2">
                                    <Listbox value={pendingType} onChange={setPendingType}>
                                        <div className="relative">
                                            <ListboxButton className="relative w-32 cursor-default rounded-md bg-white py-0.5 pl-2 pr-7 text-left text-sm border border-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500">
                                                <span className="block truncate text-gray-900">
                                                    {JOB_LOCATION_OPTIONS.find(o => o.value === pendingType)?.label}
                                                </span>
                                                <span className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-1.5">
                                                    <ChevronUpDownIcon className="h-4 w-4 text-gray-500" />
                                                </span>
                                            </ListboxButton>
                                            <Transition as={Fragment} leave="transition ease-in duration-100" leaveFrom="opacity-100" leaveTo="opacity-0">
                                                <ListboxOptions className="absolute z-50 mt-1 max-h-48 w-full overflow-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                                                    {JOB_LOCATION_OPTIONS.map(opt => (
                                                        <ListboxOption
                                                            key={opt.value}
                                                            value={opt.value}
                                                            className={({ active }) => `relative cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-900'}`}
                                                        >
                                                            {({ selected, active }) => (<>
                                                                <span className={selected ? 'font-semibold' : 'font-normal'}>{opt.label}</span>
                                                                {selected && (
                                                                    <span className={`absolute inset-y-0 right-0 flex items-center pr-3 ${active ? 'text-white' : 'text-blue-600'}`}>
                                                                        <CheckIcon className="h-4 w-4" />
                                                                    </span>
                                                                )}
                                                            </>)}
                                                        </ListboxOption>
                                                    ))}
                                                </ListboxOptions>
                                            </Transition>
                                        </div>
                                    </Listbox>
                                    <button
                                        onClick={handleSaveJobLocation}
                                        disabled={updateJobCard.isPending}
                                        className="text-xs px-2 py-0.5 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                                    >
                                        Save
                                    </button>
                                    <button
                                        onClick={() => setEditingJobLocation(false)}
                                        className="text-xs px-2 py-0.5 bg-gray-200 text-gray-600 rounded hover:bg-gray-300"
                                    >
                                        Cancel
                                    </button>
                                </span>
                            ) : (
                                <span className="flex items-center gap-1.5">
                                    <span className={`text-xs font-medium px-1.5 py-0.5 rounded ${
                                        jobCard.type === 'Outsource'
                                            ? 'bg-orange-100 text-orange-700'
                                            : 'bg-blue-100 text-blue-700'
                                    }`}>
                                        {jobLocationLabel}
                                    </span>
                                    {isExec && jobCard.status === 'Open' && (
                                        typeLockedBy ? (
                                            <LockClosedIcon
                                                className="w-3.5 h-3.5 text-gray-400"
                                                title={`Linked to multi-vehicle invoice ${typeLockedBy}, so it must stay outsourced. Remove the link on that invoice first.`}
                                            />
                                        ) : (
                                            <button
                                                onClick={() => { setPendingType(jobCard.type); setEditingJobLocation(true) }}
                                                className="text-gray-500 hover:text-blue-600"
                                            >
                                                <PencilIcon className="w-3.5 h-3.5" />
                                            </button>
                                        )
                                    )}
                                </span>
                            )}
                        </span>

                        {/* ── Workshop pill ──────────────────────────────────────
                            The workshop decides which stock this card draws from, so
                            once parts have been issued it is fixed — the deductions
                            already happened at the current workshop. */}
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                            <BuildingOffice2Icon className="w-4 h-4 text-gray-600" />
                            {editingWorkshop ? (
                                <span className="flex items-center gap-2">
                                    <Listbox value={pendingWorkshopId} onChange={setPendingWorkshopId}>
                                        <div className="relative">
                                            <ListboxButton className="relative w-40 cursor-default rounded-md bg-white py-0.5 pl-2 pr-7 text-left text-sm border border-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500">
                                                <span className="block truncate text-gray-900">
                                                    {workshopLocations.find(l => l.id === pendingWorkshopId)?.name || 'Select'}
                                                </span>
                                                <span className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-1.5">
                                                    <ChevronUpDownIcon className="h-4 w-4 text-gray-500" />
                                                </span>
                                            </ListboxButton>
                                            <Transition as={Fragment} leave="transition ease-in duration-100" leaveFrom="opacity-100" leaveTo="opacity-0">
                                                <ListboxOptions className="absolute z-50 mt-1 max-h-48 w-full overflow-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                                                    {workshopLocations.map(loc => (
                                                        <ListboxOption
                                                            key={loc.id}
                                                            value={loc.id}
                                                            className={({ active }) => `relative cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-900'}`}
                                                        >
                                                            {({ selected, active }) => (<>
                                                                <span className={selected ? 'font-semibold' : 'font-normal'}>{loc.name}</span>
                                                                {selected && (
                                                                    <span className={`absolute inset-y-0 right-0 flex items-center pr-3 ${active ? 'text-white' : 'text-blue-600'}`}>
                                                                        <CheckIcon className="h-4 w-4" />
                                                                    </span>
                                                                )}
                                                            </>)}
                                                        </ListboxOption>
                                                    ))}
                                                </ListboxOptions>
                                            </Transition>
                                        </div>
                                    </Listbox>
                                    <button
                                        onClick={handleSaveWorkshop}
                                        disabled={updateJobCard.isPending}
                                        className="text-xs px-2 py-0.5 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                                    >
                                        Save
                                    </button>
                                    <button
                                        onClick={() => setEditingWorkshop(false)}
                                        className="text-xs px-2 py-0.5 bg-gray-200 text-gray-600 rounded hover:bg-gray-300"
                                    >
                                        Cancel
                                    </button>
                                </span>
                            ) : (
                                <span className="flex items-center gap-1.5">
                                    {jobCard.location?.name || '—'}
                                    {isExec && jobCard.status === 'Open' && workshopLocations.length > 1 && (
                                        workshopLocked ? (
                                            <LockClosedIcon
                                                className="w-3.5 h-3.5 text-gray-400"
                                                title="Parts have already been issued from this workshop, so the job card can no longer be moved."
                                            />
                                        ) : (
                                            <button
                                                onClick={() => { setPendingWorkshopId(jobCard.location_id); setEditingWorkshop(true) }}
                                                className="text-gray-500 hover:text-blue-600"
                                            >
                                                <PencilIcon className="w-3.5 h-3.5" />
                                            </button>
                                        )
                                    )}
                                </span>
                            )}
                        </span>

                        {/* ── Assignment pill — mechanic or supplier ─────────── */}
                        {jobCard.type === 'InHouse' ? (
                            <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                                <UserIcon className="w-4 h-4 text-gray-600" />
                                {assigningMechanic ? (
                                    <span className="flex items-center gap-2">
                                        <Listbox value={selectedMechanicId} onChange={setSelectedMechanicId}>
                                            <div className="relative">
                                                <ListboxButton className="relative w-40 cursor-default rounded-md bg-white py-0.5 pl-2 pr-7 text-left text-sm border border-gray-300 focus:outline-none focus:ring-2 focus:ring-blue-500">
                                                    <span className="block truncate text-gray-900">
                                                        {selectedMechanicId
                                                            ? mechanics.find(m => m.id === selectedMechanicId)?.name
                                                            : 'Unassigned'}
                                                    </span>
                                                    <span className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-1.5">
                                                        <ChevronUpDownIcon className="h-4 w-4 text-gray-500" />
                                                    </span>
                                                </ListboxButton>
                                                <Transition as={Fragment} leave="transition ease-in duration-100" leaveFrom="opacity-100" leaveTo="opacity-0">
                                                    <ListboxOptions className="absolute z-50 mt-1 max-h-48 w-full overflow-auto rounded-md bg-white py-1 text-sm shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                                                        <ListboxOption
                                                            value=""
                                                            className={({ active }) => `relative cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-600'}`}
                                                        >
                                                            {({ selected, active }) => (<>
                                                                <span className={selected ? 'font-semibold' : 'font-normal'}>Unassigned</span>
                                                                {selected && <span className={`absolute inset-y-0 right-0 flex items-center pr-3 ${active ? 'text-white' : 'text-blue-600'}`}><CheckIcon className="h-4 w-4" /></span>}
                                                            </>)}
                                                        </ListboxOption>
                                                        {mechanics.map(m => (
                                                            <ListboxOption
                                                                key={m.id}
                                                                value={m.id}
                                                                className={({ active }) => `relative cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-900'}`}
                                                            >
                                                                {({ selected, active }) => (<>
                                                                    <span className={selected ? 'font-semibold' : 'font-normal'}>{m.name}</span>
                                                                    {selected && <span className={`absolute inset-y-0 right-0 flex items-center pr-3 ${active ? 'text-white' : 'text-blue-600'}`}><CheckIcon className="h-4 w-4" /></span>}
                                                                </>)}
                                                            </ListboxOption>
                                                        ))}
                                                    </ListboxOptions>
                                                </Transition>
                                            </div>
                                        </Listbox>
                                        <button
                                            onClick={handleAssignMechanic}
                                            disabled={updateJobCard.isPending}
                                            className="text-xs px-2 py-0.5 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                                        >
                                            Save
                                        </button>
                                        <button
                                            onClick={() => { setAssigningMechanic(false); setSelectedMechanicId(jobCard.assigned_mechanic_id || '') }}
                                            className="text-xs px-2 py-0.5 bg-gray-200 text-gray-600 rounded hover:bg-gray-300"
                                        >
                                            Cancel
                                        </button>
                                    </span>
                                ) : (
                                    <span className="flex items-center gap-1">
                                        {jobCard.mechanic?.name || 'Unassigned'}
                                        {isExec && jobCard.status === 'Open' && (
                                            <button
                                                onClick={() => setAssigningMechanic(true)}
                                                className="ml-1 text-gray-500 hover:text-blue-600"
                                            >
                                                <PencilIcon className="w-3.5 h-3.5" />
                                            </button>
                                        )}
                                    </span>
                                )}
                            </span>
                        ) : (
                            /* Outsource — supplier assignment; required to close, so a missing one is flagged */
                            <span className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-sm ${
                                supplierMissing
                                    ? 'bg-red-50 text-red-700 ring-1 ring-red-200'
                                    : 'bg-gray-100 text-gray-700'
                            }`}>
                                <UserIcon className={`w-4 h-4 ${supplierMissing ? 'text-red-500' : 'text-gray-600'}`} />
                                {editingSupplier ? (
                                    <span className="flex items-center gap-2">
                                        <div className="w-48">
                                            <SearchableSelect
                                                value={selectedSupplierId}
                                                onChange={handleSupplierSelect}
                                                options={approvedSuppliers.map(s => ({ value: s.id, label: s.entity_name }))}
                                                showAllOnFocus
                                                pinnedOption={{ value: QUICK_ADD_SENTINEL, label: '+ Quick Add Supplier' }}
                                                placeholder="Search suppliers..."
                                            />
                                        </div>
                                        <button
                                            onClick={handleSaveSupplier}
                                            disabled={updateJobCard.isPending}
                                            className="text-xs px-2 py-0.5 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                                        >
                                            Save
                                        </button>
                                        <button
                                            onClick={() => { setEditingSupplier(false); setSelectedSupplierId(jobCard.supplier_id || '') }}
                                            className="text-xs px-2 py-0.5 bg-gray-200 text-gray-600 rounded hover:bg-gray-300"
                                        >
                                            Cancel
                                        </button>
                                    </span>
                                ) : (
                                    <span className="flex items-center gap-1">
                                        {jobCard.supplier?.entity_name || 'No supplier'}
                                        {supplierMissing && <span className="text-red-500">*</span>}
                                        {isExec && jobCard.status === 'Open' && (
                                            <button
                                                onClick={() => setEditingSupplier(true)}
                                                className="ml-1 text-gray-500 hover:text-blue-600"
                                            >
                                                <PencilIcon className="w-3.5 h-3.5" />
                                            </button>
                                        )}
                                    </span>
                                )}
                            </span>
                        )}
                    </div>

                    {/* Odometer */}
                    <div className="flex items-center gap-2 mb-4 text-sm text-gray-700">
                        <span className="font-medium text-gray-500 text-xs uppercase tracking-wide w-20 shrink-0">Odometer</span>
                        {editingOdometer ? (
                            <span className="flex items-center gap-2">
                                <div className="flex items-center gap-1">
                                    <input
                                        type="number"
                                        min="0"
                                        step="1"
                                        value={odometerValue}
                                        onChange={e => setOdometerValue(e.target.value)}
                                        placeholder="e.g. 45000"
                                        className="w-32 text-sm border border-gray-300 rounded-lg px-2 py-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
                                        autoFocus
                                    />
                                    <span className="text-xs text-gray-500">km</span>
                                </div>
                                <button
                                    onClick={handleSaveOdometer}
                                    disabled={updateJobCard.isPending}
                                    className="text-xs px-2 py-0.5 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
                                >
                                    Save
                                </button>
                                <button
                                    onClick={() => { setEditingOdometer(false); setOdometerValue(jobCard.odometer != null ? String(jobCard.odometer) : '') }}
                                    className="text-xs px-2 py-0.5 bg-gray-200 text-gray-600 rounded hover:bg-gray-300"
                                >
                                    Cancel
                                </button>
                            </span>
                        ) : (
                            <span className="flex items-center gap-1.5">
                                <span className="text-gray-900">
                                    {jobCard.odometer != null ? `${jobCard.odometer.toLocaleString('en-IN')} km` : <span className="text-gray-400 italic">Not recorded</span>}
                                </span>
                                {isMechanic && jobCard.status === 'Open' && (
                                    <button
                                        onClick={() => setEditingOdometer(true)}
                                        className="text-gray-500 hover:text-blue-600"
                                    >
                                        <PencilIcon className="w-3.5 h-3.5" />
                                    </button>
                                )}
                            </span>
                        )}
                    </div>

                    {/* Progress bar */}
                    <div>
                        <div className="flex justify-between text-xs text-gray-600 mb-1">
                            <span>Progress</span>
                            <span>{completedIssues} of {totalIssues} done</span>
                        </div>
                        <div className="w-full bg-gray-200 rounded-full h-2">
                            <div
                                className="bg-green-500 h-2 rounded-full transition-all duration-500"
                                style={{ width: `${progress}%` }}
                            />
                        </div>
                    </div>
                </div>

                {/* ── Work Items ───────────────────────────────────────────── */}
                <div>
                    <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider px-1 mb-2">
                        Work Items
                    </h2>
                    {totalIssues === 0 ? (
                        <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-8 text-center">
                            <ClipboardDocumentListIcon className="w-10 h-10 text-gray-300 mx-auto mb-2" />
                            <p className="text-sm text-gray-500">No issues linked to this job card.</p>
                        </div>
                    ) : (
                        <div className="space-y-3">
                            {jobCard.issues.map(issue => (
                                <IssueWorkCard
                                    key={issue.id}
                                    issue={issue}
                                    jobCardId={id}
                                    jobCardStatus={jobCard.status}
                                    isMechanic={isMechanic}
                                    parts={parts}
                                    userProfile={userProfile}
                                    jobCardType={jobCard.type}
                                />
                            ))}
                        </div>
                    )}
                </div>

                {/* ── Invoice Details form (Outsource only) ────────────────── */}
                {isOutsource && (
                    <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                        <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                            Invoice Details
                        </h2>

                        {invoiceReadOnly ? (
                            /* Read-only display after full closure, or for non-execs */
                            <InvoiceDetailsReadOnly invoice={existingInvoice} />
                        ) : (
                            /* Editable form — shown while Open or Completed - Invoice Pending */
                            <InvoiceDetailsFields
                                form={invoiceForm}
                                setForm={setInvoiceForm}
                                errors={invoiceErrs}
                                showErrors={showInvoiceErrors}
                                todayStr={todayStr}
                                optional
                            >
                                {showInvoiceErrors && !jobCard.supplier_id && (
                                    <p className="text-xs text-red-600">
                                        A supplier must be assigned before completing this job card.
                                    </p>
                                )}
                            </InvoiceDetailsFields>
                        )}
                    </div>
                )}

                {/* ── Invoice file upload (Outsource only) ─────────────────── */}
                {jobCard.type === 'Outsource' && (
                    <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                        <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                            Invoice
                        </h2>
                        {invoiceReadOnly ? (
                            jobCard.invoice_url ? (
                                <a
                                    href={jobCard.invoice_url}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="inline-flex items-center gap-1.5 text-sm text-blue-600 hover:underline"
                                >
                                    View uploaded invoice →
                                </a>
                            ) : (
                                <p className="text-sm text-gray-400 italic">No invoice uploaded.</p>
                            )
                        ) : (
                            <>
                                <DocumentUpload
                                    label=""
                                    value={jobCard.invoice_url}
                                    onChange={(url) =>
                                        updateJobCard.mutate({ id: jobCard.id, updates: { invoice_url: url } })
                                    }
                                    accept=".pdf,.jpg,.jpeg,.png"
                                />
                                {!jobCard.invoice_url && !isBatchLinked && (
                                    <p className="mt-2 text-xs text-gray-500">
                                        {isInvoicePending
                                            ? 'Upload the invoice and fill in its details to finalize this job card.'
                                            : 'Optional — without an invoice the job card closes as Invoice Pending.'}
                                    </p>
                                )}
                            </>
                        )}
                    </div>
                )}

                {/* ── Multi-vehicle invoices linked to this card (MAIN-112) ── */}
                {isOutsource && (
                    <LinkedBatchInvoices
                        jobCardId={jobCard.id}
                        enabled={isExec || userProfile?.role === 'finance'}
                    />
                )}

                {/* ── Execution Remarks ────────────────────────────────────── */}
                <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                    <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                        Execution Remarks
                    </h2>
                    {isMechanic && jobCard.status === 'Open' ? (
                        <>
                            <textarea
                                value={remarks}
                                onChange={e => setRemarks(e.target.value)}
                                className="w-full rounded-lg border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 text-sm"
                                rows={4}
                                placeholder="Enter parts used, work details, or issues faced..."
                            />
                            <button
                                onClick={handleSaveRemarks}
                                className="mt-2 w-full py-2.5 text-sm font-medium text-blue-600 border border-blue-200 rounded-lg hover:bg-blue-50 transition-colors"
                            >
                                Save Remarks
                            </button>
                        </>
                    ) : (
                        <p className="text-sm text-gray-700 whitespace-pre-wrap">{remarks || 'No remarks.'}</p>
                    )}
                </div>

                {/* ── Complete Job Card — exec only, Open status only. An outsourced
                     card with no invoice (and no multi-vehicle invoice line) closes as
                     Invoice Pending instead. ─────────────────────────────────── */}
                {isExec && jobCard.status === 'Open' && (
                    <div>
                        <button
                            onClick={handleCompleteJobCard}
                            disabled={!canComplete || batchLinesLoading || updateJobCard.isPending || upsertInvoice.isPending}
                            className={`w-full py-4 rounded-xl text-base font-semibold text-white shadow-sm transition-colors ${
                                !canComplete
                                    ? 'bg-gray-300 cursor-not-allowed'
                                    : closesAsInvoicePending
                                    ? 'bg-amber-500 hover:bg-amber-600'
                                    : 'bg-green-600 hover:bg-green-700'
                            }`}
                        >
                            {upsertInvoice.isPending
                                ? 'Saving invoice…'
                                : closesAsInvoicePending
                                ? 'Close — Invoice Pending'
                                : 'Complete Job Card'}
                        </button>
                        {completeBlockedReason && (
                            <p className="mt-2 text-sm text-center text-gray-500">{completeBlockedReason}</p>
                        )}
                    </div>
                )}

                {/* ── Invoice Pending banner + Finalize button ─────────────── */}
                {isExec && isInvoicePending && (
                    <>
                        <div className="rounded-xl bg-amber-50 border border-amber-200 px-4 py-3">
                            <p className="text-sm text-amber-800 font-medium">Invoice not yet received</p>
                            <p className="text-xs text-amber-700 mt-0.5">
                                {isBatchLinked
                                    ? 'This job card is billed on a multi-vehicle invoice — click Finalize Invoice to fully close it.'
                                    : 'Upload the invoice file and fill in the invoice details above, or bill it on a multi-vehicle invoice, then click Finalize Invoice to fully close this job card.'}
                            </p>
                        </div>
                        <button
                            onClick={handleFinalizeInvoice}
                            disabled={!canFinalize || upsertInvoice.isPending || finalizeInvoice.isPending}
                            className={`w-full py-4 rounded-xl text-base font-semibold text-white shadow-sm transition-colors ${
                                canFinalize
                                    ? 'bg-green-600 hover:bg-green-700'
                                    : 'bg-gray-300 cursor-not-allowed'
                            }`}
                        >
                            {upsertInvoice.isPending || finalizeInvoice.isPending ? 'Saving…' : 'Finalize Invoice'}
                        </button>
                        {finalizeBlockedReason && (
                            <p className="-mt-1 text-sm text-center text-gray-500">{finalizeBlockedReason}</p>
                        )}
                    </>
                )}

                {/* ── Reopen Job Card — exec only ──────────────────────────── */}
                {isExec && (jobCard.status === 'Completed' || isInvoicePending) && (
                    <>
                        {isOutsource && hasPayments && jobCard.status === 'Completed' && (
                            <p className="text-sm text-red-600 text-center px-4">
                                Cannot revert — payments have been recorded for this invoice. Contact finance to handle this manually.
                            </p>
                        )}
                        <button
                            onClick={handleReopenJobCard}
                            disabled={updateJobCard.isPending || (isOutsource && hasPayments && jobCard.status === 'Completed')}
                            className="w-full py-4 rounded-xl text-base font-semibold text-orange-700 bg-orange-50 border border-orange-200 hover:bg-orange-100 shadow-sm transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            Reopen Job Card
                        </button>
                    </>
                )}

            </div>

            {/* ── Quick Add Supplier Modal ─────────────────────────────────── */}
            <QuickAddSupplierModal
                isOpen={showQuickAddModal}
                onClose={() => setShowQuickAddModal(false)}
                onSuccess={handleQuickAddSuccess}
            />

            {/* ── Scrap Decision Modal (job card closure) ───────────────────── */}
            {showScrapModal && (
                <ScrapDecisionModal
                    jobCard={jobCard}
                    invoicePending={invoicePendingMode}
                    onClose={() => { setShowScrapModal(false); setInvoicePendingMode(false) }}
                    onSuccess={() => { setShowScrapModal(false); setInvoicePendingMode(false) }}
                    onRaceError={msg => { setShowScrapModal(false); setInvoicePendingMode(false); setScrapRaceError(msg) }}
                />
            )}
        </div>
    )
}