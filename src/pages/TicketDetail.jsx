import { useState, useEffect } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { format } from 'date-fns'
import { useAuth } from '../hooks/useAuth'
import { useTicket, useUpdateTicket } from '../hooks/useTickets'
import { useIssues, useCreateIssue, useUpdateIssue, useDeleteIssue } from '../hooks/useIssues'
import { useJobCards, useCreateJobCard, useLinkIssuesToJobCard } from '../hooks/useJobCards'
import { getDriveThumbnailUrl } from '../lib/googleDrive'
import Navigation from '../components/shared/Navigation'
import SLATimer from '../components/shared/SLATimer'

const parseUTC = (ts) => ts ? new Date(ts.endsWith('Z') || ts.includes('+') ? ts : ts + 'Z') : null
import { TicketDetailSkeleton } from '../components/shared/LoadingSkeleton'
import PhotoUpload from '../components/tickets/PhotoUpload'
import TicketTimeline from '../components/tickets/TicketTimeline'
import CustomSelect from '../components/shared/CustomSelect'
import CustomInput from '../components/shared/CustomInput'
import RejectTicketModal from '../components/tickets/RejectTicketModal'
import FeedbackModal from '../components/tickets/FeedbackModal'


import {
  ClipboardDocumentCheckIcon,
  WrenchScrewdriverIcon,
  PhotoIcon,
  ChatBubbleBottomCenterTextIcon,
  PlusIcon,
  TrashIcon,
  ChevronDownIcon,
  PencilIcon,
  XMarkIcon,
  CheckIcon,
  NoSymbolIcon
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

  // Mutations
  const updateTicket = useUpdateTicket()

  // State
  const [isRejectModalOpen, setIsRejectModalOpen] = useState(false)


  if (ticketLoading) {
    return <TicketDetailSkeleton />
  }

  if (!ticket) {
    return <div className="p-8 text-center">Ticket not found</div>
  }

  const isSupervisor = userProfile?.role === 'supervisor'
  const isExec = ['maintenance_exec', 'super_admin'].includes(userProfile?.role)

  // Handle ticket rejection
  const handleRejectTicket = async ({ rejection_reason, rejection_comment }) => {
    try {
      await updateTicket.mutateAsync({
        id: ticket.id,
        updates: {
          status: 'Rejected',
          rejection_reason,
          rejection_comment
        }
      })
      setIsRejectModalOpen(false)
    } catch (e) {
      alert('Failed to reject ticket: ' + e.message)
    }
  }

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
              <button onClick={() => navigate('/tickets')} className="text-gray-600 hover:text-gray-700">
                ← Back
              </button>
              <div>
                <div className="flex items-center gap-2">
                  <h1 className="text-2xl font-bold text-gray-900">Ticket #{ticket.ticket_number}</h1>
                  <StatusBadge status={ticket.status} />
                </div>
                <p className="text-sm text-gray-600 mt-1">
                  Created {format(parseUTC(ticket.created_at), 'MMM d, yyyy')} by {ticket.supervisor_name}
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              {/* Status Actions Dropdown */}
              {isExec && ticket.status !== 'Rejected' && ticket.status !== 'Closed' && (
                <Menu as="div" className="relative inline-block text-left">
                  <MenuButton className="flex items-center gap-2 bg-white border border-gray-300 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-50 text-sm font-medium transition-colors">
                    Actions
                    <ChevronDownIcon className="w-4 h-4" />
                  </MenuButton>
                  <Transition
                    as={Fragment}
                    enter="transition ease-out duration-100"
                    enterFrom="transform opacity-0 scale-95"
                    enterTo="transform opacity-100 scale-100"
                    leave="transition ease-in duration-75"
                    leaveFrom="transform opacity-100 scale-100"
                    leaveTo="transform opacity-0 scale-95"
                  >
                    <MenuItems anchor="bottom end" className="absolute right-0 z-10 mt-2 w-48 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                      <div className="py-1">
                        <MenuItem>
                          {({ active }) => (
                            <button
                              onClick={() => setIsRejectModalOpen(true)}
                              className={`${active ? 'bg-red-50 text-red-700' : 'text-red-600'} flex items-center gap-2 w-full px-4 py-2 text-left text-sm`}
                            >
                              <NoSymbolIcon className="w-4 h-4" />
                              Reject Ticket
                            </button>
                          )}
                        </MenuItem>
                      </div>
                    </MenuItems>
                  </Transition>
                </Menu>
              )}
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
              <PhotoIcon className="w-6 h-6 text-gray-500" />
              Overview
            </h2>
          </div>
          <OverviewTab ticket={ticket} />
        </section>

        {/* Section 2: Issues */}
        <section id="issues" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <ClipboardDocumentCheckIcon className="w-6 h-6 text-gray-500" />
              Issues ({issues?.length || 0})
            </h2>
          </div>
          <IssuesTab ticket={ticket} issues={issues} canEdit={isExec} userProfile={userProfile} />
        </section>

        {/* Section 3: Job Cards */}
        <section id="job-cards" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <WrenchScrewdriverIcon className="w-6 h-6 text-gray-500" />
              Job Cards
            </h2>
          </div>
          <JobCardsTab ticket={ticket} issues={issues} />
        </section>

        {/* Section 4: History */}
        <section id="history" className="scroll-mt-20">
          <div className="border-b pb-4 mb-6">
            <h2 className="text-xl font-bold text-gray-900 flex items-center gap-2">
              <ChatBubbleBottomCenterTextIcon className="w-6 h-6 text-gray-500" />
              History
            </h2>
          </div>
          <TicketTimeline ticketId={ticket.id} />
        </section>

      </main>

      {/* Reject Ticket Modal */}
      <RejectTicketModal
        isOpen={isRejectModalOpen}
        onClose={() => setIsRejectModalOpen(false)}
        onConfirm={handleRejectTicket}
        isLoading={updateTicket.isPending}
      />
    </div>
  )
}

