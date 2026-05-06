import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { XMarkIcon } from '@heroicons/react/24/outline'
import { useAuth } from '../../hooks/useAuth'
import { useQuickAddSupplier } from '../../hooks/useSuppliers'
import { supabase } from '../../lib/supabase'

const EMPTY_FORM = {
  entity_name: '',
  owner_name: '',
  owner_contact: '',
  registered_office_address: '',
  nature_of_work: '',
}

function isFormDirty(form) {
  return Object.values(form).some((v) => v.trim() !== '')
}

export default function QuickAddSupplierModal({ isOpen, onClose, onSuccess }) {
  const { userProfile } = useAuth()
  const quickAdd = useQuickAddSupplier()

  const [form, setForm] = useState(EMPTY_FORM)
  const [submitError, setSubmitError] = useState(null)

  const { data: nowSuggestions = [] } = useQuery({
    queryKey: ['suppliers', 'nature_of_work_suggestions'],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('suppliers')
        .select('nature_of_work')
        .not('nature_of_work', 'is', null)
      if (error) return []
      const unique = [...new Set(data.map((r) => r.nature_of_work).filter(Boolean))].sort()
      return unique
    },
    staleTime: 5 * 60 * 1000,
  })

  if (!isOpen) return null

  const set = (field, value) => setForm((f) => ({ ...f, [field]: value }))

  const allFilled = Object.values(form).every((v) => v.trim() !== '')

  const handleClose = () => {
    if (isFormDirty(form) && !window.confirm('Discard changes?')) return
    setForm(EMPTY_FORM)
    setSubmitError(null)
    onClose()
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    setSubmitError(null)
    try {
      const newSupplier = await quickAdd.mutateAsync({
        entity_name: form.entity_name.trim(),
        owner_name: form.owner_name.trim(),
        owner_contact: form.owner_contact.trim(),
        registered_office_address: form.registered_office_address.trim(),
        nature_of_work: form.nature_of_work.trim(),
        created_by: userProfile?.id ?? null,
        submitted_by: userProfile?.name || userProfile?.email || 'Unknown',
      })
      setForm(EMPTY_FORM)
      setSubmitError(null)
      onSuccess(newSupplier)
      onClose()
    } catch (err) {
      setSubmitError(err.message || 'Failed to add supplier. Please try again.')
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-xl shadow-2xl w-full max-w-lg flex flex-col max-h-[90vh]">

        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 shrink-0">
          <div>
            <h2 className="text-base font-semibold text-gray-900">Quick Add Supplier</h2>
            <p className="text-xs text-gray-500 mt-0.5">
              Added as approved — finish full registration later via the Suppliers page.
            </p>
          </div>
          <button
            type="button"
            onClick={handleClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <XMarkIcon className="w-5 h-5" />
          </button>
        </div>

        {/* Body */}
        <form onSubmit={handleSubmit} className="flex flex-col flex-1 overflow-hidden">
          <div className="overflow-y-auto flex-1 px-6 py-5 space-y-4">

            {submitError && (
              <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
                {submitError}
              </div>
            )}

            <Field label="Entity Name" required>
              <input
                type="text"
                value={form.entity_name}
                onChange={(e) => set('entity_name', e.target.value)}
                placeholder="e.g. Ravi Auto Works"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </Field>

            <Field label="Owner / Proprietor Name" required>
              <input
                type="text"
                value={form.owner_name}
                onChange={(e) => set('owner_name', e.target.value)}
                placeholder="e.g. Ravi Kumar"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </Field>

            <Field label="Owner Contact Number" required>
              <input
                type="tel"
                value={form.owner_contact}
                onChange={(e) => set('owner_contact', e.target.value)}
                placeholder="e.g. 9876543210"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </Field>

            <Field label="Registered Office Address" required>
              <textarea
                rows={3}
                value={form.registered_office_address}
                onChange={(e) => set('registered_office_address', e.target.value)}
                placeholder="e.g. 12, Industrial Estate, Chennai - 600032"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
              />
            </Field>

            <Field label="Nature of Work" required>
              <input
                type="text"
                list="now-suggestions"
                value={form.nature_of_work}
                onChange={(e) => set('nature_of_work', e.target.value)}
                placeholder="e.g. AC Repair, Tyre Replacement"
                className="w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
              {nowSuggestions.length > 0 && (
                <datalist id="now-suggestions">
                  {nowSuggestions.map((s) => (
                    <option key={s} value={s} />
                  ))}
                </datalist>
              )}
            </Field>

          </div>

          {/* Footer */}
          <div className="flex items-center justify-end gap-3 px-6 py-4 border-t border-gray-200 shrink-0">
            <button
              type="button"
              onClick={handleClose}
              className="px-4 py-2 text-sm font-medium text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!allFilled || quickAdd.isPending}
              className="px-5 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-2"
            >
              {quickAdd.isPending && (
                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              )}
              {quickAdd.isPending ? 'Adding...' : 'Add Supplier'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

function Field({ label, required, children }) {
  return (
    <div className="space-y-1.5">
      <label className="block text-sm font-medium text-gray-700">
        {label}
        {required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {children}
    </div>
  )
}