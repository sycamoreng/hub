<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import {
  WEEKDAYS, WEEKDAYS_SHORT, todayLocalISO, formatTime, formatDateTime,
  durationHours, formatDuration, minutesLate, statusFor
} from '~/composables/useAttendance'

const supabase = useSupabase()
const { user } = useAuth()
const toast = useToast()

const staffRow = ref<any | null>(null)
const schedule = ref<any[]>([])
const effectiveSource = ref<'personal' | 'group' | 'department' | 'location' | 'organization' | 'none'>('none')
const effectiveTemplateName = ref<string>('')
const today = ref(todayLocalISO())
const todayRecord = ref<any | null>(null)
const weekRecords = ref<any[]>([])
const historyRecords = ref<any[]>([])
const dayOverride = ref<any | null>(null)
const loading = ref(true)
const pending = ref(false)
const now = ref(new Date())
const historyRange = ref<'week' | 'month' | 'quarter' | 'year'>('week')

let clockInterval: any
onMounted(() => { clockInterval = setInterval(() => { now.value = new Date() }, 1000) })
onBeforeUnmount(() => { if (clockInterval) clearInterval(clockInterval) })

const todaysWeekday = computed(() => new Date(today.value).getDay())
const todaysSchedule = computed(() => schedule.value.find(s => s.weekday === todaysWeekday.value) ?? null)

const status = computed(() => statusFor(todayRecord.value))
const elapsed = computed(() => {
  if (!todayRecord.value?.clock_in_at) return 0
  const end = todayRecord.value.clock_out_at ? new Date(todayRecord.value.clock_out_at) : now.value
  return (end.getTime() - new Date(todayRecord.value.clock_in_at).getTime()) / 3_600_000
})

const lateMinutes = computed(() => minutesLate(todayRecord.value?.clock_in_at, todaysSchedule.value?.start_time, today.value))

async function load() {
  loading.value = true
  try {
    if (!user.value) return
    const { data: sm } = await supabase.from('staff_members').select('id, full_name, email, department_id, location_id').eq('auth_user_id', user.value.id).maybeSingle()
    staffRow.value = sm
    if (!sm) { loading.value = false; return }

    const weekAgo = todayLocalISO(new Date(Date.now() - 6 * 86400000))
    const yearAgo = todayLocalISO(new Date(Date.now() - 400 * 86400000))
    const smAny: any = sm

    const [{ data: sched }, { data: rec }, { data: week }, { data: history }, { data: override }, { data: memberTpls }, { data: defaultTpls }] = await Promise.all([
      supabase.from('staff_schedules').select('*').eq('staff_id', smAny.id),
      supabase.from('attendance_records').select('*').eq('staff_id', smAny.id).eq('work_date', today.value).maybeSingle(),
      supabase.from('attendance_records').select('*').eq('staff_id', smAny.id).gte('work_date', weekAgo).lte('work_date', today.value).order('work_date', { ascending: false }),
      supabase.from('attendance_records').select('*').eq('staff_id', smAny.id).gte('work_date', yearAgo).lte('work_date', today.value).order('work_date', { ascending: true }),
      supabase.from('attendance_days').select('*').eq('day', today.value).or(`staff_id.is.null,staff_id.eq.${smAny.id}`).maybeSingle(),
      supabase.from('schedule_template_members').select('template:schedule_templates(id, name, scope, department_id, location_id, updated_at, schedule_template_days(weekday, is_working, start_time, end_time))').eq('staff_id', smAny.id),
      supabase.from('schedule_templates').select('id, name, scope, department_id, location_id, is_default, schedule_template_days(weekday, is_working, start_time, end_time)').eq('is_default', true)
    ])

    todayRecord.value = rec ?? null
    weekRecords.value = week ?? []
    historyRecords.value = history ?? []
    dayOverride.value = override ?? null

    const personal = sched ?? []
    const applyTemplate = (tpl: any, source: typeof effectiveSource.value) => {
      schedule.value = (tpl.schedule_template_days ?? []).map((d: any) => ({
        weekday: d.weekday,
        is_working: d.is_working,
        start_time: (d.start_time || '09:00').toString().slice(0, 5),
        end_time: (d.end_time || '17:00').toString().slice(0, 5)
      }))
      effectiveSource.value = source
      effectiveTemplateName.value = tpl.name ?? ''
    }

    if (personal.length > 0) {
      schedule.value = personal
      effectiveSource.value = 'personal'
      effectiveTemplateName.value = ''
    } else {
      const memberships = (memberTpls ?? []).map((m: any) => m.template).filter(Boolean)
      const sortedMemberships = memberships.sort((a: any, b: any) => new Date(b.updated_at || 0).getTime() - new Date(a.updated_at || 0).getTime())
      const explicit = sortedMemberships[0]
      const list = defaultTpls ?? []
      const dept = list.find((t: any) => t.scope === 'department' && t.department_id === smAny.department_id)
      const loc = list.find((t: any) => t.scope === 'location' && t.location_id === smAny.location_id)
      const org = list.find((t: any) => t.scope === 'organization')
      if (explicit) applyTemplate(explicit, 'group')
      else if (dept) applyTemplate(dept, 'department')
      else if (loc) applyTemplate(loc, 'location')
      else if (org) applyTemplate(org, 'organization')
      else {
        schedule.value = []
        effectiveSource.value = 'none'
        effectiveTemplateName.value = ''
      }
    }
  } finally { loading.value = false }
}

