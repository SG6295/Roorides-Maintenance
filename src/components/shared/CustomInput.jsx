import { forwardRef } from 'react'

function classNames(...classes) {
    return classes.filter(Boolean).join(' ')
}

const CustomInput = forwardRef(function CustomInput({
    label,
    error,
    className,
    ...props
}, ref) {
    return (
        <div className={label ? "" : "w-full"}>
            {label && (
                <label className="block text-sm font-medium text-gray-700 mb-2">
                    {label}
                </label>
            )}
            <div className="relative mt-1">
                <input
                    ref={ref}
                    className={classNames(
                        "block w-full rounded-lg border bg-white py-3 px-4 shadow-sm focus:outline-none focus:ring-2 sm:text-sm",
                        error
                            ? "border-red-300 focus:border-red-500 focus:ring-red-500 text-red-900 placeholder-red-300"
                            : "border-gray-300 focus:border-blue-500 focus:ring-blue-500 text-gray-900",
                        props.disabled && "bg-gray-100 cursor-not-allowed opacity-75",
                        className
                    )}
                    {...props}
                />
                {error && (
                    <p className="mt-1 text-sm text-red-600">{error.message || error}</p>
                )}
            </div>
        </div>
    )
})

export default CustomInput
