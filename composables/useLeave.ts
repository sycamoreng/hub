import { useSupabase } from '~/utils/supabase'

export interface LeaveType {
  id: string
  name: string
  code: string
  color: string
  default_days_per_year: number
  paid: boolean
  requires_approval: boolean
  is_active: boolean
  sort_order: number
  description?: string
}

export interface PublicHoliday {
  id: string
  day: string
  name: string
  country: string
  recurring_yearly: boolean
  is_active: boolean
}

export function ymd(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${dd}`
}

export function enumerateDates(startISO: string, endISO: string): string[] {
  const out: string[] = []
  const s = new Date(startISO + 'T00:00:00')
  const e = new Date(endISO + 'T00:00:00')
  for (let d = new Date(s); d <= e; d.setDate(d.getDate() + 1)) {
    out.push(ymd(d))
  }
  return out
}

export function isWeekend(iso: string): boolean {
  const dow = new Date(iso + 'T00:00:00').getDay()
  return dow === 0 || dow === 6
}

export function computeWorkingDays(
  startISO: string,
  endISO: string,
  holidays: PublicHoliday[],
  halfDayStart = false,
  halfDayEnd = false
): number {
  const holidaySet = new Set<string>()
  const year = new Date(startISO + 'T00:00:00').getFullYear()
  for (const h of holidays) {
    if (!h.is_active) continue
    if (h.recurring_yearly) {
      const md = h.day.slice(5) // MM-DD
      holidaySet.add(`${year}-${md}`)
      holidaySet.add(`${year + 1}-${md}`)
    } else {
      holidaySet.add(h.day)
    }
  }
  const dates = enumerateDates(startISO, endISO)
  let days = 0
  for (const d of dates) {
    if (isWeekend(d)) continue
    if (holidaySet.has(d)) continue
    days += 1
  }
  if (days > 0 && halfDayStart) days -= 0.5
  if (days > 0 && halfDayEnd && startISO !== endISO) days -= 0.5
  return Math.max(0, days)
}

export function useLeave() {
  const supabase = useSupabase()

  async function loadLeaveTypes(): Promise<LeaveType[]> {
    const { data } = await supabase
      .from('leave_types')
      .select('*')
      .order('sort_order')
      .order('name')
    return (data ?? []) as any
  }

  async function loadPublicHolidays(): Promise<PublicHoliday[]> {
    const { data } = await supabase
      .from('public_holidays')
      .select('*')
      .eq('is_active', true)
      .order('day')
    return (data ?? []) as any
  }

  async function loadStaffBalances(staffId: string, year: number) {
    const { data } = await supabase
      .from('leave_balances')
      .select('*, leave_type:leave_types(*)')
      .eq('staff_id', staffId)
      .eq('year', year)
    return data ?? []
  }

  async function ensureBalanceRows(staffId: string, year: number, types: LeaveType[]) {
    const { data } = await supabase
      .from('leave_balances')
      .select('leave_type_id')
      .eq('staff_id', staffId)
      .eq('year', year)
    const have = new Set((data ?? []).map((r: any) => r.leave_type_id))
    const toInsert = types
      .filter(t => t.is_active && !have.has(t.id))
      .map(t => ({
        staff_id: staffId,
        leave_type_id: t.id,
        year,
        allocated_days: t.default_days_per_year,
        used_days: 0,
        adjustment_days: 0
      }))
    if (toInsert.length) {
      await supabase.from('leave_balances').insert(toInsert)
    }
  }

  return {
    loadLeaveTypes,
    loadPublicHolidays,
    loadStaffBalances,
    ensureBalanceRows
  }
}