async function clockIn() {
  if (!staffRow.value) return
  pending.value = true
  try {
    const payload = {
      staff_id: staffRow.value.id,
      work_date: today.value,
      clock_in_at: new Date().toISOString(),
      expected_start: todaysSchedule.value?.start_time ?? null,
      expected_end: todaysSchedule.value?.end_time ?? null
    }
    const { data, error } = await supabase.from('attendance_records').upsert(payload, { onConflict: 'staff_id,work_date' }).select().maybeSingle()
    if (error) throw error
    todayRecord.value = data
    try {
      const { data: s } = await supabase.auth.getUser()
      if (s.user?.id) {
        await supabase.from('points_events').upsert({
          user_id: s.user.id,
          event_kind: 'attendance_clock_in',
          ref_type: 'attendance',
          ref_id: today.value,
          points: 2
        }, { onConflict: 'user_id,event_kind,ref_type,ref_id', ignoreDuplicates: true })
      }
    } catch { /* non-fatal */ }
    toast.success('Clocked in')
    await load()
  } catch (e: any) { toast.error(e.message ?? 'Failed to clock in') }
  finally { pending.value = false }
}

async function clockOut() {
  if (!todayRecord.value) return
  pending.value = true
  try {
    const { data, error } = await supabase.from('attendance_records')
      .update({ clock_out_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq('id', todayRecord.value.id).select().maybeSingle()
    if (error) throw error
    todayRecord.value = data
    toast.success('Clocked out')
  } catch (e: any) { toast.error(e.message ?? 'Failed to clock out') }
  finally { pending.value = false }
}

load()

const LATE_GRACE_MINUTES = 5

const weekDaysData = computed(() => {
  const out: any[] = []
  for (let i = 6; i >= 0; i--) {
    const d = new Date()
    d.setDate(d.getDate() - i)
    const iso = todayLocalISO(d)
    const rec = weekRecords.value.find(r => r.work_date === iso)
    const wd = d.getDay()
    const sch = schedule.value.find(s => s.weekday === wd)
    const late = rec ? minutesLate(rec.clock_in_at, sch?.start_time, iso) : 0
    const isPast = iso < today.value
    const isToday = iso === today.value
    let dayStatus: 'off' | 'present' | 'late' | 'absent' | 'pending'
    if (!sch?.is_working) dayStatus = 'off'
    else if (rec?.clock_in_at) dayStatus = late > LATE_GRACE_MINUTES ? 'late' : 'present'
    else if (isPast) dayStatus = 'absent'
    else dayStatus = 'pending'
    out.push({ iso, weekday: wd, label: WEEKDAYS_SHORT[wd], day: d.getDate(), schedule: sch, record: rec, late, dayStatus, isToday })
  }
  return out
})

const weekSummary = computed(() => {
  const days = weekDaysData.value
  const scheduled = days.filter(d => d.schedule?.is_working)
  const present = days.filter(d => d.dayStatus === 'present').length
  const lateDays = days.filter(d => d.dayStatus === 'late')
  const absent = days.filter(d => d.dayStatus === 'absent').length
  const totalLateMins = lateDays.reduce((sum, d) => sum + (d.late || 0), 0)
  const hoursWorked = days.reduce((sum, d) => {
    if (d.record?.clock_in_at && d.record?.clock_out_at) return sum + durationHours(d.record.clock_in_at, d.record.clock_out_at)
    return sum
  }, 0)
  return {
    scheduledDays: scheduled.length,
    present,
    late: lateDays.length,
    absent,
    totalLateMins,
    hoursWorked
  }
})

const nowString = computed(() => now.value.toLocaleTimeString('en-NG', { hour: '2-digit', minute: '2-digit', second: '2-digit' }))

type Bucket = {
  key: string
  label: string
  start: string
  end: string
  scheduled: number
  present: number
  late: number
  absent: number
  totalLateMins: number
  hoursWorked: number
}

function isoWeekKey(d: Date) {
  const tmp = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
  const dayNum = tmp.getUTCDay() || 7
  tmp.setUTCDate(tmp.getUTCDate() + 4 - dayNum)
  const yearStart = new Date(Date.UTC(tmp.getUTCFullYear(), 0, 1))
  const week = Math.ceil((((tmp.getTime() - yearStart.getTime()) / 86400000) + 1) / 7)
  return { year: tmp.getUTCFullYear(), week }
}

function bucketFor(d: Date, range: typeof historyRange.value): { key: string; label: string; start: Date; end: Date } {
  if (range === 'week') {
    const { year, week } = isoWeekKey(d)
    // Monday start of ISO week
    const day = d.getDay() || 7
    const monday = new Date(d); monday.setDate(d.getDate() - (day - 1))
    const sunday = new Date(monday); sunday.setDate(monday.getDate() + 6)
    return { key: `${year}-W${String(week).padStart(2, '0')}`, label: `W${week} ${year}`, start: monday, end: sunday }
  }
  if (range === 'month') {
    const start = new Date(d.getFullYear(), d.getMonth(), 1)
    const end = new Date(d.getFullYear(), d.getMonth() + 1, 0)
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    const label = start.toLocaleDateString('en-NG', { month: 'short', year: 'numeric' })
    return { key, label, start, end }
  }
  if (range === 'quarter') {
    const q = Math.floor(d.getMonth() / 3)
    const start = new Date(d.getFullYear(), q * 3, 1)
    const end = new Date(d.getFullYear(), q * 3 + 3, 0)
    return { key: `${d.getFullYear()}-Q${q + 1}`, label: `Q${q + 1} ${d.getFullYear()}`, start, end }
  }
  const start = new Date(d.getFullYear(), 0, 1)
  const end = new Date(d.getFullYear(), 11, 31)
  return { key: `${d.getFullYear()}`, label: `${d.getFullYear()}`, start, end }
}

const historyBuckets = computed<Bucket[]>(() => {
  const range = historyRange.value
  const recordByDate = new Map<string, any>()
  for (const r of historyRecords.value) recordByDate.set(r.work_date, r)
  const scheduleByWeekday = new Map<number, any>()
  for (const s of schedule.value) scheduleByWeekday.set(s.weekday, s)

  const buckets = new Map<string, Bucket>()
  const todayDate = new Date(today.value)
  // Define start window per range.
  const starts: Date = (() => {
    if (range === 'week') { const d = new Date(todayDate); d.setDate(d.getDate() - 7 * 11); return d } // 12 weeks
    if (range === 'month') return new Date(todayDate.getFullYear(), todayDate.getMonth() - 11, 1) // 12 months
    if (range === 'quarter') return new Date(todayDate.getFullYear() - 1, 0, 1) // ~8 quarters
    return new Date(todayDate.getFullYear() - 4, 0, 1) // 5 years
  })()

  for (let d = new Date(starts); d <= todayDate; d.setDate(d.getDate() + 1)) {
    const iso = todayLocalISO(d)
    const wd = d.getDay()
    const sch = scheduleByWeekday.get(wd)
    const rec = recordByDate.get(iso)
    const b = bucketFor(d, range)
    let bucket = buckets.get(b.key)
    if (!bucket) {
      bucket = {
        key: b.key, label: b.label,
        start: todayLocalISO(b.start), end: todayLocalISO(b.end),
        scheduled: 0, present: 0, late: 0, absent: 0, totalLateMins: 0, hoursWorked: 0
      }
      buckets.set(b.key, bucket)
    }
    if (sch?.is_working) bucket.scheduled += 1
    if (rec?.clock_in_at) {
      const late = minutesLate(rec.clock_in_at, sch?.start_time, iso)
      if (late > LATE_GRACE_MINUTES) { bucket.late += 1; bucket.totalLateMins += late }
      else bucket.present += 1
      if (rec.clock_out_at) bucket.hoursWorked += durationHours(rec.clock_in_at, rec.clock_out_at)
    } else if (sch?.is_working && iso < today.value) {
      bucket.absent += 1
    }
  }
  return Array.from(buckets.values()).sort((a, b) => b.start.localeCompare(a.start))
})

const historyMaxScheduled = computed(() => Math.max(1, ...historyBuckets.value.map(b => b.scheduled || 1)))
</script>

<template>
  <div class="max-w-5xl mx-auto">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">Attendance</h1>
      <p class="text-sm text-slate-500 mt-1">Clock in when you start, clock out when you finish.</p>
    </header>

    <div v-if="loading" class="text-sm text-slate-500">Loading...</div>

    <div v-else-if="!staffRow" class="bg-amber-50 border border-amber-200 rounded-xl p-5 text-sm text-amber-900">
      No staff record linked to your account yet. Ask an admin to add you to the staff directory.
    </div>

    <template v-else>
      <section class="bg-white border border-slate-200 rounded-2xl overflow-hidden mb-8">
        <div class="grid grid-cols-1 md:grid-cols-2">
          <div class="p-6 md:p-8 border-b md:border-b-0 md:border-r border-slate-200">
            <div class="text-xs uppercase tracking-wide text-slate-500 mb-1">Today &middot; {{ WEEKDAYS[todaysWeekday] }}</div>
            <div class="text-3xl sm:text-5xl font-semibold text-slate-900 tabular-nums">{{ nowString }}</div>

            <div v-if="dayOverride" class="mt-4 inline-flex items-center gap-2 px-3 py-1 rounded-full bg-amber-50 border border-amber-200 text-amber-800 text-xs font-semibold">
              {{ dayOverride.label || dayOverride.kind }}
            </div>

            <div v-if="todaysSchedule?.is_working" class="mt-4 text-sm text-slate-600">
              Scheduled
              <strong class="text-slate-900">{{ formatTime(todaysSchedule.start_time) }}</strong>
              to
              <strong class="text-slate-900">{{ formatTime(todaysSchedule.end_time) }}</strong>
            </div>
            <div v-else class="mt-4 text-sm text-slate-600">No shift scheduled for today.</div>
            <div v-if="effectiveSource !== 'none' && effectiveSource !== 'personal'" class="mt-2 text-[11px] text-slate-400">
              From {{ effectiveSource }} template<span v-if="effectiveTemplateName"> &middot; {{ effectiveTemplateName }}</span>
            </div>
          </div>

          <div class="p-6 md:p-8 flex flex-col justify-center">
            <div v-if="status === 'not-in'">
              <button
                type="button"
                :disabled="pending"
                @click="clockIn"
                class="w-full px-5 py-3.5 sm:px-6 sm:py-5 bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-50 text-white rounded-xl text-base sm:text-lg font-semibold shadow-sm transition-colors"
              >
                {{ pending ? 'Clocking in...' : 'Clock in' }}
              </button>
              <p v-if="todaysSchedule?.is_working" class="mt-3 text-xs text-slate-500 text-center">
                Shift starts at {{ formatTime(todaysSchedule.start_time) }}
              </p>
            </div>
            <div v-else-if="status === 'in'">
              <div class="mb-4">
                <div class="text-xs text-slate-500 uppercase tracking-wide">Clocked in</div>
                <div class="text-xl sm:text-2xl font-semibold text-slate-900 tabular-nums">{{ formatDateTime(todayRecord.clock_in_at) }}</div>
                <div class="mt-1 text-sm text-slate-600">Elapsed <span class="font-semibold text-slate-900">{{ formatDuration(elapsed) }}</span></div>
                <div v-if="lateMinutes > 0" class="mt-1 text-xs font-semibold text-amber-700">{{ lateMinutes }} min late</div>
              </div>
              <button
                type="button"
                :disabled="pending"
                @click="clockOut"
                class="w-full px-5 py-3.5 sm:px-6 sm:py-5 bg-slate-900 hover:bg-slate-800 disabled:opacity-50 text-white rounded-xl text-base sm:text-lg font-semibold shadow-sm transition-colors"
              >
                {{ pending ? 'Clocking out...' : 'Clock out' }}
              </button>
            </div>
            <div v-else class="text-center">
              <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs font-semibold mb-3">
                Done for today
              </div>
              <div class="text-sm text-slate-600">
                <div>In &middot; <span class="tabular-nums font-medium text-slate-900">{{ formatDateTime(todayRecord.clock_in_at) }}</span></div>
                <div>Out &middot; <span class="tabular-nums font-medium text-slate-900">{{ formatDateTime(todayRecord.clock_out_at) }}</span></div>
                <div class="mt-2">Worked <span class="font-semibold text-slate-900">{{ formatDuration(elapsed) }}</span></div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="mb-8">
        <h2 class="text-sm font-semibold text-slate-900 mb-3">Weekly summary</h2>
        <div class="grid grid-cols-2 sm:grid-cols-5 gap-2 sm:gap-3">
          <div class="bg-white border border-slate-200 rounded-xl p-3 sm:p-4">
            <div class="text-[10px] sm:text-xs text-slate-500">Scheduled days</div>
            <div class="text-base sm:text-lg font-semibold text-slate-900 tabular-nums">{{ weekSummary.scheduledDays }}</div>
          </div>
          <div class="bg-white border border-slate-200 rounded-xl p-3 sm:p-4">
            <div class="text-[10px] sm:text-xs text-slate-500">On time</div>
            <div class="text-base sm:text-lg font-semibold text-emerald-700 tabular-nums">{{ weekSummary.present }}</div>
          </div>
          <div class="bg-white border border-slate-200 rounded-xl p-3 sm:p-4">
            <div class="text-[10px] sm:text-xs text-slate-500">Late arrivals</div>
            <div class="text-base sm:text-lg font-semibold text-amber-700 tabular-nums">{{ weekSummary.late }}</div>
            <div v-if="weekSummary.totalLateMins" class="text-[10px] sm:text-[11px] text-amber-600 mt-0.5">{{ weekSummary.totalLateMins }} min total</div>
          </div>
          <div class="bg-white border border-slate-200 rounded-xl p-3 sm:p-4">
            <div class="text-[10px] sm:text-xs text-slate-500">Absences</div>
            <div class="text-base sm:text-lg font-semibold text-rose-700 tabular-nums">{{ weekSummary.absent }}</div>
          </div>
          <div class="bg-white border border-slate-200 rounded-xl p-3 sm:p-4 col-span-2 sm:col-span-1">
            <div class="text-[10px] sm:text-xs text-slate-500">Hours worked</div>
            <div class="text-base sm:text-lg font-semibold text-slate-900 tabular-nums">{{ formatDuration(weekSummary.hoursWorked) }}</div>
          </div>
        </div>
      </section>

      <section class="mb-8">
        <header class="flex items-center justify-between mb-3 gap-2 flex-wrap">
          <h2 class="text-sm font-semibold text-slate-900">Attendance history</h2>
          <div class="inline-flex rounded-lg border border-slate-200 overflow-hidden text-[10px] sm:text-xs">
            <button v-for="r in (['week','month','quarter','year'] as const)" :key="r" type="button"
              @click="historyRange = r"
              :class="historyRange === r ? 'bg-slate-900 text-white' : 'bg-white text-slate-600 hover:bg-slate-50'"
              class="px-2 sm:px-3 py-1 sm:py-1.5 font-medium capitalize border-r last:border-r-0 border-slate-200">
              <span class="hidden sm:inline">{{ r === 'week' ? 'Week-on-week' : r === 'month' ? 'Month-on-month' : r === 'quarter' ? 'Quarter-on-quarter' : 'Year-on-year' }}</span>
              <span class="sm:hidden">{{ r === 'week' ? 'Week' : r === 'month' ? 'Month' : r === 'quarter' ? 'Qtr' : 'Year' }}</span>
            </button>
          </div>
        </header>
        <div v-if="historyBuckets.length === 0" class="text-xs text-slate-400 italic bg-white border border-slate-200 rounded-xl p-4">
          No attendance history yet.
        </div>
        <div v-else class="bg-white border border-slate-200 rounded-xl overflow-x-auto">
          <table class="w-full text-xs sm:text-sm min-w-[600px]">
            <thead class="bg-slate-50 text-slate-500 text-[10px] sm:text-xs uppercase tracking-wide">
              <tr>
                <th class="text-left px-3 sm:px-4 py-2 capitalize">{{ historyRange }}</th>
                <th class="text-right px-3 sm:px-4 py-2">Scheduled</th>
                <th class="text-right px-3 sm:px-4 py-2">On time</th>
                <th class="text-right px-3 sm:px-4 py-2">Late</th>
                <th class="text-right px-3 sm:px-4 py-2">Absent</th>
                <th class="text-right px-3 sm:px-4 py-2">Hours</th>
                <th class="px-3 sm:px-4 py-2 w-32 sm:w-40">Attendance</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="b in historyBuckets" :key="b.key" class="border-t border-slate-100">
                <td class="px-3 sm:px-4 py-2 font-medium text-slate-900">{{ b.label }}</td>
                <td class="px-3 sm:px-4 py-2 text-right tabular-nums text-slate-700">{{ b.scheduled }}</td>
                <td class="px-3 sm:px-4 py-2 text-right tabular-nums text-emerald-700 font-semibold">{{ b.present }}</td>
                <td class="px-3 sm:px-4 py-2 text-right tabular-nums">
                  <span class="text-amber-700 font-semibold">{{ b.late }}</span>
                  <span v-if="b.totalLateMins" class="text-[10px] sm:text-[11px] text-amber-500 ml-1">({{ b.totalLateMins }}m)</span>
                </td>
                <td class="px-3 sm:px-4 py-2 text-right tabular-nums text-rose-700 font-semibold">{{ b.absent }}</td>
                <td class="px-3 sm:px-4 py-2 text-right tabular-nums text-slate-700">{{ formatDuration(b.hoursWorked) }}</td>
                <td class="px-3 sm:px-4 py-2">
                  <div class="h-2 rounded-full bg-slate-100 overflow-hidden flex">
                    <div class="bg-emerald-500" :style="{ width: `${(b.present / historyMaxScheduled) * 100}%` }"></div>
                    <div class="bg-amber-500" :style="{ width: `${(b.late / historyMaxScheduled) * 100}%` }"></div>
                    <div class="bg-rose-500" :style="{ width: `${(b.absent / historyMaxScheduled) * 100}%` }"></div>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 class="text-sm font-semibold text-slate-900 mb-3">This week</h2>
        <div class="grid grid-cols-7 gap-1 sm:gap-2">
          <div v-for="d in weekDaysData" :key="d.iso"
            class="bg-white border rounded-lg sm:rounded-xl p-1.5 sm:p-3 text-center"
            :class="d.iso === today ? 'border-sycamore-300 ring-1 ring-sycamore-200' : 'border-slate-200'">
            <div class="text-[9px] sm:text-[10px] uppercase tracking-wide text-slate-400">{{ d.label }}</div>
            <div class="text-sm sm:text-lg font-semibold text-slate-900">{{ d.day }}</div>

            <div class="mt-1.5 mb-1 flex justify-center">
              <span v-if="d.dayStatus === 'present'" class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">On time</span>
              <span v-else-if="d.dayStatus === 'late'" class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 border border-amber-200">{{ d.late }}m late</span>
              <span v-else-if="d.dayStatus === 'absent'" class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-rose-50 text-rose-700 border border-rose-200">Absent</span>
              <span v-else-if="d.dayStatus === 'pending' && d.isToday" class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-slate-100 text-slate-600 border border-slate-200">Pending</span>
              <span v-else-if="d.dayStatus === 'pending'" class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-slate-50 text-slate-400 border border-slate-200">—</span>
              <span v-else class="text-[10px] font-semibold px-2 py-0.5 rounded-full bg-slate-50 text-slate-400 border border-slate-200">Off</span>
            </div>

            <div v-if="d.record?.clock_in_at" class="text-[11px] text-slate-600">
              <div class="tabular-nums">{{ formatDateTime(d.record.clock_in_at) }}</div>
              <div v-if="d.record.clock_out_at" class="tabular-nums text-slate-400">{{ formatDateTime(d.record.clock_out_at) }}</div>
            </div>
            <div v-else-if="d.schedule?.is_working" class="text-[11px] text-slate-400">
              {{ formatTime(d.schedule.start_time) }}
            </div>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
