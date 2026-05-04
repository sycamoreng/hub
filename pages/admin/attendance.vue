<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { WEEKDAYS, WEEKDAYS_SHORT, todayLocalISO, formatTime, formatDateTime, durationHours, formatDuration, minutesLate } from '~/composables/useAttendance'

definePageMeta({ layout: 'admin', middleware: ['auth'] })

const supabase = useSupabase()
const toast = useToast()

const tab = ref<'today' | 'schedules' | 'templates' | 'records' | 'days'>('today')

/* ---------- Shared: staff list ---------- */
const staff = ref<any[]>([])
const templates = ref<any[]>([])
const templateMembersByStaff = ref<Record<string, any[]>>({})
async function loadStaff() {
  const { data } = await supabase.from('staff_members').select('id, full_name, email, is_active, department_id, location_id').order('full_name')
  staff.value = (data ?? []).filter(s => s.is_active)
}
async function loadTemplates() {
  const [{ data: tpls }, { data: members }] = await Promise.all([
    supabase.from('schedule_templates')
      .select('id, name, scope, department_id, location_id, is_default, updated_at, schedule_template_days(weekday, is_working, start_time, end_time)'),
    supabase.from('schedule_template_members').select('staff_id, template_id')
  ])
  templates.value = tpls ?? []
  const byStaff: Record<string, any[]> = {}
  for (const m of (members ?? [])) {
    const tpl = (tpls ?? []).find((t: any) => t.id === m.template_id)
    if (!tpl) continue
    ;(byStaff[m.staff_id] ||= []).push(tpl)
  }
  templateMembersByStaff.value = byStaff
}
function scheduleForStaff(s: any, weekday: number) {
  const own = todaysSchedules.value.find(sc => sc.staff_id === s.id && sc.weekday === weekday)
  if (own) return own
  const memberships = (templateMembersByStaff.value[s.id] ?? []).slice().sort((a: any, b: any) =>
    new Date(b.updated_at || 0).getTime() - new Date(a.updated_at || 0).getTime())
  const explicit = memberships[0]
  const defaults = templates.value.filter((t: any) => t.is_default)
  const dept = defaults.find((t: any) => t.scope === 'department' && t.department_id === s.department_id)
  const loc = defaults.find((t: any) => t.scope === 'location' && t.location_id === s.location_id)
  const org = defaults.find((t: any) => t.scope === 'organization')
  const match = explicit || dept || loc || org
  const day = match?.schedule_template_days?.find((d: any) => d.weekday === weekday)
  if (!day) return null
  return {
    is_working: day.is_working,
    start_time: (day.start_time || '09:00').toString().slice(0, 5),
    end_time: (day.end_time || '17:00').toString().slice(0, 5)
  }
}

/* ---------- Today ---------- */
const today = ref(todayLocalISO())
const todaysRecords = ref<any[]>([])
const todaysSchedules = ref<any[]>([])
const todaysWeekday = computed(() => new Date(today.value).getDay())
async function loadToday() {
  const [{ data: records }, { data: scheds }] = await Promise.all([
    supabase.from('attendance_records').select('*').eq('work_date', today.value),
    supabase.from('staff_schedules').select('*').eq('weekday', todaysWeekday.value)
  ])
  todaysRecords.value = records ?? []
  todaysSchedules.value = scheds ?? []
}
const todayRows = computed(() => {
  return staff.value.map(s => {
    const schedule = scheduleForStaff(s, todaysWeekday.value)
    const record = todaysRecords.value.find(r => r.staff_id === s.id)
    let status = 'No shift'
    if (schedule?.is_working) {
      if (!record?.clock_in_at) status = 'Not in'
      else if (!record.clock_out_at) status = 'Clocked in'
      else status = 'Done'
    }
    const late = minutesLate(record?.clock_in_at, schedule?.start_time, today.value)
    return { staff: s, schedule, record, status, late }
  })
})
function statusClass(s: string) {
  if (s === 'Clocked in') return 'bg-sky-50 text-sky-700 border-sky-200'
  if (s === 'Done') return 'bg-emerald-50 text-emerald-700 border-emerald-200'
  if (s === 'Not in') return 'bg-rose-50 text-rose-700 border-rose-200'
  return 'bg-slate-50 text-slate-500 border-slate-200'
}

/* ---------- Schedules editor ---------- */
const selectedStaffId = ref<string>('')
const staffSchedule = ref<Record<number, any>>({})
const scheduleSource = ref<'personal' | 'group' | 'department' | 'location' | 'organization' | 'none'>('none')
const scheduleSourceName = ref<string>('')

