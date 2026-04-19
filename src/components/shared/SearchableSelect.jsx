import { useState, Fragment } from 'react'
import {
  Combobox,
  ComboboxInput,
  ComboboxOptions,
  ComboboxOption,
  Transition,
} from '@headlessui/react'
import { CheckIcon } from '@heroicons/react/20/solid'

function classNames(...classes) {
  return classes.filter(Boolean).join(' ')
}

/**
 * A searchable select — shows no options until the user starts typing,
 * then filters as they type. Matches the visual style of CustomSelect.
 *
 * options: array of { value, label } objects
 */
export default function SearchableSelect({
  label,
  value,
  onChange,
  options = [],
  error,
  placeholder = 'Type to search...',
  disabled = false,
}) {
  const [query, setQuery] = useState('')

  const filtered =
    query === ''
      ? []
      : options.filter((opt) =>
          opt.label.toLowerCase().includes(query.toLowerCase())
        )

  const displayValue = (val) => {
    if (!val) return ''
    const found = options.find((o) => o.value === val)
    return found ? found.label : val
  }

  const handleChange = (val) => {
    onChange(val)
    setQuery('')
  }

  return (
    <Combobox value={value} onChange={handleChange} disabled={disabled}>
      {label && (
        <Combobox.Label className="block text-sm font-medium text-gray-700 mb-2">
          {label}
        </Combobox.Label>
      )}
      <div className="relative mt-1">
        <ComboboxInput
          className={classNames(
            'relative w-full cursor-default rounded-lg text-left border shadow-sm focus:outline-none focus:ring-2 sm:text-sm py-2.5 pl-4 pr-10',
            disabled
              ? 'bg-gray-50 text-gray-500 cursor-not-allowed'
              : 'bg-white',
            error
              ? 'border-red-300 focus:ring-red-500'
              : 'border-gray-300 focus:ring-blue-500'
          )}
          displayValue={displayValue}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={placeholder}
          autoComplete="off"
        />

        {error && (
          <p className="mt-1 text-sm text-red-600">{error.message}</p>
        )}

        <Transition
          as={Fragment}
          show={query.length > 0}
          leave="transition ease-in duration-100"
          leaveFrom="opacity-100"
          leaveTo="opacity-0"
        >
          <ComboboxOptions className="absolute z-50 mt-1 max-h-60 w-full overflow-auto rounded-md bg-white py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm">
            {filtered.length === 0 ? (
              <div className="relative cursor-default select-none py-2 px-4 text-gray-500">
                No vehicles found for "{query}"
              </div>
            ) : (
              filtered.map((opt) => (
                <ComboboxOption
                  key={opt.value}
                  value={opt.value}
                  className={({ active }) =>
                    classNames(
                      active ? 'bg-blue-600 text-white' : 'text-gray-900',
                      'relative cursor-default select-none py-2 pl-3 pr-9'
                    )
                  }
                >
                  {({ selected, active }) => (
                    <>
                      <span
                        className={classNames(
                          selected ? 'font-semibold' : 'font-normal',
                          'block truncate'
                        )}
                      >
                        {opt.label}
                      </span>
                      {selected && (
                        <span
                          className={classNames(
                            active ? 'text-white' : 'text-blue-600',
                            'absolute inset-y-0 right-0 flex items-center pr-4'
                          )}
                        >
                          <CheckIcon className="h-5 w-5" aria-hidden="true" />
                        </span>
                      )}
                    </>
                  )}
                </ComboboxOption>
              ))
            )}
          </ComboboxOptions>
        </Transition>
      </div>
    </Combobox>
  )
}
