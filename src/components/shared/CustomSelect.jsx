import { Fragment } from 'react'
import { Listbox, ListboxButton, ListboxOption, ListboxOptions, Transition } from '@headlessui/react'
import { CheckIcon, ChevronUpDownIcon } from '@heroicons/react/20/solid'

function classNames(...classes) {
    return classes.filter(Boolean).join(' ')
}

export default function CustomSelect({
    label,
    value,
    onChange,
    options = [],
    disabled = false,
    error,
    placeholder = 'Select option'
}) {
    const selectedOption = options.find(opt =>
        (typeof opt === 'object' ? opt.value || opt.name || opt.id : opt) === value
    ) || null

    const getDisplayLabel = (opt) => {
        if (!opt) return placeholder
        if (typeof opt === 'string') return opt
        return opt.label || opt.name || opt.number || opt.id
    }

    const getOptionValue = (opt) => {
        if (typeof opt === 'string') return opt
        if (opt.value !== undefined) return opt.value
        if (opt.name !== undefined) return opt.name
        if (opt.number !== undefined) return opt.number
        return opt.id
    }

    return (
        <Listbox value={value} onChange={onChange} disabled={disabled}>
            {({ open }) => (
                <>
                    {label && (
                        <Listbox.Label className="block text-sm font-medium text-gray-700 mb-2">
                            {label}
                        </Listbox.Label>
                    )}
                    <div className="relative mt-1">
                        <ListboxButton className={classNames(
                            "relative w-full cursor-default rounded-lg bg-white py-3 pl-4 pr-10 text-left border shadow-sm focus:outline-none focus:ring-2 focus:ring-blue-500 sm:text-sm",
                            error ? "border-red-300 focus:ring-red-500" : "border-gray-300 focus:ring-blue-500",
                            disabled ? "bg-gray-100 cursor-not-allowed opacity-75" : "bg-white"
                        )}>
                            <span className={classNames("block truncate", !selectedOption && "text-gray-500")}>
                                {selectedOption ? getDisplayLabel(selectedOption) : placeholder}
                            </span>
                            <span className="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
                                <ChevronUpDownIcon className="h-5 w-5 text-gray-400" aria-hidden="true" />
                            </span>
                        </ListboxButton>

                        <Transition
                            as={Fragment}
                            leave="transition ease-in duration-100"
                            leaveFrom="opacity-100"
                            leaveTo="opacity-0"
                        >
                            <ListboxOptions
                                anchor="bottom"
                                className="z-50 mt-1 max-h-60 w-[var(--button-width)] overflow-auto rounded-md bg-white py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm"
                            >
                                {options.map((option, idx) => {
                                    const optValue = getOptionValue(option)
                                    const optLabel = getDisplayLabel(option)

                                    return (
                                        <ListboxOption
                                            key={idx}
                                            className={({ active }) =>
                                                classNames(
                                                    active ? 'bg-blue-600 text-white' : 'text-gray-900',
                                                    'relative cursor-default select-none py-2 pl-3 pr-9'
                                                )
                                            }
                                            value={optValue}
                                        >
                                            {({ selected, active }) => (
                                                <>
                                                    <span className={classNames(selected ? 'font-semibold' : 'font-normal', 'block truncate')}>
                                                        {optLabel}
                                                    </span>

                                                    {selected ? (
                                                        <span
                                                            className={classNames(
                                                                active ? 'text-white' : 'text-blue-600',
                                                                'absolute inset-y-0 right-0 flex items-center pr-4'
                                                            )}
                                                        >
                                                            <CheckIcon className="h-5 w-5" aria-hidden="true" />
                                                        </span>
                                                    ) : null}
                                                </>
                                            )}
                                        </ListboxOption>
                                    )
                                })}
                            </ListboxOptions>
                        </Transition>

                        {error && (
                            <p className="mt-1 text-sm text-red-600">{error.message}</p>
                        )}
                    </div>
                </>
            )}
        </Listbox>
    )
}