function templateFor(staffRow: any) {
  if (!staffRow) return null
  const memberships = (templateMembersByStaff.value[staffRow.id] ?? []).slice().sort((a: any, b: any) =>
    new Date(b.updated_at || 0).getTime() - new Date(a.updated_at || 0).getTime())
  const explicit = memberships[0]
  const defaults = templates.value.filter((t: any) => t.is_default)
  const dept = defaults.find((t: any) => t.scope === 'department' && t.department_id === staffRow.department_id)
  const loc = defaults.find((t: any) => t.scope === 'location' && t.location_id === staffRow.location_id)
  const org = defaults.find((t: any) => t.scope === 'organization')
  if (explicit) return { tpl: explicit, source: 'group' as const }
  if (dept) return { tpl: dept, source: 'department' as const }
  if (loc) return { tpl: loc, source: 'location' as const }
  if (org) return { tpl: org, source: 'organization' as const }
  return null
}

async function loadStaffSchedule() {
  if (!selectedStaffId.value) { staffSchedule.value = {}; scheduleSource.value = 'none'; scheduleSourceName.value = ''; return }
  const staffRow = staff.value.find(s => s.id === selectedStaffId.value)
  const { data } = await supabase.from('staff_schedules').select('*').eq('staff_id', selectedStaffId.value)
  const map: Record<number, any> = {}

  const personal = data ?? []
  const hasPersonal = personal.length > 0

  if (hasPersonal) {
    for (let d = 0; d < 7; d++) map[d] = { weekday: d, is_working: d >= 1 && d <= 5, start_time: '09:00', end_time: '17:00' }
    for (const r of personal) map[r.weekday] = {
      ...r,
      start_time: (r.start_time || '09:00').slice(0, 5),
      end_time: (r.end_time || '17:00').slice(0, 5)
    }
    scheduleSource.value = 'personal'
    scheduleSourceName.value = ''
  } else {
    const match = templateFor(staffRow)
    if (match) {
      for (let d = 0; d < 7; d++) {
        const day = match.tpl.schedule_template_days?.find((x: any) => x.weekday === d)
        map[d] = day
          ? { weekday: d, is_working: day.is_working, start_time: (day.start_time || '09:00').toString().slice(0, 5), end_time: (day.end_time || '17:00').toString().slice(0, 5) }
          : { weekday: d, is_working: false, start_time: '09:00', end_time: '17:00' }
      }
      scheduleSource.value = match.source
      scheduleSourceName.value = match.tpl.name ?? ''
    } else {
      for (let d = 0; d < 7; d++) map[d] = { weekday: d, is_working: d >= 1 && d <= 5, start_time: '09:00', end_time: '17:00' }
      scheduleSource.value = 'none'
      scheduleSourceName.value = ''
    }
  }
  staffSchedule.value = map
}

