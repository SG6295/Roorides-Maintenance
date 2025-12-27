// SLA Rules from PRD
const SLA_RULES = {
  'Major-Electrical': 7,
  'Major-Mechanical': 15,
  'Major-Body': 30,
  'Major-Tyre': 15,
  'Major-GPS/Camera': 3,
  'Minor-Electrical': 3,
  'Minor-Mechanical': 3,
  'Minor-Body': 3,
  'Minor-Tyre': 3,
  'Minor-GPS/Camera': 3,
  'Minor-Other': 3,
  'Major-Other': 7,
}

const ASSIGNMENT_SLA_DAYS = 1

/**
 * Calculate SLA days based on impact and category
 */
export function calculateSLADays(impact, category) {
  if (!impact || !category) return null

  const key = `${impact}-${category}`
  return SLA_RULES[key] || 3 // default to 3 days
}

/**
 * Calculate SLA end date from creation date
 */
export function calculateSLAEndDate(createdAt, slaDays) {
  if (!createdAt || !slaDays) return null

  const date = new Date(createdAt)
  date.setDate(date.getDate() + slaDays)
  return date
}

/**
 * Check if assignment SLA is violated
 * Must be assigned within 1 day of creation
 */
export function checkAssignmentSLA(createdAt, assignedDate) {
  if (!createdAt) return 'Pending'
  if (!assignedDate) {
    // Check if more than 1 day has passed since creation
    const daysSinceCreation = Math.floor((new Date() - new Date(createdAt)) / (1000 * 60 * 60 * 24))
    return daysSinceCreation > ASSIGNMENT_SLA_DAYS ? 'Violated' : 'Pending'
  }

  const created = new Date(createdAt)
  const assigned = new Date(assignedDate)
  const daysDiff = Math.floor((assigned - created) / (1000 * 60 * 60 * 24))

  return daysDiff <= ASSIGNMENT_SLA_DAYS ? 'Adhered' : 'Violated'
}

/**
 * Check if completion SLA is violated
 */
export function checkCompletionSLA(slaEndDate, completedDate, status) {
  if (!slaEndDate) return 'Pending'
  if (status !== 'Completed') {
    // Check if we're past the SLA end date
    const now = new Date()
    return now > new Date(slaEndDate) ? 'Violated' : 'Pending'
  }

  if (!completedDate) return 'Pending'

  const slaEnd = new Date(slaEndDate)
  const completed = new Date(completedDate)

  return completed <= slaEnd ? 'Adhered' : 'Violated'
}

/**
 * Calculate TAT (Turn Around Time) in days
 */
export function calculateTAT(createdAt, completedDate) {
  if (!createdAt || !completedDate) return null

  const created = new Date(createdAt)
  const completed = new Date(completedDate)

  return Math.floor((completed - created) / (1000 * 60 * 60 * 24))
}
