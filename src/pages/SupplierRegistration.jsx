import { useState } from 'react'
import { useRegisterSupplier, checkPanExists } from '../hooks/useSuppliers'
import DocumentUpload from '../components/suppliers/DocumentUpload'

const STEPS = [
  'Basic Details',
  'Statutory & Compliance',
  'Bank Details',
  'Work Experience',
  'Payment Terms',
]

const ENTITY_TYPES = ['Proprietorship/LLP', 'Partnership', 'Company', 'HUF', 'Other']
const GST_TYPES = ['Regular', 'Composition', 'Unregistered', 'Input Service Distributor (ISD)']
const ACCOUNT_TYPES = ['Savings', 'Current']

const EMPTY_FORM = {
  // Step 1
  email: '',
  entity_name: '',
  entity_type: '',
  entity_type_other: '',
  registered_office_address: '',
  nature_of_work: '',
  workshop_address: '',
  owner_name: '',
  owner_contact: '',
  owner_email: '',
  accounts_contact_name: '',
  accounts_contact_number: '',
  accounts_email: '',
  sales_contact_name: '',
  sales_contact_number: '',
  sales_email: '',
  po_communication_emails: '',
  // Step 2
  pan_number: '',
  pan_copy_url: '',
  gstin: '',
  gst_registration_type: '',
  gst_certificate_url: '',
  msme_udyam_number: '',
  udyam_certificate_url: '',
  pf_registration_number: '',
  pf_certificate_url: '',
  esi_registration_number: '',
  esi_certificate_url: '',
  labour_license_number: '',
  // Step 3
  bank_name: '',
  bank_branch: '',
  account_holder_name: '',
  account_number: '',
  ifsc_code: '',
  account_type: '',
  cancelled_cheque_url: '',
  // Step 4
  years_of_experience: '',
  major_clients: '',
  skilled_manpower_available: null,
  brand_spares_usage: '',
  // Step 5
  payment_terms_days: '',
  submitted_by: '',
}

// Required fields per step
const REQUIRED = {
  1: ['email', 'entity_name', 'entity_type', 'registered_office_address', 'nature_of_work', 'owner_name', 'owner_contact', 'accounts_contact_number'],
  2: ['pan_number', 'pan_copy_url', 'gstin', 'gst_registration_type'],
  3: ['bank_name', 'bank_branch', 'account_holder_name', 'account_number', 'ifsc_code', 'cancelled_cheque_url'],
  4: ['years_of_experience'],
  5: ['payment_terms_days', 'submitted_by'],
}

