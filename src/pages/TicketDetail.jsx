import { useState } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { useAuth } from '../hooks/useAuth'
import { useTicket, useUpdateTicket } from '../hooks/useTickets'
import { useIssues, useCreateIssue, useUpdateIssue, useDeleteIssue } from '../hooks/useIssues'
import { useJobCards, useCreateJobCard, useLinkIssuesToJobCard } from '../hooks/useJobCards'
import { getDriveThumbnailUrl } from '../lib/googleDrive'
import Navigation from '../components/shared/Navigation'
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import PhotoUpload from '../components/tickets/PhotoUpload'
import TicketTimeline from '../components/tickets/TicketTimeline'
import CustomSelect from '../components/shared/CustomSelect'
import CustomInput from '../components/shared/CustomInput'


// Icons
import {
  ClipboardDocumentCheckIcon,
  WrenchScrewdriverIcon,
  PhotoIcon,
  ChatBubbleBottomCenterTextIcon,
  PlusIcon,
  TrashIcon,
  ChevronDownIcon
} from '@heroicons/react/24/outline'
import { Menu, MenuButton, MenuItem, MenuItems, Transition } from '@headlessui/react'
import { Fragment } from 'react'

export default function TicketDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { userProfile } = useAuth()

  // Queries
  const { data: ticket, isLoading: ticketLoading } = useTicket(id)
  const { data: issues, isLoading: issuesLoading } = useIssues({ ticket_id: id })

  // State


  if (ticketLoading) {
    return <TicketDetailSkeleton />
  }

  if (!ticket) {
    return <div className="p-8 text-center">Ticket not found</div>
  }

  const isSupervisor = userProfile?.role === 'supervisor'
  const isExec = userProfile?.role === 'maintenance_exec'

  return (
    <div className="min-h-screen bg-gray-50 pb-12">
      <Navigation
        breadcrumbs={[
          { label: 'Tickets', href: '/tickets' },
          { label: `Ticket #${ticket.ticket_number}` },
        ]}
      />

      {/* Header */}
      <header className="bg-white border-b sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-4">
          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div className="flex items-center gap-4">
              <button onClick={() => navigate('/tickets')} className="text-gray-500 hover:text-gray-700">
                ← Back
              </button>
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-2xl font-bold text-gray-900">Ticket #{ticket.ticket_number}</h1>
                  <StatusBadge status={ticket.status} />
                </div>
                <p className="text-sm text-gray-500 mt-1">
                  Created {format(new Date(ticket.created_at), 'MMM d, yyyy')} by {ticket.supervisor_name}
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              {/* Actions */}
            </div>
          </div>

          {/* SLA Warning Banner */}
          <SLAWarning ticket={ticket} />
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-12">

        {/* Section 1: Overview */}
        <section id="overview" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <PhotoIcon className="w-6 h-6 text-gray-400" />
              Overview
            </h2>
          </div>
          <OverviewTab ticket={ticket} />
        </section>

        {/* Section 2: Issues */}
        <section id="issues" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <ClipboardDocumentCheckIcon className="w-6 h-6 text-gray-400" />
              Issues ({issues?.length || 0})
            </h2>
          </div>
          <IssuesTab ticket={ticket} issues={issues} canEdit={isExec} />
        </section>

        {/* Section 3: Job Cards */}
        <section id="job-cards" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <WrenchScrewdriverIcon className="w-6 h-6 text-gray-400" />
              Job Cards
            </h2>
          </div>
          <JobCardsTab ticket={ticket} issues={issues} />
        </section>

        {/* Section 4: History */}
        <section id="history" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <ChatBubbleBottomCenterTextIcon className="w-6 h-6 text-gray-400" />
              History
            </h2>
          </div>
          <TicketTimeline ticketId={ticket.id} />
        </section>

      </main>
    </div>
  )
}

// --- Sub Components ---


function StatusBadge({ status }) {
  const styles = {
    'Pending': 'bg-yellow-100 text-yellow-800',
    'Accepted': 'bg-blue-100 text-blue-800',
    'Work in Progress': 'bg-purple-100 text-purple-800',
    'Resolved': 'bg-green-100 text-green-800',
    'Closed': 'bg-gray-100 text-gray-800',
    'Rejected': 'bg-red-100 text-red-800'
  }
  return (
    <span className={`px-2.5 py-0.5 rounded-full text-xs font-medium ${styles[status] || 'bg-gray-100 text-gray-800'}`}>
      {status}
    </span>
  )
}

