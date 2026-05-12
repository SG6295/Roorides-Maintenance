import { useState, useEffect } from 'react'
import { Fragment } from 'react'
import { useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Listbox, ListboxButton, ListboxOption, ListboxOptions, Transition } from '@headlessui/react'
import { useAuth } from '../hooks/useAuth'
import { useJobCard, useUpdateJobCard } from '../hooks/useJobCards'
import { useOutsourceInvoice, useUpsertOutsourceInvoice } from '../hooks/useOutsourceInvoices'
import { useApprovedSuppliers } from '../hooks/useSuppliers'
import { useParts } from '../hooks/useParts'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import SearchableSelect from '../components/shared/SearchableSelect'
import DocumentUpload from '../components/suppliers/DocumentUpload'
import QuickAddSupplierModal from '../components/suppliers/QuickAddSupplierModal'
import ScrapDecisionModal from '../components/job-cards/ScrapDecisionModal'
import { supabase } from '../lib/supabase'
import IssueWorkCard from '../components/job-cards/IssueWorkCard'

import {
    UserIcon,
    TruckIcon,
    PencilIcon,
    ClipboardDocumentListIcon,
} from '@heroicons/react/24/outline'
import { ChevronUpDownIcon, CheckIcon } from '@heroicons/react/20/solid'

const JOB_LOCATION_OPTIONS = [
    { value: 'InHouse', label: 'In-house' },
    { value: 'Outsource', label: 'Outsource' },
]

const QUICK_ADD_SENTINEL = '__quick_add__'

function validateInvoiceForm(f, today) {
    const errors = {}
    if (!f.dateOfActivity) errors.dateOfActivity = 'Required'
    else if (f.dateOfActivity > today) errors.dateOfActivity = 'Cannot be in the future'
    if (!f.invoiceNo.trim()) errors.invoiceNo = 'Required'
    else if (f.invoiceNo.trim().length > 50) errors.invoiceNo = 'Max 50 characters'
    if (!f.paidBy) errors.paidBy = 'Required'
    const iv = parseFloat(f.invoiceValue)
    if (f.invoiceValue === '' || isNaN(iv) || iv <= 0) errors.invoiceValue = 'Must be > 0'
    const aa = parseFloat(f.approvedAmount)
    if (f.approvedAmount === '' || isNaN(aa) || aa < 0) errors.approvedAmount = 'Must be ≥ 0'
    else if (!isNaN(iv) && aa > iv) errors.approvedAmount = 'Must be ≤ invoice value'
    const adv = parseFloat(f.advanceAmount)
    if (f.advanceAmount === '' || isNaN(adv) || adv < 0) errors.advanceAmount = 'Must be ≥ 0'
    else if (!isNaN(aa) && adv > aa) errors.advanceAmount = 'Must be ≤ approved amount'
    if (!f.paymentStatus) errors.paymentStatus = 'Required'
    if (!f.paybyDate) errors.paybyDate = 'Required'
    else if (f.dateOfActivity && f.paybyDate < f.dateOfActivity) errors.paybyDate = 'Must be ≥ date of activity'
    return errors
}

