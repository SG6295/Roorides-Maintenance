import { useState, useEffect } from 'react'
import { Fragment } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { format } from 'date-fns'
import { Listbox, ListboxButton, ListboxOption, ListboxOptions, Transition } from '@headlessui/react'
import { useAuth } from '../hooks/useAuth'
import { useJobCard, useUpdateJobCard } from '../hooks/useJobCards'
import { useParts } from '../hooks/useParts'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import { supabase } from '../lib/supabase'
import IssueWorkCard from '../components/job-cards/IssueWorkCard'

import {
    UserIcon,
    TruckIcon,
    PencilIcon,
    ClipboardDocumentListIcon,
} from '@heroicons/react/24/outline'
import { ChevronUpDownIcon, CheckIcon } from '@heroicons/react/20/solid'

export default function JobCardDetail() {
    const { id } = useParams()
    const { userProfile } = useAuth()

    const { data: jobCard, isLoading } = useJobCard(id)
    const updateJobCard = useUpdateJobCard()
    const { data: parts = [] } = useParts()

    const isExec = userProfile?.role === 'maintenance_exec'
    const isMechanic = userProfile?.role === 'mechanic' || userProfile?.role === 'maintenance_exec'

    const [remarks, setRemarks] = useState('')
    const [assigningMechanic, setAssigningMechanic] = useState(false)
    const [selectedMechanicId, setSelectedMechanicId] = useState('')

    useEffect(() => {
        if (jobCard) {
            setRemarks(jobCard.remarks || '')
            setSelectedMechanicId(jobCard.assigned_mechanic_id || '')
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

    if (isLoading) return <TicketDetailSkeleton />
    if (!jobCard) return <div className="p-8 text-center">Job Card not found</div>

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

    const handleCompleteJobCard = async () => {
        if (!confirm('Are you sure you want to complete this Job Card? Ensure all work is done.')) return
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { status: 'Completed', completed_at: new Date().toISOString(), remarks }
            })
            alert('Job Card Completed!')
        } catch (e) {
            alert('Failed to complete job card')
        }
    }

    const handleReopenJobCard = async () => {
        if (!confirm('Reopen this Job Card? This will allow parts and labour to be updated.')) return
        try {
            await updateJobCard.mutateAsync({
                id: jobCard.id,
                updates: { status: 'Open', completed_at: null }
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

    const totalIssues = jobCard.issues?.length || 0
    const completedIssues = jobCard.issues?.filter(i => i.status === 'Done').length || 0
    const progress = totalIssues > 0 ? (completedIssues / totalIssues) * 100 : 0
    const isAllDone = totalIssues > 0 && totalIssues === completedIssues

    const assignedName = jobCard.type === 'InHouse'
        ? (jobCard.mechanic?.name || 'Unassigned')
        : (jobCard.vendor_name || 'No vendor')

    return (
        <div className="min-h-screen bg-gray-50 pb-16">
            <Navigation
                breadcrumbs={[
                    { label: 'Job Cards', href: '/job-cards' },
                    { label: `Job Card #${jobCard.job_card_number}` },
                ]}
            />

            <div className="max-w-2xl mx-auto px-4 py-4 space-y-4">

                {/* Header Card */}
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
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                            <TruckIcon className="w-4 h-4 text-gray-600" />
                            {jobCard.vehicle_number}
                        </span>

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
                                                        <ListboxOption value="" className={({ active }) => `relative cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-600'}`}>
                                                            {({ selected, active }) => (<>
                                                                <span className={selected ? 'font-semibold' : 'font-normal'}>Unassigned</span>
                                                                {selected && <span className={`absolute inset-y-0 right-0 flex items-center pr-3 ${active ? 'text-white' : 'text-blue-600'}`}><CheckIcon className="h-4 w-4" /></span>}
                                                            </>)}
                                                        </ListboxOption>
                                                        {mechanics.map(m => (
                                                            <ListboxOption key={m.id} value={m.id} className={({ active }) => `relative cursor-default select-none py-2 pl-3 pr-9 ${active ? 'bg-blue-600 text-white' : 'text-gray-900'}`}>
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
                                        <button onClick={handleAssignMechanic} disabled={updateJobCard.isPending} className="text-xs px-2 py-0.5 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50">Save</button>
                                        <button onClick={() => { setAssigningMechanic(false); setSelectedMechanicId(jobCard.assigned_mechanic_id || '') }} className="text-xs px-2 py-0.5 bg-gray-200 text-gray-600 rounded hover:bg-gray-300">Cancel</button>
                                    </span>
                                ) : (
                                    <span className="flex items-center gap-1">
                                        {assignedName}
                                        {isExec && jobCard.status !== 'Completed' && (
                                            <button onClick={() => setAssigningMechanic(true)} className="ml-1 text-gray-500 hover:text-blue-600">
                                                <PencilIcon className="w-3.5 h-3.5" />
                                            </button>
                                        )}
                                    </span>
                                )}
                            </span>
                        ) : (
                            <span className="inline-flex items-center gap-1.5 px-3 py-1 bg-gray-100 rounded-full text-sm text-gray-700">
                                <UserIcon className="w-4 h-4 text-gray-600" />
                                {jobCard.vendor_name || 'No vendor'}
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

                {/* Work Items */}
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
                                />
                            ))}
                        </div>
                    )}
                </div>

                {/* Execution Remarks */}
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

                {/* Complete Job Card — exec only */}
                {isExec && jobCard.status !== 'Completed' && (
                    <button
                        onClick={handleCompleteJobCard}
                        disabled={!isAllDone || updateJobCard.isPending}
                        title={!isAllDone ? "Mark all issues as Done first" : ""}
                        className={`w-full py-4 rounded-xl text-base font-semibold text-white shadow-sm transition-colors ${
                            isAllDone
                                ? 'bg-green-600 hover:bg-green-700'
                                : 'bg-gray-300 cursor-not-allowed'
                        }`}
                    >
                        Complete Job Card
                    </button>
                )}

                {/* Reopen Job Card — exec only */}
                {isExec && jobCard.status === 'Completed' && (
                    <button
                        onClick={handleReopenJobCard}
                        disabled={updateJobCard.isPending}
                        className="w-full py-4 rounded-xl text-base font-semibold text-orange-700 bg-orange-50 border border-orange-200 hover:bg-orange-100 shadow-sm transition-colors disabled:opacity-50"
                    >
                        Reopen Job Card
                    </button>
                )}

            </div>
        </div>
    )
}
