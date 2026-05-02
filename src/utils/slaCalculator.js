import { supabase } from '../lib/supabase'

/* 
 * NOTE: Acceptance SLA is dynamic based on system_settings.
 * Completion SLA is dynamic based on database rules.
 */

// Default fallback if DB fetch fails
const DEFAULT_ACCEPTANCE_SLA_DAYS = 1

/**
 * Fetch a system setting by key
 */
export async function fetchSystemSetting(key) {
  try {
    const { data, error } = await supabase
      .from('system_settings')
      .select('value')
      .eq('key', key)
      .single()

    if (error) return null
    return data.value
  } catch (err) {
    console.error(`Error fetching setting ${key}:`, err)
    return null
  }
}

/**
 * Fetch SLA days from database based on impact and category
 * Returns default 3 if not found or error
 */
export async function fetchSLADays(impact, category) {
  if (!impact || !category) return 3

  try {
    const { data, error } = await supabase
      .from('sla_rules')
      .select('days')
      .eq('impact', impact)
      .eq('category', category)
      .single()

    if (error || !data) {
      console.warn('SLA rule not found, using default 3 days', error)
      return 3
    }

    return data.days
  } catch (err) {
    console.error('Error fetching SLA:', err)
    return 3
  }
}

/**
 * Calculate SLA end date skipping holidays and weekly offs
 */
export async function calculateSLAEndDate(createdAt, slaDays) {
  if (!createdAt || !slaDays) return null

  try {
    // 1. Fetch configuration
    const [settingsRes, holidaysRes] = await Promise.all([
      supabase.from('system_settings').select('value').eq('key', 'sla_weekly_offs').single(),
      supabase.from('holidays').select('date')
    ])

    const weeklyOffs = settingsRes.data ? JSON.parse(settingsRes.data.value) : [0] // Default Sunday (0)
    const holidays = new Set(holidaysRes.data?.map(h => h.date) || [])

    let currentDate = new Date(createdAt)
    let daysAdded = 0

    // 2. Add days one by one, skipping offs
    while (daysAdded < slaDays) {
      currentDate.setDate(currentDate.getDate() + 1)

      const dayOfWeek = currentDate.getDay() // 0-6
      const dateString = currentDate.toISOString().split('T')[0] // YYYY-MM-DD

      // Check if working day
      const isWeeklyOff = weeklyOffs.includes(dayOfWeek)
      const isHoliday = holidays.has(dateString)

      if (!isWeeklyOff && !isHoliday) {
        daysAdded++
      }
    }

    return currentDate
  } catch (err) {
    console.error('Error calculating SLA end date:', err)
    // Fallback to simple calculation
    const date = new Date(createdAt)
    date.setDate(date.getDate() + slaDays)
    return date
  }
}

/**
 * Check if assignment SLA is violated
 * Must be assigned within limit days of creation
 */
export function checkAcceptanceSLA(createdAt, assignedDate, limitDays = DEFAULT_ACCEPTANCE_SLA_DAYS) {
  if (!createdAt) return 'Pending'
  if (!assignedDate) {
    // Check if more than limit has passed since creation
    const daysSinceCreation = Math.floor((new Date() - new Date(createdAt)) / (1000 * 60 * 60 * 24))
    return daysSinceCreation > limitDays ? 'Violated' : 'Pending'
  }

  const created = new Date(createdAt)
  const assigned = new Date(assignedDate)
  const daysDiff = Math.floor((assigned - created) / (1000 * 60 * 60 * 24))

  return daysDiff <= limitDays ? 'Adhered' : 'Violated'
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
