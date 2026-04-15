import { useParams, useNavigate } from 'react-router-dom'
import { useSupplierById, useUpdateSupplierStatus } from '../hooks/useSuppliers'
import Navigation from '../components/shared/Navigation'
import { useAuth } from '../hooks/useAuth'

const STATUS_COLORS = {
  pending: 'bg-yellow-100 text-yellow-800 border-yellow-200',
  approved: 'bg-green-100 text-green-800 border-green-200',
  rejected: 'bg-red-100 text-red-800 border-red-200',
}

function Section({ title }) {
  return (
    <div className="bg-[#2d6a6a] text-white rounded-xl px-4 py-2.5 mt-2">
      <h3 className="font-semibold text-sm">{title}</h3>
    </div>
  )
}

function Row({ label, value, mono = false, link = false }) {
  if (value === null || value === undefined || value === '') return null
  return (
    <div className="flex flex-col sm:flex-row sm:items-start gap-1 py-2.5 border-b border-gray-100 last:border-0">
      <span className="text-xs font-medium text-gray-500 sm:w-56 flex-shrink-0">{label}</span>
      {link ? (
        <a href={value} target="_blank" rel="noopener noreferrer" className="text-sm text-blue-600 hover:underline">
          View document
        </a>
      ) : (
        <span className={`text-sm text-gray-900 break-words ${mono ? 'font-mono' : ''}`}>
          {value === true ? 'Yes' : value === false ? 'No' : String(value)}
        </span>
      )}
    </div>
  )
}

