<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import {
  WEEKDAYS, WEEKDAYS_SHORT, todayLocalISO, formatTime, formatDateTime,
  durationHours, formatDuration, minutesLate, statusFor
} from '~/composables/useAttendance'

definePageMeta({ middleware: ['auth'] })

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
const dayOverride = ref<any | null>(null)
const loading = ref(true)
const pending = ref(false)
const now = ref(new Date())

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
    const smAny: any = sm

    const [{ data: sched }, { data: rec }, { data: week }, { data: override }, { data: memberTpls }, { data: defaultTpls }] = await Promise.all([
      supabase.from('staff_schedules').select('*').eq('staff_id', smAny.id),
      supabase.from('attendance_records').select('*').eq('staff_id', smAny.id).eq('work_date', today.value).maybeSingle(),
      supabase.from('attendance_records').select('*').eq('staff_id', smAny.id).gte('work_date', weekAgo).lte('work_date', today.value).order('work_date', { ascending: false }),
      supabase.from('attendance_days').select('*').eq('day', today.value).or(`staff_id.is.null,staff_id.eq.${smAny.id}`).maybeSingle(),
      supabase.from('schedule_template_members').select('template:schedule_templates(id, name, scope, department_id, location_id, updated_at, schedule_template_days(weekday, is_working, start_time, end_time))').eq('staff_id', smAny.id),
      supabase.from('schedule_templates').select('id, name, scope, department_id, location_id, is_default, schedule_template_days(weekday, is_working, start_time, end_time)').eq('is_default', true)
    ])

    todayRecord.value = rec ?? null
    weekRecords.value = week ?? []
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

const weekDaysData = computed(() => {
  const out: any[] = []
  for (let i = 6; i >= 0; i--) {
    const d = new Date()
    d.setDate(d.getDate() - i)
    const iso = todayLocalISO(d)
    const rec = weekRecords.value.find(r => r.work_date === iso)
    const wd = d.getDay()
    const sch = schedule.value.find(s => s.weekday === wd)
    out.push({ iso, weekday: wd, label: WEEKDAYS_SHORT[wd], day: d.getDate(), schedule: sch, record: rec })
  }
  return out
})

const nowString = computed(() => now.value.toLocaleTimeString('en-NG', { hour: '2-digit', minute: '2-digit', second: '2-digit' }))
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
            <div class="text-4xl sm:text-5xl font-semibold text-slate-900 tabular-nums">{{ nowString }}</div>

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
                class="w-full px-6 py-5 bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-50 text-white rounded-xl text-lg font-semibold shadow-sm transition-colors"
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
                <div class="text-2xl font-semibold text-slate-900 tabular-nums">{{ formatDateTime(todayRecord.clock_in_at) }}</div>
                <div class="mt-1 text-sm text-slate-600">Elapsed <span class="font-semibold text-slate-900">{{ formatDuration(elapsed) }}</span></div>
                <div v-if="lateMinutes > 0" class="mt-1 text-xs font-semibold text-amber-700">{{ lateMinutes }} min late</div>
              </div>
              <button
                type="button"
                :disabled="pending"
                @click="clockOut"
                class="w-full px-6 py-5 bg-slate-900 hover:bg-slate-800 disabled:opacity-50 text-white rounded-xl text-lg font-semibold shadow-sm transition-colors"
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

      <section>
        <h2 class="text-sm font-semibold text-slate-900 mb-3">This week</h2>
        <div class="grid grid-cols-7 gap-2">
          <div v-for="d in weekDaysData" :key="d.iso"
            class="bg-white border rounded-xl p-3 text-center"
            :class="d.iso === today ? 'border-sycamore-300 ring-1 ring-sycamore-200' : 'border-slate-200'">
            <div class="text-[10px] uppercase tracking-wide text-slate-400">{{ d.label }}</div>
            <div class="text-lg font-semibold text-slate-900">{{ d.day }}</div>
            <div v-if="d.record?.clock_in_at" class="mt-1 text-[11px] text-emerald-700">
              <div class="tabular-nums">{{ formatDateTime(d.record.clock_in_at) }}</div>
              <div v-if="d.record.clock_out_at" class="tabular-nums text-slate-500">{{ formatDateTime(d.record.clock_out_at) }}</div>
            </div>
            <div v-else-if="d.schedule?.is_working" class="mt-1 text-[11px] text-slate-400">
              {{ formatTime(d.schedule.start_time) }}
            </div>
            <div v-else class="mt-1 text-[11px] text-slate-300">Off</div>
          </div>
        </div>
      </section>
    </template>
  </div>
</template>