async function clearPersonalSchedule() {
  if (!selectedStaffId.value) return
  if (!(await toast.confirm({ title: 'Remove personal schedule', message: 'Revert this staff member to their group or default template?', variant: 'danger', confirmLabel: 'Remove override' }))) return
  const { error } = await supabase.from('staff_schedules').delete().eq('staff_id', selectedStaffId.value)
  if (error) { toast.error(error.message); return }
  toast.success('Personal override removed')
  await loadStaffSchedule()
}
const savingSchedule = ref(false)
async function saveSchedule() {
  if (!selectedStaffId.value) return
  savingSchedule.value = true
  try {
    const rows = Object.values(staffSchedule.value).map((r: any) => ({
      staff_id: selectedStaffId.value,
      weekday: r.weekday,
      is_working: Boolean(r.is_working),
      start_time: r.start_time || '09:00',
      end_time: r.end_time || '17:00',
      updated_at: new Date().toISOString()
    }))
    const { error } = await supabase.from('staff_schedules').upsert(rows, { onConflict: 'staff_id,weekday' })
    if (error) throw error
    toast.success('Schedule saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { savingSchedule.value = false }
}

watch(selectedStaffId, loadStaffSchedule)

/* ---------- Records (range view) ---------- */
const rangeStart = ref(todayLocalISO(new Date(Date.now() - 7 * 86400000)))
const rangeEnd = ref(todayLocalISO())
const rangeStaffId = ref<string>('')
const rangeLoading = ref(false)
const rangeRecords = ref<any[]>([])
async function loadRange() {
  rangeLoading.value = true
  try {
    let q = supabase.from('attendance_records').select('*').gte('work_date', rangeStart.value).lte('work_date', rangeEnd.value).order('work_date', { ascending: false })
    if (rangeStaffId.value) q = q.eq('staff_id', rangeStaffId.value)
    const { data, error } = await q
    if (error) throw error
    rangeRecords.value = data ?? []
  } finally { rangeLoading.value = false }
}
function staffName(id: string) {
  return staff.value.find(s => s.id === id)?.full_name ?? '—'
}
function exportCsv() {
  const header = ['Date','Staff','Email','Clock in','Clock out','Hours','Late (min)','Notes']
  const lines = [header.join(',')]
  for (const r of rangeRecords.value) {
    const s = staff.value.find(x => x.id === r.staff_id)
    const hours = durationHours(r.clock_in_at, r.clock_out_at).toFixed(2)
    const late = minutesLate(r.clock_in_at, r.expected_start, r.work_date)
    lines.push([
      r.work_date, JSON.stringify(s?.full_name ?? ''), JSON.stringify(s?.email ?? ''),
      JSON.stringify(r.clock_in_at ?? ''), JSON.stringify(r.clock_out_at ?? ''),
      hours, late, JSON.stringify(r.notes ?? '')
    ].join(','))
  }
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url; a.download = `attendance-${rangeStart.value}_${rangeEnd.value}.csv`; a.click()
  URL.revokeObjectURL(url)
}

/* ---------- Attendance days (holidays / closures) ---------- */
const days = ref<any[]>([])
const newDay = ref({ day: todayLocalISO(), kind: 'holiday', label: '' })
async function loadDays() {
  const { data } = await supabase.from('attendance_days').select('*').is('staff_id', null).order('day', { ascending: false })
  days.value = data ?? []
}
async function addDay() {
  if (!newDay.value.day) return
  try {
    const { error } = await supabase.from('attendance_days').insert({ day: newDay.value.day, kind: newDay.value.kind, label: newDay.value.label, staff_id: null })
    if (error) throw error
    newDay.value = { day: todayLocalISO(), kind: 'holiday', label: '' }
    await loadDays()
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
}
async function removeDay(id: string) {
  if (!(await toast.confirm({ title: 'Remove day', message: 'Remove this day?', variant: 'danger', confirmLabel: 'Remove' }))) return
  await supabase.from('attendance_days').delete().eq('id', id)
  await loadDays()
}

/* ---------- Init ---------- */
await loadStaff()
await Promise.all([loadToday(), loadTemplates(), loadRange(), loadDays()])
</script>

<template>
  <div class="max-w-6xl">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">Attendance</h1>
      <p class="text-sm text-slate-500 mt-1">Set schedules, monitor today's clock-ins, and export attendance records.</p>
    </header>

    <div class="flex flex-wrap gap-1 p-1 bg-slate-100 rounded-lg mb-6 w-fit">
      <button v-for="t in (['today','schedules','templates','records','days'] as const)" :key="t" type="button"
        @click="tab = t"
        class="px-4 py-2 rounded-md text-sm font-medium capitalize transition-colors"
        :class="tab === t ? 'bg-white text-sycamore-700 shadow-sm' : 'text-slate-600 hover:text-slate-900'">
        {{ t === 'days' ? 'Holidays' : t }}
      </button>
    </div>

    <!-- Today -->
    <section v-if="tab === 'today'" class="space-y-4">
      <div class="flex items-center justify-between">
        <div class="text-sm text-slate-600">
          <strong class="text-slate-900">{{ WEEKDAYS[todaysWeekday] }}</strong> &middot; {{ today }}
        </div>
        <input type="date" v-model="today" @change="loadToday" class="border border-slate-300 rounded-md px-3 py-1.5 text-sm" />
      </div>
      <div class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Staff</th>
              <th class="text-left px-5 py-2">Scheduled</th>
              <th class="text-left px-5 py-2">Status</th>
              <th class="text-left px-5 py-2">Clock in</th>
              <th class="text-left px-5 py-2">Clock out</th>
              <th class="text-right px-5 py-2">Hours</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in todayRows" :key="row.staff.id" class="border-t border-slate-100">
              <td class="px-5 py-3">
                <div class="font-medium text-slate-900">{{ row.staff.full_name }}</div>
                <div class="text-xs text-slate-500">{{ row.staff.email }}</div>
              </td>
              <td class="px-5 py-3 text-slate-600">
                <span v-if="row.schedule?.is_working">{{ formatTime(row.schedule.start_time) }} &ndash; {{ formatTime(row.schedule.end_time) }}</span>
                <span v-else class="text-slate-400">Off</span>
              </td>
              <td class="px-5 py-3">
                <span class="inline-block text-xs font-semibold px-2 py-0.5 rounded border" :class="statusClass(row.status)">{{ row.status }}</span>
                <span v-if="row.late > 0" class="ml-2 text-xs font-semibold text-amber-700">+{{ row.late }}m late</span>
              </td>
              <td class="px-5 py-3 tabular-nums">{{ row.record?.clock_in_at ? formatDateTime(row.record.clock_in_at) : '—' }}</td>
              <td class="px-5 py-3 tabular-nums">{{ row.record?.clock_out_at ? formatDateTime(row.record.clock_out_at) : '—' }}</td>
              <td class="px-5 py-3 text-right tabular-nums">{{ row.record?.clock_in_at && row.record?.clock_out_at ? formatDuration(durationHours(row.record.clock_in_at, row.record.clock_out_at)) : '—' }}</td>
            </tr>
            <tr v-if="todayRows.length === 0"><td colspan="6" class="px-5 py-6 text-center text-slate-500">No active staff.</td></tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Schedules -->
    <section v-if="tab === 'schedules'" class="space-y-4">
      <div class="flex flex-wrap items-center gap-3">
        <label class="flex items-center gap-3">
          <span class="text-sm text-slate-600">Staff</span>
          <select v-model="selectedStaffId" class="min-w-[240px] border border-slate-300 rounded-md px-3 py-2 text-sm">
            <option value="">Select staff...</option>
            <option v-for="s in staff" :key="s.id" :value="s.id">{{ s.full_name }}</option>
          </select>
        </label>
        <div v-if="selectedStaffId" class="text-xs px-2.5 py-1 rounded-full border"
          :class="scheduleSource === 'personal' ? 'bg-sycamore-50 text-sycamore-700 border-sycamore-200' : (scheduleSource === 'none' ? 'bg-slate-50 text-slate-500 border-slate-200' : 'bg-sky-50 text-sky-700 border-sky-200')">
          <span v-if="scheduleSource === 'personal'">Personal override</span>
          <span v-else-if="scheduleSource === 'none'">No schedule assigned</span>
          <span v-else>Inherited from {{ scheduleSource }} template<span v-if="scheduleSourceName"> &middot; {{ scheduleSourceName }}</span></span>
        </div>
        <button v-if="selectedStaffId && scheduleSource === 'personal'" type="button" @click="clearPersonalSchedule"
          class="text-xs text-rose-600 font-medium">Remove override</button>
      </div>
      <p v-if="selectedStaffId && scheduleSource !== 'personal' && scheduleSource !== 'none'" class="text-xs text-slate-500">
        Saving here creates a personal override for this staff member; otherwise they continue to follow the template.
      </p>

      <div v-if="selectedStaffId" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Day</th>
              <th class="text-left px-5 py-2">Working</th>
              <th class="text-left px-5 py-2">Start</th>
              <th class="text-left px-5 py-2">End</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="d in 7" :key="d - 1" class="border-t border-slate-100">
              <td class="px-5 py-3 font-medium text-slate-900">{{ WEEKDAYS[d - 1] }}</td>
              <td class="px-5 py-3">
                <label class="inline-flex items-center gap-2">
                  <input type="checkbox" v-model="staffSchedule[d - 1].is_working" class="rounded" />
                  <span class="text-xs text-slate-500">{{ staffSchedule[d - 1].is_working ? 'On shift' : 'Off' }}</span>
                </label>
              </td>
              <td class="px-5 py-3"><input type="time" v-model="staffSchedule[d - 1].start_time" :disabled="!staffSchedule[d - 1].is_working" class="border border-slate-300 rounded-md px-2 py-1 text-sm disabled:bg-slate-50" /></td>
              <td class="px-5 py-3"><input type="time" v-model="staffSchedule[d - 1].end_time" :disabled="!staffSchedule[d - 1].is_working" class="border border-slate-300 rounded-md px-2 py-1 text-sm disabled:bg-slate-50" /></td>
            </tr>
          </tbody>
        </table>
        <div class="px-5 py-4 border-t border-slate-100 flex justify-end">
          <button type="button" @click="saveSchedule" :disabled="savingSchedule"
            class="px-4 py-2 bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-50 text-white rounded-md text-sm font-medium">
            {{ savingSchedule ? 'Saving...' : 'Save schedule' }}
          </button>
        </div>
      </div>
    </section>

    <!-- Templates -->
    <section v-if="tab === 'templates'">
      <LazyScheduleTemplates />
    </section>

    <!-- Records -->
    <section v-if="tab === 'records'" class="space-y-4">
      <div class="flex flex-wrap items-end gap-3">
        <label class="text-sm"><span class="block text-slate-600 mb-1">From</span><input type="date" v-model="rangeStart" class="border border-slate-300 rounded-md px-3 py-1.5" /></label>
        <label class="text-sm"><span class="block text-slate-600 mb-1">To</span><input type="date" v-model="rangeEnd" class="border border-slate-300 rounded-md px-3 py-1.5" /></label>
        <label class="text-sm">
          <span class="block text-slate-600 mb-1">Staff</span>
          <select v-model="rangeStaffId" class="border border-slate-300 rounded-md px-3 py-1.5">
            <option value="">All staff</option>
            <option v-for="s in staff" :key="s.id" :value="s.id">{{ s.full_name }}</option>
          </select>
        </label>
        <button type="button" @click="loadRange" class="px-4 py-1.5 bg-slate-900 text-white rounded-md text-sm">Apply</button>
        <button type="button" @click="exportCsv" class="px-4 py-1.5 border border-slate-300 rounded-md text-sm">Export CSV</button>
      </div>
      <div class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Date</th>
              <th class="text-left px-5 py-2">Staff</th>
              <th class="text-left px-5 py-2">Clock in</th>
              <th class="text-left px-5 py-2">Clock out</th>
              <th class="text-right px-5 py-2">Hours</th>
              <th class="text-right px-5 py-2">Late</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="rangeLoading"><td colspan="6" class="px-5 py-6 text-center text-slate-500">Loading...</td></tr>
            <tr v-else-if="rangeRecords.length === 0"><td colspan="6" class="px-5 py-6 text-center text-slate-500">No records in range.</td></tr>
            <tr v-else v-for="r in rangeRecords" :key="r.id" class="border-t border-slate-100">
              <td class="px-5 py-3 tabular-nums">{{ r.work_date }}</td>
              <td class="px-5 py-3">{{ staffName(r.staff_id) }}</td>
              <td class="px-5 py-3 tabular-nums">{{ r.clock_in_at ? formatDateTime(r.clock_in_at) : '—' }}</td>
              <td class="px-5 py-3 tabular-nums">{{ r.clock_out_at ? formatDateTime(r.clock_out_at) : '—' }}</td>
              <td class="px-5 py-3 text-right tabular-nums">{{ r.clock_in_at && r.clock_out_at ? formatDuration(durationHours(r.clock_in_at, r.clock_out_at)) : '—' }}</td>
              <td class="px-5 py-3 text-right tabular-nums">{{ minutesLate(r.clock_in_at, r.expected_start, r.work_date) || '—' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Holidays -->
    <section v-if="tab === 'days'" class="space-y-4">
      <div class="bg-white border border-slate-200 rounded-xl p-5">
        <h3 class="text-sm font-semibold text-slate-900 mb-3">Add holiday or closure</h3>
        <div class="grid grid-cols-1 sm:grid-cols-4 gap-3">
          <label class="text-sm"><span class="block text-slate-600 mb-1">Date</span><input type="date" v-model="newDay.day" class="w-full border border-slate-300 rounded-md px-3 py-2" /></label>
          <label class="text-sm">
            <span class="block text-slate-600 mb-1">Kind</span>
            <select v-model="newDay.kind" class="w-full border border-slate-300 rounded-md px-3 py-2">
              <option value="holiday">Public holiday</option>
              <option value="closed">Office closed</option>
              <option value="custom">Custom</option>
            </select>
          </label>
          <label class="text-sm sm:col-span-2"><span class="block text-slate-600 mb-1">Label</span><input type="text" v-model="newDay.label" placeholder="e.g. Workers' Day" class="w-full border border-slate-300 rounded-md px-3 py-2" /></label>
        </div>
        <div class="mt-4 flex justify-end">
          <button type="button" @click="addDay" class="px-4 py-2 bg-sycamore-600 hover:bg-sycamore-700 text-white rounded-md text-sm font-medium">Add</button>
        </div>
      </div>

      <div class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Date</th>
              <th class="text-left px-5 py-2">Kind</th>
              <th class="text-left px-5 py-2">Label</th>
              <th class="text-right px-5 py-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="days.length === 0"><td colspan="4" class="px-5 py-6 text-center text-slate-500">No holidays set.</td></tr>
            <tr v-for="d in days" :key="d.id" class="border-t border-slate-100">
              <td class="px-5 py-3 tabular-nums">{{ d.day }}</td>
              <td class="px-5 py-3 capitalize">{{ d.kind }}</td>
              <td class="px-5 py-3">{{ d.label }}</td>
              <td class="px-5 py-3 text-right"><button type="button" @click="removeDay(d.id)" class="text-rose-600 text-sm font-medium">Remove</button></td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