function Field({ label, required, children }) {
  return (
    <div className="bg-white rounded-xl border border-gray-200 p-4">
      <label className="block text-sm font-medium text-gray-800 mb-2">
        {label}{required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {children}
    </div>
  )
}

function TextInput({ value, onChange, placeholder = 'Your answer', ...props }) {
  return (
    <input
      type="text"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className="w-full border-0 border-b border-gray-300 focus:border-blue-500 focus:outline-none pb-1 text-sm bg-transparent"
      {...props}
    />
  )
}

export default function SupplierRegistration() {
  const [step, setStep] = useState(1)
  const [form, setForm] = useState(EMPTY_FORM)
  const [errors, setErrors] = useState({})
  const [panChecking, setPanChecking] = useState(false)
  const [submitError, setSubmitError] = useState(null)
  const [submitted, setSubmitted] = useState(false)

  const { mutateAsync: registerSupplier, isPending: submitting } = useRegisterSupplier()

  const set = (field, value) => setForm((f) => ({ ...f, [field]: value }))

  const validate = (stepNum) => {
    const required = REQUIRED[stepNum] || []
    const newErrors = {}

    for (const field of required) {
      // entity_type_other only required if entity_type === 'Other'
      if (field === 'entity_type_other') continue
      if (!form[field] && form[field] !== false) {
        newErrors[field] = 'This field is required'
      }
    }

    // If entity_type is Other, the text box is required
    if (stepNum === 1 && form.entity_type === 'Other' && !form.entity_type_other.trim()) {
      newErrors['entity_type_other'] = 'Please specify the entity type'
    }

    setErrors(newErrors)
    return Object.keys(newErrors).length === 0
  }

  const handleNext = async () => {
    if (!validate(step)) return

    // PAN duplicate check when leaving step 2
    if (step === 2 && form.pan_number) {
      setPanChecking(true)
      try {
        const exists = await checkPanExists(form.pan_number)
        if (exists) {
          setErrors((e) => ({ ...e, pan_number: 'A supplier with this PAN is already registered.' }))
          setPanChecking(false)
          return
        }
      } catch {
        // Non-blocking — if the check fails, allow the user to proceed
      }
      setPanChecking(false)
    }

    setStep((s) => s + 1)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const handleBack = () => {
    setStep((s) => s - 1)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  const handleSubmit = async () => {
    if (!validate(5)) return

    setSubmitError(null)
    try {
      const payload = { ...form }
      // Normalise PAN to uppercase
      payload.pan_number = payload.pan_number.toUpperCase().trim()
      // Remove entity_type_other when not applicable
      if (payload.entity_type !== 'Other') payload.entity_type_other = null

      await registerSupplier(payload)
      setSubmitted(true)
      window.scrollTo({ top: 0, behavior: 'smooth' })
    } catch (err) {
      if (err.code === '23505') {
        setSubmitError('A supplier with this PAN number is already registered.')
      } else {
        setSubmitError(err.message || 'Submission failed. Please try again.')
      }
    }
  }

  if (submitted) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-200 p-8 max-w-md w-full text-center">
          <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h2 className="text-xl font-bold text-gray-900 mb-2">Registration Submitted</h2>
          <p className="text-gray-600 text-sm">
            Thank you for registering with NVS Travel Solutions. Your details have been received and are under review. We will get in touch with you shortly.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-[#2d6a6a] text-white px-4 py-5">
        <div className="max-w-2xl mx-auto">
          <p className="text-xs font-medium uppercase tracking-wider opacity-75 mb-1">NVS Travel Solutions</p>
          <h1 className="text-xl font-bold">Vendor / Supplier Registration</h1>
        </div>
      </div>

      {/* Progress */}
      <div className="bg-white border-b border-gray-200 sticky top-0 z-10 shadow-sm">
        <div className="max-w-2xl mx-auto px-4 py-3">
          <div className="flex items-center justify-between mb-1.5">
            <span className="text-xs text-gray-500 font-medium">{STEPS[step - 1]}</span>
            <span className="text-xs text-gray-400">Page {step} of {STEPS.length}</span>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-1.5">
            <div
              className="bg-[#2d6a6a] h-1.5 rounded-full transition-all duration-300"
              style={{ width: `${(step / STEPS.length) * 100}%` }}
            />
          </div>
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">

        {/* ── STEP 1: Basic Details ── */}
        {step === 1 && (
          <>
            <div className="bg-[#2d6a6a] text-white rounded-xl px-4 py-3">
              <h2 className="font-semibold">1. Basic Details</h2>
            </div>

            <Field label="Email" required>
              <TextInput value={form.email} onChange={(v) => set('email', v)} placeholder="abc@abc.com" />
              {errors.email && <p className="mt-1 text-xs text-red-500">{errors.email}</p>}
            </Field>

            <Field label="Name of the Entity" required>
              <TextInput value={form.entity_name} onChange={(v) => set('entity_name', v)} />
              {errors.entity_name && <p className="mt-1 text-xs text-red-500">{errors.entity_name}</p>}
            </Field>

            <Field label="Type of Entity" required>
              <div className="space-y-2 mt-1">
                {ENTITY_TYPES.map((type) => (
                  <label key={type} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name="entity_type"
                      value={type}
                      checked={form.entity_type === type}
                      onChange={() => set('entity_type', type)}
                      className="text-[#2d6a6a]"
                    />
                    <span className="text-sm text-gray-700">{type}</span>
                    {type === 'Other' && form.entity_type === 'Other' && (
                      <input
                        type="text"
                        value={form.entity_type_other}
                        onChange={(e) => set('entity_type_other', e.target.value)}
                        placeholder="Please specify"
                        className="flex-1 border-0 border-b border-gray-300 focus:border-blue-500 focus:outline-none pb-0.5 text-sm bg-transparent"
                      />
                    )}
                  </label>
                ))}
              </div>
              {errors.entity_type && <p className="mt-1 text-xs text-red-500">{errors.entity_type}</p>}
              {errors.entity_type_other && <p className="mt-1 text-xs text-red-500">{errors.entity_type_other}</p>}
            </Field>

            <Field label="Registered Office Address" required>
              <TextInput value={form.registered_office_address} onChange={(v) => set('registered_office_address', v)} />
              {errors.registered_office_address && <p className="mt-1 text-xs text-red-500">{errors.registered_office_address}</p>}
            </Field>

            <Field label="Nature of Work" required>
              <TextInput value={form.nature_of_work} onChange={(v) => set('nature_of_work', v)} />
              {errors.nature_of_work && <p className="mt-1 text-xs text-red-500">{errors.nature_of_work}</p>}
            </Field>

            <Field label="Workshop Address">
              <TextInput value={form.workshop_address} onChange={(v) => set('workshop_address', v)} />
            </Field>

            <Field label="Owner Name" required>
              <TextInput value={form.owner_name} onChange={(v) => set('owner_name', v)} />
              {errors.owner_name && <p className="mt-1 text-xs text-red-500">{errors.owner_name}</p>}
            </Field>

            <Field label="Owner Contact Number" required>
              <TextInput value={form.owner_contact} onChange={(v) => set('owner_contact', v)} placeholder="9123491234" />
              {errors.owner_contact && <p className="mt-1 text-xs text-red-500">{errors.owner_contact}</p>}
            </Field>

            <Field label="Owner Email ID">
              <TextInput value={form.owner_email} onChange={(v) => set('owner_email', v)} />
            </Field>

            <Field label="Accounts - Contact Person Name">
              <TextInput value={form.accounts_contact_name} onChange={(v) => set('accounts_contact_name', v)} />
            </Field>

            <Field label="Accounts - Contact Person Number" required>
              <TextInput value={form.accounts_contact_number} onChange={(v) => set('accounts_contact_number', v)} placeholder="9123491234" />
              {errors.accounts_contact_number && <p className="mt-1 text-xs text-red-500">{errors.accounts_contact_number}</p>}
            </Field>

            <Field label="Accounts Mail ID">
              <TextInput value={form.accounts_email} onChange={(v) => set('accounts_email', v)} />
            </Field>

            <Field label="Sales / Service Contact Person Name">
              <TextInput value={form.sales_contact_name} onChange={(v) => set('sales_contact_name', v)} />
            </Field>

            <Field label="Sales / Service Contact Person Number">
              <TextInput value={form.sales_contact_number} onChange={(v) => set('sales_contact_number', v)} />
            </Field>

            <Field label="Sales / Service Mail ID">
              <TextInput value={form.sales_email} onChange={(v) => set('sales_email', v)} />
            </Field>

            <Field label="PO-Related Communication Mail IDs">
              <TextInput value={form.po_communication_emails} onChange={(v) => set('po_communication_emails', v)} />
            </Field>
          </>
        )}

        {/* ── STEP 2: Statutory & Compliance ── */}
        {step === 2 && (
          <>
            <div className="bg-[#2d6a6a] text-white rounded-xl px-4 py-3">
              <h2 className="font-semibold">2. Statutory & Compliance Details</h2>
            </div>

            <Field label="PAN No." required>
              <TextInput
                value={form.pan_number}
                onChange={(v) => set('pan_number', v.toUpperCase())}
                placeholder="FMRPS4516Z"
              />
              {errors.pan_number && <p className="mt-1 text-xs text-red-500">{errors.pan_number}</p>}
            </Field>

            <Field label="PAN Copy" required>
              <DocumentUpload
                label=""
                required
                value={form.pan_copy_url}
                onChange={(url) => set('pan_copy_url', url)}
              />
              {errors.pan_copy_url && <p className="mt-1 text-xs text-red-500">{errors.pan_copy_url}</p>}
            </Field>

            <Field label="GSTIN" required>
              <TextInput
                value={form.gstin}
                onChange={(v) => set('gstin', v.toUpperCase())}
                placeholder="29AFLPN1790E1Z6"
              />
              {errors.gstin && <p className="mt-1 text-xs text-red-500">{errors.gstin}</p>}
            </Field>

            <Field label="GST Registration Type" required>
              <select
                value={form.gst_registration_type}
                onChange={(e) => set('gst_registration_type', e.target.value)}
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:border-blue-500"
              >
                <option value="">Select type</option>
                {GST_TYPES.map((t) => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>
              {errors.gst_registration_type && <p className="mt-1 text-xs text-red-500">{errors.gst_registration_type}</p>}
            </Field>

            <Field label="GST Certificate">
              <DocumentUpload
                label=""
                value={form.gst_certificate_url}
                onChange={(url) => set('gst_certificate_url', url)}
              />
            </Field>

            <Field label="MSME / Udyam Registration No.">
              <TextInput value={form.msme_udyam_number} onChange={(v) => set('msme_udyam_number', v)} />
            </Field>

            <Field label="Udyam Certificate">
              <DocumentUpload
                label=""
                value={form.udyam_certificate_url}
                onChange={(url) => set('udyam_certificate_url', url)}
              />
            </Field>

            <Field label="PF Registration No.">
              <TextInput value={form.pf_registration_number} onChange={(v) => set('pf_registration_number', v)} />
            </Field>

            <Field label="PF Certificate">
              <DocumentUpload
                label=""
                value={form.pf_certificate_url}
                onChange={(url) => set('pf_certificate_url', url)}
              />
            </Field>

            <Field label="ESI Registration No.">
              <TextInput value={form.esi_registration_number} onChange={(v) => set('esi_registration_number', v)} />
            </Field>

            <Field label="ESI Certificate">
              <DocumentUpload
                label=""
                value={form.esi_certificate_url}
                onChange={(url) => set('esi_certificate_url', url)}
              />
            </Field>

            <Field label="Labour License No.">
              <TextInput value={form.labour_license_number} onChange={(v) => set('labour_license_number', v)} />
            </Field>
          </>
        )}

        {/* ── STEP 3: Bank Details ── */}
        {step === 3 && (
          <>
            <div className="bg-[#2d6a6a] text-white rounded-xl px-4 py-3">
              <h2 className="font-semibold">3. Bank Details</h2>
            </div>

            <Field label="Bank Name" required>
              <TextInput value={form.bank_name} onChange={(v) => set('bank_name', v)} />
              {errors.bank_name && <p className="mt-1 text-xs text-red-500">{errors.bank_name}</p>}
            </Field>

            <Field label="Branch" required>
              <TextInput value={form.bank_branch} onChange={(v) => set('bank_branch', v)} />
              {errors.bank_branch && <p className="mt-1 text-xs text-red-500">{errors.bank_branch}</p>}
            </Field>

            <Field label="Account Holder Name" required>
              <TextInput value={form.account_holder_name} onChange={(v) => set('account_holder_name', v)} />
              {errors.account_holder_name && <p className="mt-1 text-xs text-red-500">{errors.account_holder_name}</p>}
            </Field>

            <Field label="Account Number" required>
              <TextInput value={form.account_number} onChange={(v) => set('account_number', v)} />
              {errors.account_number && <p className="mt-1 text-xs text-red-500">{errors.account_number}</p>}
            </Field>

            <Field label="IFSC Code" required>
              <TextInput
                value={form.ifsc_code}
                onChange={(v) => set('ifsc_code', v.toUpperCase())}
              />
              {errors.ifsc_code && <p className="mt-1 text-xs text-red-500">{errors.ifsc_code}</p>}
            </Field>

            <Field label="Account Type">
              <div className="space-y-2 mt-1">
                {ACCOUNT_TYPES.map((type) => (
                  <label key={type} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name="account_type"
                      value={type}
                      checked={form.account_type === type}
                      onChange={() => set('account_type', type)}
                      className="text-[#2d6a6a]"
                    />
                    <span className="text-sm text-gray-700">{type}</span>
                  </label>
                ))}
              </div>
            </Field>

            <Field label="Cancelled Cheque / Passbook (Front Page)" required>
              <DocumentUpload
                label=""
                required
                value={form.cancelled_cheque_url}
                onChange={(url) => set('cancelled_cheque_url', url)}
              />
              {errors.cancelled_cheque_url && <p className="mt-1 text-xs text-red-500">{errors.cancelled_cheque_url}</p>}
            </Field>
          </>
        )}

        {/* ── STEP 4: Work Experience & Capability ── */}
        {step === 4 && (
          <>
            <div className="bg-[#2d6a6a] text-white rounded-xl px-4 py-3">
              <h2 className="font-semibold">4. Work Experience & Capability</h2>
            </div>

            <Field label="Total Years of Experience" required>
              <TextInput value={form.years_of_experience} onChange={(v) => set('years_of_experience', v)} />
              {errors.years_of_experience && <p className="mt-1 text-xs text-red-500">{errors.years_of_experience}</p>}
            </Field>

            <Field label="Major Clients Handled">
              <TextInput value={form.major_clients} onChange={(v) => set('major_clients', v)} />
            </Field>

            <Field label="Skilled Manpower Available">
              <div className="space-y-2 mt-1">
                {[{ label: 'Yes', value: true }, { label: 'No', value: false }].map(({ label, value }) => (
                  <label key={label} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="radio"
                      name="skilled_manpower"
                      checked={form.skilled_manpower_available === value}
                      onChange={() => set('skilled_manpower_available', value)}
                      className="text-[#2d6a6a]"
                    />
                    <span className="text-sm text-gray-700">{label}</span>
                  </label>
                ))}
              </div>
            </Field>

            <Field label="Type of Brand Spares Usage">
              <TextInput value={form.brand_spares_usage} onChange={(v) => set('brand_spares_usage', v)} />
            </Field>
          </>
        )}

        {/* ── STEP 5: Commercial & Payment Terms ── */}
        {step === 5 && (
          <>
            <div className="bg-[#2d6a6a] text-white rounded-xl px-4 py-3">
              <h2 className="font-semibold">5. Commercial & Payment Terms</h2>
            </div>

            <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 text-sm text-gray-700 leading-relaxed">
              <p className="font-semibold">All invoices for the previous month must be submitted by the 3rd of the current month.</p>
              <p className="font-semibold mt-1">The ledger statement should be shared before the 5th to enable reconciliation and confirmation of the closing balance.</p>
              <p className="font-semibold mt-1">The NDC must be submitted by the 15th of the month.</p>
              <p className="mt-2 flex items-start gap-1.5">
                <span>⚠️</span>
                <span className="font-semibold">Invoices received after the above deadlines will not be accepted for payment.</span>
              </p>
            </div>

            <Field label="Payment Terms (Credit Period in Days)" required>
              <TextInput value={form.payment_terms_days} onChange={(v) => set('payment_terms_days', v)} />
              {errors.payment_terms_days && <p className="mt-1 text-xs text-red-500">{errors.payment_terms_days}</p>}
            </Field>

            <Field label="Submitted by" required>
              <TextInput value={form.submitted_by} onChange={(v) => set('submitted_by', v)} />
              {errors.submitted_by && <p className="mt-1 text-xs text-red-500">{errors.submitted_by}</p>}
            </Field>

            {submitError && (
              <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-sm text-red-700">
                {submitError}
              </div>
            )}
          </>
        )}

        {/* Navigation */}
        <div className="flex items-center justify-between pt-2 pb-8">
          {step > 1 ? (
            <button
              type="button"
              onClick={handleBack}
              className="px-5 py-2.5 text-sm font-medium text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
            >
              Back
            </button>
          ) : (
            <div />
          )}

          {step < STEPS.length ? (
            <button
              type="button"
              onClick={handleNext}
              disabled={panChecking}
              className="px-6 py-2.5 text-sm font-medium text-white bg-[#2d6a6a] rounded-lg hover:bg-[#245858] disabled:opacity-50 transition-colors"
            >
              {panChecking ? 'Checking...' : 'Next'}
            </button>
          ) : (
            <button
              type="button"
              onClick={handleSubmit}
              disabled={submitting}
              className="px-6 py-2.5 text-sm font-medium text-white bg-[#2d6a6a] rounded-lg hover:bg-[#245858] disabled:opacity-50 transition-colors flex items-center gap-2"
            >
              {submitting && <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white" />}
              {submitting ? 'Submitting...' : 'Submit'}
            </button>
          )}
        </div>

        <p className="text-xs text-gray-400 text-center pb-4">
          A copy of your responses will be emailed to the address you provided.
        </p>
      </div>
    </div>
  )
}
