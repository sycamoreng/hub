export const WEEKDAYS = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']
export const WEEKDAYS_SHORT = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat']

export function todayLocalISO(d = new Date()) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

export function formatTime(t: string | null | undefined) {
  if (!t) return '--'
  // t may be 'HH:MM:SS' or 'HH:MM'
  const [h, m] = t.split(':')
  const hour = Number(h); const minute = m ?? '00'
  const period = hour >= 12 ? 'PM' : 'AM'
  const h12 = hour % 12 === 0 ? 12 : hour % 12
  return `${h12}:${minute} ${period}`
}

export function formatDateTime(iso: string | null | undefined) {
  if (!iso) return '--'
  const d = new Date(iso)
  return d.toLocaleString('en-NG', { hour: '2-digit', minute: '2-digit', hour12: true })
}

export function durationHours(start: string | null | undefined, end: string | null | undefined) {
  if (!start || !end) return 0
  const ms = new Date(end).getTime() - new Date(start).getTime()
  return Math.max(0, ms / 3_600_000)
}

export function formatDuration(hours: number) {
  const h = Math.floor(hours)
  const m = Math.round((hours - h) * 60)
  return `${h}h ${String(m).padStart(2, '0')}m`
}

export function minutesLate(clockInIso: string | null | undefined, expectedStart: string | null | undefined, workDate: string) {
  if (!clockInIso || !expectedStart) return 0
  const expected = new Date(`${workDate}T${expectedStart.length === 5 ? expectedStart + ':00' : expectedStart}`)
  const actual = new Date(clockInIso)
  const diff = (actual.getTime() - expected.getTime()) / 60_000
  return Math.max(0, Math.round(diff))
}

export function statusFor(record: any): 'not-in' | 'in' | 'done' {
  if (!record) return 'not-in'
  if (record.clock_in_at && !record.clock_out_at) return 'in'
  if (record.clock_in_at && record.clock_out_at) return 'done'
  return 'not-in'
}
