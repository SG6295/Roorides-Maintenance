export function TicketCardSkeleton() {
  return (
    <div className="bg-white rounded-lg shadow p-4 animate-pulse">
      <div className="flex justify-between items-start mb-3">
        <div className="h-5 bg-gray-200 rounded w-24"></div>
        <div className="h-5 bg-gray-200 rounded w-20"></div>
      </div>
      <div className="space-y-2 mb-3">
        <div className="h-4 bg-gray-200 rounded w-3/4"></div>
        <div className="h-4 bg-gray-200 rounded w-1/2"></div>
      </div>
      <div className="flex gap-2">
        <div className="h-6 bg-gray-200 rounded w-16"></div>
        <div className="h-6 bg-gray-200 rounded w-20"></div>
      </div>
    </div>
  )
}

export function TicketListSkeleton({ count = 3 }) {
  return (
    <div className="space-y-4">
      {Array.from({ length: count }).map((_, i) => (
        <TicketCardSkeleton key={i} />
      ))}
    </div>
  )
}

export function TicketDetailSkeleton() {
  return (
    <div className="bg-white rounded-lg shadow animate-pulse">
      <div className="p-6 border-b">
        <div className="flex gap-2">
          <div className="h-7 bg-gray-200 rounded w-24"></div>
          <div className="h-7 bg-gray-200 rounded w-32"></div>
        </div>
      </div>

      <div className="p-6 border-b">
        <div className="h-6 bg-gray-200 rounded w-40 mb-4"></div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <div className="h-4 bg-gray-200 rounded w-32 mb-2"></div>
            <div className="h-5 bg-gray-200 rounded w-40"></div>
          </div>
          <div>
            <div className="h-4 bg-gray-200 rounded w-24 mb-2"></div>
            <div className="h-5 bg-gray-200 rounded w-36"></div>
          </div>
        </div>
      </div>

      <div className="p-6 border-b">
        <div className="h-6 bg-gray-200 rounded w-32 mb-2"></div>
        <div className="space-y-2">
          <div className="h-4 bg-gray-200 rounded w-full"></div>
          <div className="h-4 bg-gray-200 rounded w-5/6"></div>
          <div className="h-4 bg-gray-200 rounded w-4/6"></div>
        </div>
      </div>

      <div className="p-6">
        <div className="h-6 bg-gray-200 rounded w-48 mb-4"></div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <div className="h-4 bg-gray-200 rounded w-20 mb-2"></div>
            <div className="h-5 bg-gray-200 rounded w-32"></div>
          </div>
          <div>
            <div className="h-4 bg-gray-200 rounded w-28 mb-2"></div>
            <div className="h-5 bg-gray-200 rounded w-24"></div>
          </div>
        </div>
      </div>
    </div>
  )
}

export function FormSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      {Array.from({ length: 4 }).map((_, i) => (
        <div key={i}>
          <div className="h-5 bg-gray-200 rounded w-32 mb-2"></div>
          <div className="h-12 bg-gray-200 rounded w-full"></div>
        </div>
      ))}
      <div className="h-12 bg-blue-200 rounded w-full"></div>
    </div>
  )
}

export function SpinnerIcon({ className = "w-5 h-5" }) {
  return (
    <svg
      className={`animate-spin ${className}`}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
    >
      <circle
        className="opacity-25"
        cx="12"
        cy="12"
        r="10"
        stroke="currentColor"
        strokeWidth="4"
      ></circle>
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
      ></path>
    </svg>
  )
}