export default function JobCardDetail() {
    const { id } = useParams()
    const { userProfile } = useAuth()

    const { data: jobCard, isLoading } = useJobCard(id)
    const updateJobCard = useUpdateJobCard()
    const { data: parts = [] } = useParts()
    const { data: approvedSuppliers = [] } = useApprovedSuppliers()

    const isExec = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)
    const isMechanic = ['mechanic', 'electrician', 'maintenance_exec', 'super_admin'].includes(userProfile?.role)

    // Mechanic assignment
    const [remarks, setRemarks] = useState('')
    const [assigningMechanic, setAssigningMechanic] = useState(false)
    const [selectedMechanicId, setSelectedMechanicId] = useState('')

    // Job Location editing
    const [editingJobLocation, setEditingJobLocation] = useState(false)
    const [pendingType, setPendingType] = useState('')

    // Supplier assignment
    const [editingSupplier, setEditingSupplier] = useState(false)
    const [selectedSupplierId, setSelectedSupplierId] = useState('')
    const [showQuickAddModal, setShowQuickAddModal] = useState(false)
    const [showScrapModal, setShowScrapModal] = useState(false)
    const [scrapRaceError, setScrapRaceError] = useState(null)

    const [invoiceForm, setInvoiceForm] = useState({
        dateOfActivity: '',
        invoiceNo: '',
        paidBy: '',
        invoiceValue: '',
        approvedAmount: '',
        advanceAmount: '',
        paymentStatus: '',
        paybyDate: '',
    })
    const [showInvoiceErrors, setShowInvoiceErrors] = useState(false)

    const todayStr = new Date().toISOString().split('T')[0]

    useEffect(() => {
        if (jobCard) {
            setRemarks(jobCard.remarks || '')
            setSelectedMechanicId(jobCard.assigned_mechanic_id || '')
            setSelectedSupplierId(jobCard.supplier_id || '')
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

    useEffect(() => {
        if (!existingInvoice) return
        setInvoiceForm({
            dateOfActivity: existingInvoice.date_of_activity || '',
            invoiceNo: existingInvoice.invoice_no || '',
            paidBy: existingInvoice.paid_by || '',
            invoiceValue: existingInvoice.invoice_value != null ? String(existingInvoice.invoice_value) : '',
            approvedAmount: existingInvoice.approved_amount != null ? String(existingInvoice.approved_amount) : '',
            advanceAmount: existingInvoice.advance_amount != null ? String(existingInvoice.advance_amount) : '',
            paymentStatus: existingInvoice.payment_status || '',
            paybyDate: existingInvoice.payby_date || '',
        })
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

    const handleCompleteJobCard = async () => {
        if (jobCard.type === 'Outsource') {
            const errors = validateInvoiceForm(invoiceForm, todayStr)
            if (Object.keys(errors).length > 0) {
                setShowInvoiceErrors(true)
                return
            }
            try {
                await upsertInvoice.mutateAsync({
                    jobCardId: jobCard.id,
                    userId: userProfile?.id,
                    data: {
                        date_of_activity: invoiceForm.dateOfActivity,
                        invoice_no: invoiceForm.invoiceNo.trim(),
                        paid_by: invoiceForm.paidBy,
                        invoice_value: parseFloat(invoiceForm.invoiceValue),
                        approved_amount: parseFloat(invoiceForm.approvedAmount),
                        advance_amount: parseFloat(invoiceForm.advanceAmount),
                        payment_status: invoiceForm.paymentStatus,
                        payby_date: invoiceForm.paybyDate,
                    },
                })
            } catch (e) {
                alert('Failed to save invoice details: ' + e.message)
                return
            }
        }
        setShowScrapModal(true)
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

    // ── Derived values ────────────────────────────────────────────────────────

    const totalIssues = jobCard.issues?.length || 0
    const completedIssues = jobCard.issues?.filter(i => i.status === 'Done').length || 0
    const progress = totalIssues > 0 ? (completedIssues / totalIssues) * 100 : 0
    const isAllDone = totalIssues > 0 && totalIssues === completedIssues
    const isOutsource = jobCard.type === 'Outsource'
    const needsInvoiceFile = isOutsource && !jobCard.invoice_url
    const invoiceErrs = isOutsource ? validateInvoiceForm(invoiceForm, todayStr) : {}
    const invoiceValid = Object.keys(invoiceErrs).length === 0
    const hasSupplier = isOutsource ? !!jobCard.supplier_id : true
    const hasPayments = (existingInvoice?.payments?.length ?? 0) > 0
    const payableAmount = (() => {
        const aa = parseFloat(invoiceForm.approvedAmount)
        const adv = parseFloat(invoiceForm.advanceAmount)
        return !isNaN(aa) && !isNaN(adv) ? aa - adv : null
    })()
    const canComplete = isAllDone && !needsInvoiceFile && invoiceValid && hasSupplier

    const jobLocationLabel = jobCard.type === 'InHouse' ? 'In-house' : 'Outsource'

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
                                    : 'bg-blue-100 text-blue-800'
                            }`}>
                                {jobCard.status}
                            </span>
                        </div>
                        <span className="text-xs text-gray-500">
                            {format(new Date(jobCard.created_at), 'MMM d, yyyy')}
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
                                    {isExec && jobCard.status !== 'Completed' && (
                                        <button
                                            onClick={() => { setPendingType(jobCard.type); setEditingJobLocation(true) }}
                                            className="text-gray-500 hover:text-blue-600"
                                        >
                                            <PencilIcon className="w-3.5 h-3.5" />
                                        </button>
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
                                        {isExec && jobCard.status !== 'Completed' && (
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
                            /* Outsource — supplier assignment */
                            <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                                <UserIcon className="w-4 h-4 text-gray-600" />
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
                                        {isExec && jobCard.status !== 'Completed' && (
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

                        {jobCard.status === 'Completed' ? (
                            /* Read-only display after closure */
                            <div className="grid grid-cols-2 gap-x-6 gap-y-3 text-sm">
                                {[
                                    ['Date of Activity', existingInvoice?.date_of_activity
                                        ? format(new Date(existingInvoice.date_of_activity), 'dd MMM yyyy')
                                        : '—'],
                                    ['Invoice No', existingInvoice?.invoice_no || '—'],
                                    ['Paid By', existingInvoice?.paid_by || '—'],
                                    ['Payment Status', existingInvoice?.payment_status || '—'],
                                    ['Invoice Value', existingInvoice?.invoice_value != null
                                        ? `₹${Number(existingInvoice.invoice_value).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                                        : '—'],
                                    ['Approved Amount', existingInvoice?.approved_amount != null
                                        ? `₹${Number(existingInvoice.approved_amount).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                                        : '—'],
                                    ['Advance Amount', existingInvoice?.advance_amount != null
                                        ? `₹${Number(existingInvoice.advance_amount).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                                        : '—'],
                                    ['Payable Amount', (existingInvoice?.approved_amount != null && existingInvoice?.advance_amount != null)
                                        ? `₹${Number(existingInvoice.approved_amount - existingInvoice.advance_amount).toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                                        : '—'],
                                    ['Pay By Date', existingInvoice?.payby_date
                                        ? format(new Date(existingInvoice.payby_date), 'dd MMM yyyy')
                                        : '—'],
                                ].map(([label, value]) => (
                                    <div key={label}>
                                        <p className="text-xs text-gray-500 mb-0.5">{label}</p>
                                        <p className="font-medium text-gray-900">{value}</p>
                                    </div>
                                ))}
                            </div>
                        ) : (
                            /* Editable form — shown while job card is Open */
                            <div className="space-y-3">
                                <div className="grid grid-cols-2 gap-3">
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Date of Activity <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            type="date"
                                            value={invoiceForm.dateOfActivity}
                                            max={todayStr}
                                            onChange={e => setInvoiceForm(f => ({ ...f, dateOfActivity: e.target.value }))}
                                            className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.dateOfActivity ? 'border-red-400' : 'border-gray-300'}`}
                                        />
                                        {showInvoiceErrors && invoiceErrs.dateOfActivity && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.dateOfActivity}</p>
                                        )}
                                    </div>
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Invoice No <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            type="text"
                                            value={invoiceForm.invoiceNo}
                                            maxLength={50}
                                            onChange={e => setInvoiceForm(f => ({ ...f, invoiceNo: e.target.value }))}
                                            placeholder="e.g. INV-2024-001"
                                            className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.invoiceNo ? 'border-red-400' : 'border-gray-300'}`}
                                        />
                                        {showInvoiceErrors && invoiceErrs.invoiceNo && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.invoiceNo}</p>
                                        )}
                                    </div>
                                </div>

                                <div className="grid grid-cols-2 gap-3">
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Paid By <span className="text-red-500">*</span>
                                        </label>
                                        <select
                                            value={invoiceForm.paidBy}
                                            onChange={e => setInvoiceForm(f => ({ ...f, paidBy: e.target.value }))}
                                            className={`w-full text-sm border rounded-lg px-3 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.paidBy ? 'border-red-400' : 'border-gray-300'}`}
                                        >
                                            <option value="">Select…</option>
                                            <option>Accounts</option>
                                            <option>Nithin</option>
                                            <option>Manjunath</option>
                                        </select>
                                        {showInvoiceErrors && invoiceErrs.paidBy && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.paidBy}</p>
                                        )}
                                    </div>
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Payment Status <span className="text-red-500">*</span>
                                        </label>
                                        <select
                                            value={invoiceForm.paymentStatus}
                                            onChange={e => setInvoiceForm(f => ({ ...f, paymentStatus: e.target.value }))}
                                            className={`w-full text-sm border rounded-lg px-3 py-2 bg-white focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.paymentStatus ? 'border-red-400' : 'border-gray-300'}`}
                                        >
                                            <option value="">Select…</option>
                                            <option>Approved</option>
                                            <option>Hold</option>
                                            <option>Reject</option>
                                        </select>
                                        {showInvoiceErrors && invoiceErrs.paymentStatus && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.paymentStatus}</p>
                                        )}
                                    </div>
                                </div>

                                <div className="grid grid-cols-2 gap-3">
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Invoice Value (₹) <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            type="number"
                                            min="0.01"
                                            step="0.01"
                                            value={invoiceForm.invoiceValue}
                                            onChange={e => setInvoiceForm(f => ({ ...f, invoiceValue: e.target.value }))}
                                            placeholder="0.00"
                                            className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.invoiceValue ? 'border-red-400' : 'border-gray-300'}`}
                                        />
                                        {showInvoiceErrors && invoiceErrs.invoiceValue && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.invoiceValue}</p>
                                        )}
                                    </div>
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Approved Amount (₹) <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            type="number"
                                            min="0"
                                            step="0.01"
                                            value={invoiceForm.approvedAmount}
                                            onChange={e => setInvoiceForm(f => ({ ...f, approvedAmount: e.target.value }))}
                                            placeholder="0.00"
                                            className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.approvedAmount ? 'border-red-400' : 'border-gray-300'}`}
                                        />
                                        {showInvoiceErrors && invoiceErrs.approvedAmount && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.approvedAmount}</p>
                                        )}
                                    </div>
                                </div>

                                <div className="grid grid-cols-2 gap-3">
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Advance Amount (₹) <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            type="number"
                                            min="0"
                                            step="0.01"
                                            value={invoiceForm.advanceAmount}
                                            onChange={e => setInvoiceForm(f => ({ ...f, advanceAmount: e.target.value }))}
                                            placeholder="0.00"
                                            className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.advanceAmount ? 'border-red-400' : 'border-gray-300'}`}
                                        />
                                        {showInvoiceErrors && invoiceErrs.advanceAmount && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.advanceAmount}</p>
                                        )}
                                    </div>
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Payable Amount (₹)
                                        </label>
                                        <div className="w-full text-sm border border-gray-200 rounded-lg px-3 py-2 bg-gray-50 font-medium text-gray-900 min-h-[38px]">
                                            {payableAmount !== null
                                                ? `₹${payableAmount.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
                                                : <span className="text-gray-400 font-normal">Auto-computed</span>
                                            }
                                        </div>
                                    </div>
                                </div>

                                <div className="grid grid-cols-2 gap-3">
                                    <div>
                                        <label className="block text-xs font-medium text-gray-600 mb-1">
                                            Pay By Date <span className="text-red-500">*</span>
                                        </label>
                                        <input
                                            type="date"
                                            value={invoiceForm.paybyDate}
                                            min={invoiceForm.dateOfActivity || undefined}
                                            onChange={e => setInvoiceForm(f => ({ ...f, paybyDate: e.target.value }))}
                                            className={`w-full text-sm border rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 ${showInvoiceErrors && invoiceErrs.paybyDate ? 'border-red-400' : 'border-gray-300'}`}
                                        />
                                        {showInvoiceErrors && invoiceErrs.paybyDate && (
                                            <p className="text-xs text-red-600 mt-0.5">{invoiceErrs.paybyDate}</p>
                                        )}
                                    </div>
                                </div>

                                {showInvoiceErrors && !jobCard.supplier_id && (
                                    <p className="text-xs text-red-600">
                                        A supplier must be assigned before completing this job card.
                                    </p>
                                )}
                            </div>
                        )}
                    </div>
                )}

                {/* ── Invoice file upload (Outsource only) ─────────────────── */}
                {jobCard.type === 'Outsource' && (
                    <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                        <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                            Invoice
                        </h2>
                        {jobCard.status === 'Completed' ? (
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
                                    required
                                    value={jobCard.invoice_url}
                                    onChange={(url) =>
                                        updateJobCard.mutate({ id: jobCard.id, updates: { invoice_url: url } })
                                    }
                                    accept=".pdf,.jpg,.jpeg,.png"
                                />
                                {!jobCard.invoice_url && (
                                    <p className="mt-2 text-xs text-amber-600 font-medium">
                                        Invoice upload required before completing this job card.
                                    </p>
                                )}
                            </>
                        )}
                    </div>
                )}

                {/* ── Execution Remarks ────────────────────────────────────── */}
                <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-4">
                    <h2 className="text-sm font-semibold text-gray-600 uppercase tracking-wider mb-3">
                        Execution Remarks
                    </h2>
                    {isMechanic && jobCard.status !== 'Completed' ? (
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

                {/* ── Complete Job Card — exec only ────────────────────────── */}
                {isExec && jobCard.status !== 'Completed' && (
                    <button
                        onClick={handleCompleteJobCard}
                        disabled={!canComplete || updateJobCard.isPending || upsertInvoice.isPending}
                        title={
                            !isAllDone
                                ? 'Mark all issues as Done first'
                                : needsInvoiceFile
                                ? 'Upload an invoice before completing'
                                : !hasSupplier
                                ? 'Assign a supplier before completing'
                                : !invoiceValid
                                ? 'Fill in all required invoice details'
                                : ''
                        }
                        className={`w-full py-4 rounded-xl text-base font-semibold text-white shadow-sm transition-colors ${
                            canComplete
                                ? 'bg-green-600 hover:bg-green-700'
                                : 'bg-gray-300 cursor-not-allowed'
                        }`}
                    >
                        {upsertInvoice.isPending ? 'Saving invoice…' : 'Complete Job Card'}
                    </button>
                )}

                {/* ── Reopen Job Card — exec only ──────────────────────────── */}
                {isExec && jobCard.status === 'Completed' && (
                    <>
                        {isOutsource && hasPayments && (
                            <p className="text-sm text-red-600 text-center px-4">
                                Cannot revert — payments have been recorded for this invoice. Contact finance to handle this manually.
                            </p>
                        )}
                        <button
                            onClick={handleReopenJobCard}
                            disabled={updateJobCard.isPending || (isOutsource && hasPayments)}
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
                    onClose={() => setShowScrapModal(false)}
                    onSuccess={() => setShowScrapModal(false)}
                    onRaceError={msg => { setShowScrapModal(false); setScrapRaceError(msg) }}
                />
            )}
        </div>
    )
}