export default function SupplierDetail() {
  const { id } = useParams()
  const navigate = useNavigate()
  const { userProfile } = useAuth()
  const { data: supplier, isLoading, error } = useSupplierById(id)
  const { mutateAsync: updateStatus, isPending: updating } = useUpdateSupplierStatus()

  const isExec = userProfile?.role === 'maintenance_exec'

  const handleStatus = async (status) => {
    try {
      await updateStatus({ id, status })
      navigate('/suppliers')
    } catch (err) {
      alert('Failed to update status: ' + err.message)
    }
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navigation breadcrumbs={[{ label: 'Suppliers', href: '/suppliers' }, { label: '...' }]} />
        <div className="max-w-3xl mx-auto px-4 py-10 text-center text-sm text-gray-500">Loading...</div>
      </div>
    )
  }

  if (error || !supplier) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navigation breadcrumbs={[{ label: 'Suppliers', href: '/suppliers' }, { label: 'Not found' }]} />
        <div className="max-w-3xl mx-auto px-4 py-10 text-center">
          <p className="text-gray-500 text-sm">Supplier not found.</p>
          <button onClick={() => navigate('/suppliers')} className="mt-3 text-blue-600 text-sm hover:underline">
            ← Back to Suppliers
          </button>
        </div>
      </div>
    )
  }

  const entityTypeDisplay =
    supplier.entity_type === 'Other' && supplier.entity_type_other
      ? `Other — ${supplier.entity_type_other}`
      : supplier.entity_type

  return (
    <div className="min-h-screen bg-gray-50">
      <Navigation
        breadcrumbs={[
          { label: 'Suppliers', href: '/suppliers' },
          { label: supplier.entity_name },
        ]}
      />

      <div className="max-w-3xl mx-auto px-4 sm:px-6 py-6 space-y-4">

        {/* Header card */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 flex flex-col sm:flex-row sm:items-start gap-4">
          <div className="flex-1 min-w-0">
            <h1 className="text-lg font-bold text-gray-900">{supplier.entity_name}</h1>
            <p className="text-sm text-gray-500 mt-0.5">{entityTypeDisplay}</p>
            <p className="text-sm text-gray-600 mt-1">{supplier.nature_of_work}</p>
            <p className="text-xs text-gray-400 mt-1">
              Submitted on {new Date(supplier.created_at).toLocaleDateString('en-IN', { day: 'numeric', month: 'long', year: 'numeric' })}
              {' · '}by {supplier.submitted_by}
            </p>
          </div>
          <span className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-semibold capitalize border self-start ${STATUS_COLORS[supplier.status]}`}>
            {supplier.status}
          </span>
        </div>

        {/* Approval actions (maintenance_exec only, pending suppliers) */}
        {isExec && supplier.status === 'pending' && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 flex items-center justify-between gap-3">
            <p className="text-sm text-gray-600 font-medium">Review this supplier registration:</p>
            <div className="flex gap-2">
              <button
                onClick={() => handleStatus('rejected')}
                disabled={updating}
                className="px-4 py-2 text-sm font-medium text-red-700 border border-red-300 rounded-lg hover:bg-red-50 disabled:opacity-50 transition-colors"
              >
                Reject
              </button>
              <button
                onClick={() => handleStatus('approved')}
                disabled={updating}
                className="px-4 py-2 text-sm font-medium text-white bg-green-600 rounded-lg hover:bg-green-700 disabled:opacity-50 transition-colors"
              >
                {updating ? 'Saving...' : 'Approve'}
              </button>
            </div>
          </div>
        )}

        {/* Section 1: Basic Details */}
        <Section title="1. Basic Details" />
        <div className="bg-white rounded-xl border border-gray-200 px-4 pt-1 pb-2">
          <Row label="Email" value={supplier.email} />
          <Row label="Type of Entity" value={entityTypeDisplay} />
          <Row label="Registered Office Address" value={supplier.registered_office_address} />
          <Row label="Nature of Work" value={supplier.nature_of_work} />
          <Row label="Workshop Address" value={supplier.workshop_address} />
          <Row label="Owner Name" value={supplier.owner_name} />
          <Row label="Owner Contact" value={supplier.owner_contact} />
          <Row label="Owner Email" value={supplier.owner_email} />
          <Row label="Accounts Contact Name" value={supplier.accounts_contact_name} />
          <Row label="Accounts Contact Number" value={supplier.accounts_contact_number} />
          <Row label="Accounts Email" value={supplier.accounts_email} />
          <Row label="Sales Contact Name" value={supplier.sales_contact_name} />
          <Row label="Sales Contact Number" value={supplier.sales_contact_number} />
          <Row label="Sales Email" value={supplier.sales_email} />
          <Row label="PO Communication Emails" value={supplier.po_communication_emails} />
        </div>

        {/* Section 2: Statutory & Compliance */}
        <Section title="2. Statutory & Compliance" />
        <div className="bg-white rounded-xl border border-gray-200 px-4 pt-1 pb-2">
          <Row label="PAN No." value={supplier.pan_number} mono />
          <Row label="PAN Copy" value={supplier.pan_copy_url} link />
          <Row label="GSTIN" value={supplier.gstin} mono />
          <Row label="GST Registration Type" value={supplier.gst_registration_type} />
          <Row label="GST Certificate" value={supplier.gst_certificate_url} link />
          <Row label="MSME / Udyam No." value={supplier.msme_udyam_number} />
          <Row label="Udyam Certificate" value={supplier.udyam_certificate_url} link />
          <Row label="PF Registration No." value={supplier.pf_registration_number} />
          <Row label="PF Certificate" value={supplier.pf_certificate_url} link />
          <Row label="ESI Registration No." value={supplier.esi_registration_number} />
          <Row label="ESI Certificate" value={supplier.esi_certificate_url} link />
          <Row label="Labour License No." value={supplier.labour_license_number} />
        </div>

        {/* Section 3: Bank Details */}
        <Section title="3. Bank Details" />
        <div className="bg-white rounded-xl border border-gray-200 px-4 pt-1 pb-2">
          <Row label="Bank Name" value={supplier.bank_name} />
          <Row label="Branch" value={supplier.bank_branch} />
          <Row label="Account Holder Name" value={supplier.account_holder_name} />
          <Row label="Account Number" value={supplier.account_number} mono />
          <Row label="IFSC Code" value={supplier.ifsc_code} mono />
          <Row label="Account Type" value={supplier.account_type} />
          <Row label="Cancelled Cheque / Passbook" value={supplier.cancelled_cheque_url} link />
        </div>

        {/* Section 4: Work Experience */}
        <Section title="4. Work Experience & Capability" />
        <div className="bg-white rounded-xl border border-gray-200 px-4 pt-1 pb-2">
          <Row label="Total Years of Experience" value={supplier.years_of_experience} />
          <Row label="Major Clients" value={supplier.major_clients} />
          <Row label="Skilled Manpower Available" value={supplier.skilled_manpower_available} />
          <Row label="Brand Spares Usage" value={supplier.brand_spares_usage} />
        </div>

        {/* Section 5: Payment Terms */}
        <Section title="5. Commercial & Payment Terms" />
        <div className="bg-white rounded-xl border border-gray-200 px-4 pt-1 pb-2 mb-8">
          <Row label="Payment Terms (Credit Days)" value={supplier.payment_terms_days} />
        </div>
      </div>
    </div>
  )
}