function SLAWarning({ ticket }) {
  if (!ticket.final_sla_end_date) return null

  const today = new Date()
  const end = new Date(ticket.final_sla_end_date)
  const diffDays = Math.ceil((end - today) / (1000 * 60 * 60 * 24))

  if (ticket.status === 'Resolved' || ticket.status === 'Closed') return null

  if (diffDays < 0) {
    return (
      <div className="mt-4 bg-red-50 border-l-4 border-red-500 p-4">
        <div className="flex">
          <div className="ml-3">
            <p className="text-sm text-red-700">
              <span className="font-bold">SLA Violation:</span> This ticket is overdue by {Math.abs(diffDays)} days.
            </p>
          </div>
        </div>
      </div>
    )
  }

  if (diffDays <= 2) {
    return (
      <div className="mt-4 bg-yellow-50 border-l-4 border-yellow-400 p-4">
        <div className="flex">
          <div className="ml-3">
            <p className="text-sm text-yellow-700">
              <span className="font-bold">SLA Warning:</span> Due in {diffDays} days ({format(end, 'MMM d')}).
            </p>
          </div>
        </div>
      </div>
    )
  }

  return null
}

function OverviewTab({ ticket }) {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
      {/* Left Column: Details */}
      <div className="lg:col-span-2 space-y-6">
        <div className="bg-white rounded-lg shadow-sm p-6">
          <h2 className="text-lg font-semibold mb-4">Initial Report</h2>
          <div className="prose prose-sm text-gray-600 bg-gray-50 p-4 rounded-md">
            {ticket.initial_remarks || ticket.complaint}
          </div>
        </div>

        {ticket.photos?.length > 0 && (
          <div className="bg-white rounded-lg shadow-sm p-6">
            <h2 className="text-lg font-semibold mb-4">Photos</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {ticket.photos.map((p, i) => (
                <a key={i} href={p} target="_blank" rel="noreferrer" className="block aspect-square bg-gray-100 rounded overflow-hidden">
                  <img src={getDriveThumbnailUrl(p)} alt="" className="w-full h-full object-cover" />
                </a>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Right Column: Metadata */}
      <div className="space-y-6">
        <div className="bg-white rounded-lg shadow-sm p-6">
          <h3 className="text-sm font-medium text-gray-500 uppercase tracking-wider mb-4">Details</h3>
          <dl className="space-y-4">
            <div>
              <dt className="text-xs text-gray-500">Vehicle</dt>
              <dd className="text-sm font-medium text-gray-900">{ticket.vehicle_number}</dd>
            </div>
            <div>
              <dt className="text-xs text-gray-500">Site</dt>
              <dd className="text-sm font-medium text-gray-900">{ticket.site}</dd>
            </div>
            <div>
              <dt className="text-xs text-gray-500">Supervisor</dt>
              <dd className="text-sm font-medium text-gray-900">
                {ticket.supervisor_name}
                <span className="block text-xs text-gray-400">{ticket.supervisor_contact}</span>
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
  )
}

function IssuesTab({ ticket, issues, canEdit }) {
  const navigate = useNavigate()
  const createIssue = useCreateIssue()
  const updateIssue = useUpdateIssue()
  const deleteIssue = useDeleteIssue()
  const createJobCard = useCreateJobCard()
  const linkIssues = useLinkIssuesToJobCard()
  const { data: jobCards } = useJobCards({ vehicle_number: ticket.vehicle_number })

  // Selection State
  const [selectedIssueIds, setSelectedIssueIds] = useState(new Set())

  // Inline Form State
  const [newIssue, setNewIssue] = useState({
    description: '',
    category: null,
    severity: null,
    work_type: 'InHouse'
  })

  // Toggle Selection
  const toggleSelect = (id) => {
    const newSet = new Set(selectedIssueIds)
    if (newSet.has(id)) {
      newSet.delete(id)
    } else {
      newSet.add(id)
    }
    setSelectedIssueIds(newSet)
  }

  // Toggle All
  const toggleSelectAll = () => {
    if (selectedIssueIds.size === unassignedIssues.length) {
      setSelectedIssueIds(new Set())
    } else {
      setSelectedIssueIds(new Set(unassignedIssues.map(i => i.id)))
    }
  }

  // Handle Create Issue
  const handleCreate = async () => {
    if (!newIssue.description) return
    try {
      await createIssue.mutateAsync({
        ticket_id: ticket.id,
        ...newIssue
      })
      setNewIssue({ description: '', category: null, severity: null, work_type: 'InHouse' })
    } catch (e) {
      alert(e.message)
    }
  }

  // Handle Bulk Delete
  const handleDeleteSelected = async () => {
    if (!window.confirm(`Are you sure you want to delete ${selectedIssueIds.size} issues?`)) return

    try {
      // Execute all deletes
      await Promise.all(Array.from(selectedIssueIds).map(id => deleteIssue.mutateAsync(id)))
      setSelectedIssueIds(new Set())
    } catch (e) {
      console.error("Delete error:", e)
      alert("Failed to delete issues")
    }
  }

  // Handle Create Job Card
  const handleCreateJobCard = async () => {
    if (selectedIssueIds.size === 0) return

    // Default to InHouse, user can change later
    const jobCardData = {
      type: 'InHouse',
      site: ticket.site,
      vehicle_number: ticket.vehicle_number,
      status: 'Open'
    }

    try {
      const newJC = await createJobCard.mutateAsync({
        jobCardData,
        issueIds: Array.from(selectedIssueIds)
      })

      setSelectedIssueIds(new Set()) // Clear selection
      alert('Job Card created successfully!')
      // Optionally navigate to it
      // navigate(`/job-cards/${newJC.id}`)
    } catch (e) {
      console.error("Job Card Error:", e)
      alert(e.message || 'Failed to create Job Card')
    }
  }

  // Handle Add to Existing Job Card
  const handleAddToJobCard = async (jobCardId) => {
    if (selectedIssueIds.size === 0) return

    try {
      await linkIssues.mutateAsync({
        jobCardId,
        issueIds: Array.from(selectedIssueIds)
      })
      setSelectedIssueIds(new Set())
      alert('Issues added to Job Card successfully!')
    } catch (e) {
      console.error("Link Error", e)
      alert(e.message || 'Failed to link issues')
    }
  }

  const openJobCards = jobCards?.filter(jc => jc.status !== 'Closed' && jc.status !== 'Deleted') || []

  // Handle Unassign Job Card
  const handleUnassign = async (issueId) => {
    if (!window.confirm('Are you sure you want to remove this issue from the Job Card?')) return

    try {
      await updateIssue.mutateAsync({
        id: issueId,
        updates: { job_card_id: null, status: 'Open' } // Reset status to Open? Verify workflow.
      })
    } catch (e) {
      alert(e.message)
    }
  }

  const unassignedIssues = issues?.filter(i => !i.job_card_id) || []
  const assignedIssues = issues?.filter(i => i.job_card_id) || []
  const allIssues = [...unassignedIssues, ...assignedIssues]

  return (
    <div className="space-y-6">
      {/* Header Actions */}
      <div className="flex justify-between items-center bg-gray-50 p-4 rounded-lg border border-gray-200">
        <div className="flex items-center gap-4">
          {selectedIssueIds.size > 0 ? (
            <span className="text-sm font-medium text-blue-700 bg-blue-50 px-3 py-1 rounded-full border border-blue-200">
              {selectedIssueIds.size} selected
            </span>
          ) : (
            <span className="text-sm text-gray-500">Select issues to perform an action</span>
          )}
        </div>

        {canEdit && (
          <div className="flex items-center gap-2">

            <Menu as="div" className="relative inline-block text-left">
              <div>
                <MenuButton
                  disabled={selectedIssueIds.size === 0}
                  className="flex items-center gap-2 bg-gray-900 text-white px-4 py-2 rounded-lg hover:bg-gray-800 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
                >
                  <WrenchScrewdriverIcon className="w-4 h-4" />
                  Add to Job Card
                  <ChevronDownIcon className="w-4 h-4 ml-1" />
                </MenuButton>
              </div>
              <Transition
                as={Fragment}
                enter="transition ease-out duration-100"
                enterFrom="transform opacity-0 scale-95"
                enterTo="transform opacity-100 scale-100"
                leave="transition ease-in duration-75"
                leaveFrom="transform opacity-100 scale-100"
                leaveTo="transform opacity-0 scale-95"
              >
                <MenuItems anchor="bottom end" className="absolute right-0 z-10 mt-2 w-56 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                  <div className="py-1">
                    {openJobCards.map((jc) => (
                      <MenuItem key={jc.id}>
                        {({ active }) => (
                          <button
                            onClick={() => handleAddToJobCard(jc.id)}
                            className={`${active ? 'bg-gray-100 text-gray-900' : 'text-gray-700'
                              } block w-full px-4 py-2 text-left text-sm`}
                          >
                            #{jc.job_card_number} <span className="text-gray-400 text-xs">({jc.status})</span>
                          </button>
                        )}
                      </MenuItem>
                    ))}
                    {openJobCards.length > 0 && <div className="border-t border-gray-100 my-1"></div>}
                    <MenuItem>
                      {({ active }) => (
                        <button
                          onClick={handleCreateJobCard}
                          className={`${active ? 'bg-blue-50 text-blue-700' : 'text-blue-600'
                            } block w-full px-4 py-2 text-left text-sm font-medium flex items-center gap-2`}
                        >
                          <PlusIcon className="w-4 h-4" /> Create New Job Card
                        </button>
                      )}
                    </MenuItem>
                  </div>
                </MenuItems>
              </Transition>
            </Menu>

            <button
              onClick={handleDeleteSelected}
              disabled={selectedIssueIds.size === 0 || deleteIssue.isPending}
              className="flex items-center gap-2 bg-white text-red-600 border border-red-200 px-4 py-2 rounded-lg hover:bg-red-50 disabled:opacity-50 disabled:cursor-not-allowed text-sm font-medium transition-colors"
              title="Delete Selected"
            >
              <TrashIcon className="w-4 h-4" />
              {deleteIssue.isPending ? 'Deleting...' : 'Delete'}
            </button>
          </div>
        )}
      </div>

      {/* Issues Table */}
      <div className="bg-white rounded-lg shadow-sm overflow-hidden border border-gray-200">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 w-12 text-center">
                {unassignedIssues.length > 0 && canEdit && (
                  <input
                    type="checkbox"
                    className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    checked={selectedIssueIds.size === unassignedIssues.length && unassignedIssues.length > 0}
                    onChange={toggleSelectAll}
                  />
                )}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ID</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-1/4">Description</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Category</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Severity</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Job Card</th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {allIssues.map(issue => {
              const isAssigned = !!issue.job_card_id
              return (
                <tr key={issue.id} className={isAssigned ? 'bg-gray-50/50' : 'hover:bg-gray-50'}>
                  <td className="px-4 py-4 text-center">
                    {!isAssigned && canEdit && (
                      <input
                        type="checkbox"
                        className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                        checked={selectedIssueIds.has(issue.id)}
                        onChange={() => toggleSelect(issue.id)}
                      />
                    )}
                  </td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{issue.issue_number}</td>
                  <td className="px-4 py-4 text-sm text-gray-700">{issue.description}</td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-500">{issue.category}</td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-500">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${issue.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-600'}`}>
                      {issue.severity}
                    </span>
                  </td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-500">
                    <span className={`px-2 py-1 rounded-full text-xs font-medium ${issue.status === 'Done' ? 'bg-green-100 text-green-800' : 'bg-blue-100 text-blue-800'}`}>
                      {issue.status}
                    </span>
                  </td>
                  <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-500">
                    {issue.job_card?.job_card_number ? (
                      <div className="flex items-center gap-2">
                        <Link to={`/job-cards/${issue.job_card.id}`} className="text-blue-600 hover:underline font-medium">
                          #{issue.job_card.job_card_number}
                        </Link>
                        {canEdit && (
                          <button
                            onClick={() => handleUnassign(issue.id)}
                            className="text-gray-400 hover:text-red-500 transition-colors p-1"
                            title="Unassign from Job Card"
                          >
                            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
                              <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                            </svg>
                          </button>
                        )}
                      </div>
                    ) : (
                      <span className="text-gray-400 italic text-xs">Unassigned</span>
                    )}
                  </td>
                </tr>
              )
            })}

            {/* INLINE CREATE ROW */}
            {canEdit && (
              <tr className="bg-blue-50/30">
                <td className="px-4 py-4"></td>
                <td className="px-4 py-4 font-mono text-xs text-gray-400">NEW</td>
                <td className="px-4 py-2">
                  <CustomInput
                    placeholder="Description..."
                    value={newIssue.description}
                    onChange={e => setNewIssue({ ...newIssue, description: e.target.value })}
                    onKeyDown={e => e.key === 'Enter' && handleCreate()}
                  />
                </td>
                <td className="px-4 py-2">
                  <CustomSelect
                    value={newIssue.category}
                    onChange={val => setNewIssue({ ...newIssue, category: val })}
                    options={['Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS', 'AdBlue', 'Other']}
                    placeholder="Select"
                  />
                </td>
                <td className="px-4 py-2">
                  <CustomSelect
                    value={newIssue.severity}
                    onChange={val => setNewIssue({ ...newIssue, severity: val })}
                    options={['Minor', 'Major']}
                    placeholder="Select"
                  />
                </td>
                <td className="px-4 py-2" colSpan={2}>
                  <button
                    onClick={handleCreate}
                    disabled={!newIssue.description || !newIssue.category || !newIssue.severity || createIssue.isPending}
                    className="w-full bg-blue-600 text-white rounded-md px-4 py-2 text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed flex justify-center items-center gap-2"
                  >
                    {createIssue.isPending ? '...' : <><PlusIcon className="w-4 h-4" /> Add Issue</>}
                  </button>
                </td>
              </tr>
            )}

            {allIssues.length === 0 && !canEdit && (
              <tr>
                <td colSpan={7} className="px-6 py-8 text-center text-gray-500 italic">No issues recorded.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function JobCardsTab({ ticket, issues }) {
  // Derive job cards from issues (since generic useJobCards query might be too broad, or we can fetch only related ones)
  // Or better, fetch distinct job_cards linked to these issues

  // Group issues by job card
  const jobCardsMap = new Map()

  issues?.forEach(issue => {
    if (issue.job_card && issue.job_card.id) {
      if (!jobCardsMap.has(issue.job_card.id)) {
        jobCardsMap.set(issue.job_card.id, {
          ...issue.job_card,
          issues: []
        })
      }
      jobCardsMap.get(issue.job_card.id).issues.push(issue)
    }
  })

  const jobCards = Array.from(jobCardsMap.values())

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-lg font-semibold">Active Job Cards</h2>
        {/* Button to create Job Card from Unassigned issues could go here */}
      </div>

      {jobCards.length === 0 ? (
        <div className="bg-white p-12 text-center text-gray-500 rounded-lg border border-dashed border-gray-300">
          No Job Cards created. Go to "Issues" tab to select issues and assign them.
        </div>
      ) : (
        <div className="grid gap-6">
          {jobCards.map(jc => (
            <div key={jc.id} className="bg-white border rounded-lg p-6 shadow-sm">
              <div className="flex justify-between items-start mb-4">
                <div>
                  <h3 className="text-lg font-medium text-gray-900">
                    <Link to={`/job-cards/${jc.id}`} className="hover:underline text-blue-600">
                      Job Card #{jc.job_card_number}
                    </Link>
                  </h3>
                  <p className="text-sm text-gray-500">{jc.type} • {format(new Date(jc.created_at), 'MMM d, yyyy')}</p>
                </div>
                <StatusBadge status={jc.status} />
              </div>

              <div className="bg-gray-50 rounded p-4 mb-4">
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Assigned To</h4>
                {jc.type === 'InHouse' ? (
                  <div className="flex items-center gap-2">
                    <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center text-blue-700 font-bold">
                      M
                    </div>
                    <div>
                      <p className="text-sm font-medium text-gray-900">Mechanic Name</p>
                      {/* Name not available in issue.job_card expansion usually unless deeper nested. Need separate fetch or robust cache. */}
                    </div>
                  </div>
                ) : (
                  <div>
                    <p className="text-sm font-medium text-gray-900">{jc.vendor_name}</p>
                    <p className="text-xs text-gray-500">External Vendor</p>
                  </div>
                )}
              </div>

              <div>
                <h4 className="text-xs font-semibold text-gray-500 uppercase mb-2">Included Issues</h4>
                <ul className="list-disc list-inside text-sm text-gray-700 space-y-1">
                  {jc.issues.map(i => (
                    <li key={i.id}>{i.description} <span className="text-gray-400">({i.category})</span></li>
                  ))}
                </ul>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
