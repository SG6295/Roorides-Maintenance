import { supabase } from '../lib/supabase'

/* ─────────────────────────────────────────────────────────────────────────────
 * PARKED — nothing imports this file today (MAIN-43).
 *
 * It is NOT dead code and must NOT be deleted. SLA is currently calculated by
 * database triggers; this module is the frontend counterpart, kept to be fixed
 * and wired up rather than thrown away. It has been mistaken for dead code once
 * already, so please read MAIN-43 before touching it.
 *
 * Known defect while it sits here: every `new Date(value)` below parses a naive
 * Postgres timestamp as local time, which is 5.5 hours early for IST — the
 * MAIN-42 bug. Use src/utils/datetime.js when this is revived.
 *
 * What MAIN-45 settled, which this file does NOT yet reflect:
 *
 *   • A deadline is a timestamptz, not a date. The old open question — start or
 *     end of the day — is gone: a deadline carries the time of day the work was
 *     raised. Raised 22:00, due 22:00.
 *   • EVERY SLA counts working days, skipping sla_weekly_offs and the holidays
 *     calendar. calculateSLAEndDate() below already walks working days, but
 *     checkAcceptanceSLA() and checkCompletionSLA() still reason in flat 24-hour
 *     days and would disagree with the database.
 *   • The calendar walk belongs in IST. calculateSLAEndDate() matches holidays
 *     with toISOString().split('T')[0], the UTC date, so between 00:00 and 05:30
 *     IST it tests the wrong day.
 *   • Deadlines are recomputed when rules or the calendar change, for open work
 *     only. Anything here that caches a deadline has to honour that.
 *
 * Whatever this becomes, it must not re-derive a deadline the database already
 * stores — that divergence was the bug MAIN-45 existed to kill. Read the stored
 * value; compute only what is genuinely not persisted.
 *
 * ► DELETE THIS BANNER as part of MAIN-43, once the file is fixed and imported.
 *   Leaving it here after that would be worse than not having written it.
 * ───────────────────────────────────────────────────────────────────────────── */

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
 * Fetch SLA days from database based on severity and category
 * Returns default 3 if not found or error
 *
 * Reads `sla_rules_config` — the table the DB triggers use. This used to query
 * `sla_rules`, which nothing consumed and which MAIN-47 dropped; the argument was
 * named `impact` after that table's column, but the issues table calls it `severity`.
 */
export async function fetchSLADays(severity, category) {
  if (!severity || !category) return 3

  try {
    const { data, error } = await supabase
      .from('sla_rules_config')
      .select('sla_days')
      .eq('severity', severity)
      .eq('category', category)
      .single()

    if (error || !data) {
      console.warn('SLA rule not found, using default 3 days', error)
      return 3
    }

    return data.sla_days
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