// --- Sub Components ---


function StatusBadge({ status }) {
  const styles = {
    'New': 'bg-yellow-100 text-yellow-800',
    'Pending': 'bg-yellow-100 text-yellow-800', // Legacy support
    'Accepted': 'bg-blue-100 text-blue-800',
    'Work In Progress': 'bg-purple-100 text-purple-800',
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

// Feedback Smileys Component - Enhanced with hover, creator-only, and modal
// Uses database columns: rating ('Good', 'Ok', 'Bad'), rating_remarks, rated_at
function FeedbackSmileys({ issue, ticket, userProfile, onUpdateFeedback, isUpdating }) {
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [hoveredSmiley, setHoveredSmiley] = useState(null)

  const smileys = [
    { value: 'Good', emoji: '😊', activeColor: 'text-green-500', label: 'Good' },
    { value: 'Ok', emoji: '😐', activeColor: 'text-yellow-500', label: 'Ok' },
    { value: 'Bad', emoji: '☹️', activeColor: 'text-red-500', label: 'Bad' }
  ]

  // Only ticket creator (supervisor who created the ticket) can give/edit feedback
  const isTicketCreator = ticket?.supervisor_id === userProfile?.employee_id
  const isDone = issue.status === 'Done'
  const hasRating = issue.rating !== null && issue.rating !== undefined
  const canInteract = isDone && isTicketCreator

  // Debug: log the comparison values
  console.log('FeedbackSmileys debug:', {
    'ticket.supervisor_id': ticket?.supervisor_id,
    'userProfile.employee_id': userProfile?.employee_id,
    isTicketCreator,
    isDone,
    hasRating
  })

  const handleSubmitFeedback = (feedbackData) => {
    onUpdateFeedback(feedbackData)
    setIsModalOpen(false)
  }

  // Show greyed out smileys if issue not done
  if (!isDone) {
    return (
      <div className="flex items-center gap-1">
        {smileys.map((s) => (
          <span
            key={s.value}
            className="text-gray-300 text-lg cursor-not-allowed grayscale opacity-50"
            title="Feedback available after issue is marked Done"
          >
            {s.emoji}
          </span>
        ))}
      </div>
    )
  }

  // Not ticket creator - show read-only (greyed if no rating, or show selected)
  if (!isTicketCreator) {
    return (
      <div className="flex items-center gap-1">
        {smileys.map((s) => (
          <span
            key={s.value}
            className={`text-lg transition-all ${hasRating && issue.rating === s.value
              ? s.activeColor
              : 'grayscale opacity-40 cursor-not-allowed'
              }`}
            title={hasRating && issue.rating === s.value
              ? `${s.label}${issue.rating_remarks ? `: ${issue.rating_remarks}` : ''}`
              : 'Only ticket creator can provide feedback'}
          >
            {s.emoji}
          </span>
        ))}
      </div>
    )
  }

  // Ticket creator - can interact (add or edit rating)
  return (
    <>
      <div className="flex items-center gap-1">
        {smileys.map((s) => (
          <button
            key={s.value}
            onClick={() => setIsModalOpen(true)}
            onMouseEnter={() => setHoveredSmiley(s.value)}
            onMouseLeave={() => setHoveredSmiley(null)}
            className={`text-lg transition-all duration-150 hover:scale-125 cursor-pointer ${hasRating && issue.rating === s.value
              ? s.activeColor
              : hoveredSmiley === s.value
                ? s.activeColor
                : hasRating
                  ? 'grayscale opacity-30 hover:grayscale-0 hover:opacity-100'
                  : 'grayscale opacity-50 hover:grayscale-0 hover:opacity-100'
              }`}
            title={hasRating ? 'Click to edit rating' : `Click to rate as ${s.label}`}
          >
            {s.emoji}
          </button>
        ))}
      </div>

      <FeedbackModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        onSubmit={handleSubmitFeedback}
        isLoading={isUpdating}
        issueDescription={issue.description}
        initialRating={issue.rating}
        initialRemarks={issue.rating_remarks}
      />
    </>
  )
}

function SLAWarning({ ticket }) {
  const [now, setNow] = useState(new Date())

  useEffect(() => {
    const t = setInterval(() => setNow(new Date()), 60000)
    return () => clearInterval(t)
  }, [])

  const deadline = ticket.final_sla_end_date
  if (!deadline) return null

  const isTerminal = ticket.status === 'Resolved' || ticket.status === 'Closed'

  if (isTerminal) {
    const status = ticket.overall_sla_status
    if (!status || status === 'Pending') return null
    const adhered = status === 'Adhered'
    return (
      <div className={`mt-4 flex items-center gap-3 px-4 py-3 rounded-lg border ${adhered ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200'}`}>
        <span className="text-base">{adhered ? '✅' : '⚠️'}</span>
        <div>
          <p className={`text-sm font-semibold ${adhered ? 'text-green-700' : 'text-red-700'}`}>SLA {adhered ? 'Adhered' : 'Violated'}</p>
          <p className="text-xs text-gray-500">Deadline was {format(new Date(deadline), 'MMM d, yyyy')}</p>
        </div>
      </div>
    )
  }

  const diffDays = Math.ceil((new Date(deadline) - now) / (1000 * 60 * 60 * 24))
  const isOverdue = diffDays < 0
  const isWarning = !isOverdue && diffDays <= 2

  const styles = isOverdue
    ? { wrap: 'bg-red-50 border-red-200', label: 'text-red-700', sub: 'Was due' }
    : isWarning
      ? { wrap: 'bg-orange-50 border-orange-200', label: 'text-orange-700', sub: 'Due' }
      : { wrap: 'bg-blue-50 border-blue-200', label: 'text-blue-700', sub: 'Due' }

  return (
    <div className={`mt-4 flex items-center justify-between px-4 py-3 rounded-lg border ${styles.wrap}`}>
      <div className="flex items-center gap-3">
        {isOverdue && <span className="text-base">⚠️</span>}
        <div>
          <p className={`text-sm font-semibold ${styles.label}`}>
            {isOverdue ? 'SLA Violated' : isWarning ? 'SLA Due Soon' : 'SLA On Track'}
          </p>
          <p className="text-xs text-gray-500">{styles.sub} {format(new Date(deadline), 'MMM d, yyyy')}</p>
        </div>
      </div>
      <SLATimer targetDate={deadline} currentDate={now} />
    </div>
  )
}

function OverviewTab({ ticket }) {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
      {/* Left Column: Details */}
      <div className="lg:col-span-2 space-y-6">
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h2 className="text-lg font-semibold mb-4">Initial Report</h2>
          <div className="prose prose-sm text-gray-600 bg-gray-50 p-4 rounded-md">
            {ticket.initial_remarks || ticket.complaint}
          </div>
        </div>

        {ticket.photos?.length > 0 && (
          <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
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
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <h3 className="text-sm font-medium text-gray-600 uppercase tracking-wider mb-4">Details</h3>
          <dl className="space-y-4">
            <div>
              <dt className="text-xs text-gray-600">Vehicle</dt>
              <dd className="text-sm font-medium text-gray-900">{ticket.vehicle_number}</dd>
            </div>
            <div>
              <dt className="text-xs text-gray-600">Site</dt>
              <dd className="text-sm font-medium text-gray-900">{ticket.site}</dd>
            </div>
            <div>
              <dt className="text-xs text-gray-600">Supervisor</dt>
              <dd className="text-sm font-medium text-gray-900">
                {ticket.supervisor_name}
                <span className="block text-xs text-gray-500">{ticket.supervisor_contact}</span>
              </dd>
            </div>
          </dl>
        </div>
      </div>
    </div>
  )
}

function IssuesTab({ ticket, issues, canEdit, userProfile }) {
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

  // Edit Mode State
  const [editingIssueId, setEditingIssueId] = useState(null)
  const [editedIssue, setEditedIssue] = useState(null)

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
        issueData: {
          ticket_id: ticket.id,
          ...newIssue
        },
        userId: userProfile?.id
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
      await Promise.all(Array.from(selectedIssueIds).map(id => {
        const issue = issues?.find(i => i.id === id)
        return deleteIssue.mutateAsync({
          issueId: id,
          userId: userProfile?.id,
          oldData: issue
        })
      }))
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
      // Get selected issues for audit logging
      const selectedIssues = issues?.filter(i => selectedIssueIds.has(i.id)) || []

      const newJC = await createJobCard.mutateAsync({
        jobCardData,
        issueIds: Array.from(selectedIssueIds),
        userId: userProfile?.id,
        issues: selectedIssues
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
      // Get selected issues for audit logging
      const selectedIssues = issues?.filter(i => selectedIssueIds.has(i.id)) || []

      await linkIssues.mutateAsync({
        jobCardId,
        issueIds: Array.from(selectedIssueIds),
        userId: userProfile?.id,
        issues: selectedIssues
      })
      setSelectedIssueIds(new Set())
      alert('Issues added to Job Card successfully!')
    } catch (e) {
      console.error("Link Error", e)
      alert(e.message || 'Failed to link issues')
    }
  }

  const openJobCards = jobCards?.filter(jc => jc.status === 'Open') || []

  const unassignedIssues = issues?.filter(i => !i.job_card_id) || []
  const assignedIssues = issues?.filter(i => i.job_card_id) || []
  const allIssues = [...unassignedIssues, ...assignedIssues]

  // Start editing an issue
  const startEditing = (issue) => {
    setEditingIssueId(issue.id)
    setEditedIssue({
      description: issue.description,
      category: issue.category,
      severity: issue.severity
    })
  }

  // Cancel editing
  const cancelEditing = () => {
    setEditingIssueId(null)
    setEditedIssue(null)
  }

  // Check if there are unsaved changes
  const hasChanges = (issue) => {
    if (!editedIssue || editingIssueId !== issue.id) return false
    return (
      editedIssue.description !== issue.description ||
      editedIssue.category !== issue.category ||
      editedIssue.severity !== issue.severity
    )
  }

  // Save edited issue
  const handleSaveEdit = async (issue) => {
    if (!hasChanges(issue)) {
      cancelEditing()
      return
    }

    try {
      await updateIssue.mutateAsync({
        id: issue.id,
        updates: {
          description: editedIssue.description,
          category: editedIssue.category,
          severity: editedIssue.severity
        },
        userId: userProfile?.id,
        oldData: issue
      })
      cancelEditing()
    } catch (e) {
      alert(e.message)
    }
  }

  // Handle unassign from job card (only in edit mode)
  const handleUnassignInEditMode = async (issue) => {
    if (!window.confirm('Are you sure you want to remove this issue from the Job Card?')) return

    try {
      await updateIssue.mutateAsync({
        id: issue.id,
        updates: { job_card_id: null, status: 'Open' },
        userId: userProfile?.id,
        oldData: issue
      })
      cancelEditing()
    } catch (e) {
      alert(e.message)
    }
  }

  return (
    <div className="space-y-6">
      {/* Header Actions - Only visible if user can edit */}
      {canEdit && (
        <div className="flex justify-between items-center bg-gray-50 p-4 rounded-lg border border-gray-300">
          <div className="flex items-center gap-4">
            {selectedIssueIds.size > 0 ? (
              <span className="text-sm font-medium text-blue-700 bg-blue-50 px-3 py-1 rounded-full border border-blue-200">
                {selectedIssueIds.size} selected
              </span>
            ) : (
              <span className="text-sm text-gray-600">Select issues to perform an action</span>
            )}
          </div>

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
                <MenuItems anchor="bottom end" className="absolute right-0 z-10 mt-2 w-52 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none">
                  <div className="py-1">
                    {openJobCards.map((jc) => (
                      <MenuItem key={jc.id}>
                        {({ active }) => (
                          <button
                            onClick={() => handleAddToJobCard(jc.id)}
                            className={`${active ? 'bg-gray-100 text-gray-900' : 'text-gray-700'
                              } block w-full px-4 py-2 text-left text-sm`}
                          >
                            <div className="flex items-center justify-between gap-4">
                              <span className="font-medium">#{jc.job_card_number}</span>
                              <span className="text-gray-400 text-xs shrink-0">{jc.mechanic?.name ?? 'Unassigned'}</span>
                            </div>
                          </button>
                        )}
                      </MenuItem>
                    ))}
                    {openJobCards.length > 0 && <div className="border-t border-gray-200 my-1"></div>}
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
        </div>
      )}

      {/* Issues Table */}
      <div className="bg-white rounded-lg shadow-sm overflow-hidden border border-gray-300">
        <div className="overflow-x-auto">
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
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">ID</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider w-1/4">Description</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Category</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Severity</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Feedback</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-600 uppercase tracking-wider">Job Card</th>
                {canEdit && <th className="px-4 py-3 text-right text-xs font-medium text-gray-600 uppercase tracking-wider w-24">Actions</th>}
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
                    <td className="px-4 py-4 text-sm text-gray-700">
                      {editingIssueId === issue.id ? (
                        <CustomInput
                          value={editedIssue?.description || ''}
                          onChange={e => setEditedIssue({ ...editedIssue, description: e.target.value })}
                          className="w-full"
                        />
                      ) : (
                        issue.description
                      )}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                      {editingIssueId === issue.id ? (
                        <CustomSelect
                          value={editedIssue?.category}
                          onChange={val => setEditedIssue({ ...editedIssue, category: val })}
                          options={['Mechanical', 'Electrical', 'Body', 'Tyre', 'GPS', 'AdBlue', 'Other']}
                          placeholder="Select"
                        />
                      ) : (
                        issue.category
                      )}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                      {editingIssueId === issue.id ? (
                        <CustomSelect
                          value={editedIssue?.severity}
                          onChange={val => setEditedIssue({ ...editedIssue, severity: val })}
                          options={['Minor', 'Major']}
                          placeholder="Select"
                        />
                      ) : (
                        <span className={`px-2 py-1 rounded-full text-xs font-medium ${issue.severity === 'Major' ? 'bg-orange-100 text-orange-800' : 'bg-gray-100 text-gray-600'}`}>
                          {issue.severity}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${issue.status === 'Done' ? 'bg-green-100 text-green-800' : 'bg-blue-100 text-blue-800'}`}>
                        {issue.status}
                      </span>
                    </td>
                    {/* Feedback Column */}
                    <td className="px-4 py-4 whitespace-nowrap text-sm">
                      <FeedbackSmileys
                        issue={issue}
                        ticket={ticket}
                        userProfile={userProfile}
                        isUpdating={updateIssue.isPending}
                        onUpdateFeedback={(feedbackData) => {
                          console.log('Rating update:', {
                            issueId: issue.id,
                            feedbackData,
                            updates: {
                              rating: feedbackData.rating,
                              rating_remarks: feedbackData.rating_remarks,
                              rated_at: new Date().toISOString()
                            }
                          })
                          updateIssue.mutate({
                            id: issue.id,
                            updates: {
                              rating: feedbackData.rating,
                              rating_remarks: feedbackData.rating_remarks,
                              rated_at: new Date().toISOString()
                            },
                            userId: userProfile?.id,
                            oldData: issue
                          })
                        }}
                      />
                    </td>
                    <td className="px-4 py-4 whitespace-nowrap text-sm text-gray-600">
                      {issue.job_card?.job_card_number ? (
                        <div className="flex items-center gap-2">
                          <Link to={`/job-cards/${issue.job_card.job_card_number}`} className="text-blue-600 hover:underline font-medium">
                            #{issue.job_card.job_card_number}
                          </Link>
                          {canEdit && editingIssueId === issue.id && (
                            <button
                              onClick={() => handleUnassignInEditMode(issue)}
                              className="text-gray-500 hover:text-red-500 transition-colors p-1"
                              title="Remove from Job Card"
                            >
                              <XMarkIcon className="w-4 h-4" />
                            </button>
                          )}
                        </div>
                      ) : (
                        <span className="text-gray-500 italic text-xs">Unassigned</span>
                      )}
                    </td>
                    {/* Actions Column */}
                    {canEdit && (
                      <td className="px-4 py-4 whitespace-nowrap text-right">
                        {editingIssueId === issue.id ? (
                          <div className="flex items-center justify-end gap-1">
                            {hasChanges(issue) && (
                              <button
                                onClick={() => handleSaveEdit(issue)}
                                disabled={updateIssue.isPending}
                                className="text-green-600 hover:text-green-700 transition-colors p-1.5 rounded hover:bg-green-50"
                                title="Save changes"
                              >
                                <CheckIcon className="w-4 h-4" />
                              </button>
                            )}
                            <button
                              onClick={cancelEditing}
                              className="text-gray-500 hover:text-gray-600 transition-colors p-1.5 rounded hover:bg-gray-100"
                              title="Cancel editing"
                            >
                              <XMarkIcon className="w-4 h-4" />
                            </button>
                          </div>
                        ) : (
                          <button
                            onClick={() => startEditing(issue)}
                            className="text-gray-500 hover:text-blue-600 transition-colors p-1.5 rounded hover:bg-blue-50"
                            title="Edit issue"
                          >
                            <PencilIcon className="w-4 h-4" />
                          </button>
                        )}
                      </td>
                    )}
                  </tr>
                )
              })}

              {/* INLINE CREATE ROW */}
              {canEdit && (
                <tr className="bg-blue-50/30">
                  <td className="px-4 py-4"></td>
                  <td className="px-4 py-4 font-mono text-xs text-gray-500">NEW</td>
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
                  <td className="px-4 py-2" colSpan={3}>
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
                  <td colSpan={8} className="px-6 py-8 text-center text-gray-600 italic">No issues recorded.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
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
        <div className="bg-white p-12 text-center text-gray-600 rounded-lg border border-dashed border-gray-300">
          No Job Cards created. Go to "Issues" tab to select issues and assign them.
        </div>
      ) : (
        <div className="grid gap-6">
          {jobCards.map(jc => (
            <div key={jc.id} className="bg-white border rounded-lg p-6 shadow-sm">
              <div className="flex justify-between items-start mb-4">
                <div>
                  <h3 className="text-lg font-medium text-gray-900">
                    <Link to={`/job-cards/${jc.job_card_number}`} className="hover:underline text-blue-600">
                      Job Card #{jc.job_card_number}
                    </Link>
                  </h3>
                  <p className="text-sm text-gray-600">{jc.type} • {format(parseUTC(jc.created_at), 'MMM d, yyyy')}</p>
                </div>
                <StatusBadge status={jc.status} />
              </div>

              <div className="bg-gray-50 rounded p-4 mb-4">
                <h4 className="text-xs font-semibold text-gray-600 uppercase mb-2">Assigned To</h4>
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
                    <p className="text-xs text-gray-600">External Vendor</p>
                  </div>
                )}
              </div>

              <div>
                <h4 className="text-xs font-semibold text-gray-600 uppercase mb-2">Included Issues</h4>
                <ul className="list-disc list-inside text-sm text-gray-700 space-y-1">
                  {jc.issues.map(i => (
                    <li key={i.id}>{i.description} <span className="text-gray-500">({i.category})</span></li>
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
