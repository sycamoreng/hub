<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import {
  useAppointments,
  APPOINTMENT_STATUS_LABELS,
  APPOINTMENT_STATUS_BADGE,
  type Appointment,
  type AppointmentStatus
} from '~/composables/useAppointments'

definePageMeta({ middleware: ['auth'] })

const supabase = useSupabase()
const toast = useToast()
const { user, isAdmin, canPerform } = useAuth()
const {
  loadAppointments,
  createAppointment,
  updateAppointment,
  changeStatus,
  updateCurrentLocation,
  deleteAppointment,
  loadEvents,
  loadMyFrontDeskLocations
} = useAppointments()

const staffId = ref<string | null>(null)
const locations = ref<{ id: string; name: string; city: string | null }[]>([])
const appointments = ref<Appointment[]>([])
const loading = ref(true)

const isFrontDesk = ref(false)
const frontDeskScope = ref<{ all: boolean; locationIds: string[] }>({ all: false, locationIds: [] })

const canSeeTeamView = computed(() => isFrontDesk.value || isAdmin.value)

const tab = ref<'mine' | 'team'>('mine')
const filterStatus = ref<AppointmentStatus | 'all'>('all')
const filterLocation = ref<string>('')
const filterFrom = ref<string>(new Date().toISOString().slice(0, 10))
const filterTo = ref<string>('')

const today = new Date()
function ymd(d: Date) { return d.toISOString().slice(0, 10) }

const form = ref({
  guest_name: '',
  guest_company: '',
  guest_email: '',
  guest_phone: '',
  guest_count: 1,
  purpose: '',
  location_id: '',
  scheduled_date: ymd(today),
  scheduled_start: '09:00',
  scheduled_end: '',
  notes: ''
})
const creating = ref(false)
const editing = ref<Appointment | null>(null)

const detail = ref<Appointment | null>(null)
const detailEvents = ref<any[]>([])
const locationDraft = ref<string>('')

async function resolveMe() {
  if (!user.value) return
  const { data } = await supabase
    .from('staff_members')
    .select('id')
    .eq('auth_user_id', user.value.id)
    .maybeSingle()
  staffId.value = (data as any)?.id ?? null
  const scope = await loadMyFrontDeskLocations(user.value.id)
  frontDeskScope.value = scope
  isFrontDesk.value = scope.all || scope.locationIds.length > 0
  if (!canSeeTeamView.value) tab.value = 'mine'
}

async function loadLocations() {
  const { data } = await supabase
    .from('locations')
    .select('id, name, city')
    .order('name')
  locations.value = (data ?? []) as any
  if (!form.value.location_id && locations.value.length) {
    form.value.location_id = locations.value[0].id
  }
}

async function reload() {
  loading.value = true
  try {
    if (tab.value === 'mine') {
      appointments.value = await loadAppointments({
        onlyMine: true,
        myUserId: user.value?.id,
        fromDate: filterFrom.value || undefined,
        toDate: filterTo.value || undefined,
        status: filterStatus.value
      })
    } else {
      const locIds = filterLocation.value
        ? [filterLocation.value]
        : (frontDeskScope.value.all || isAdmin.value ? undefined : frontDeskScope.value.locationIds)
      appointments.value = await loadAppointments({
        locationIds: locIds,
        fromDate: filterFrom.value || undefined,
        toDate: filterTo.value || undefined,
        status: filterStatus.value
      })
    }
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not load appointments')
    appointments.value = []
  } finally {
    loading.value = false
  }
}

async function init() {
  await Promise.all([resolveMe(), loadLocations()])
  await reload()
}
init()

watch([tab, filterStatus, filterLocation, filterFrom, filterTo], () => reload())

function resetForm() {
  form.value = {
    guest_name: '',
    guest_company: '',
    guest_email: '',
    guest_phone: '',
    guest_count: 1,
    purpose: '',
    location_id: locations.value[0]?.id ?? '',
    scheduled_date: ymd(new Date()),
    scheduled_start: '09:00',
    scheduled_end: '',
    notes: ''
  }
  editing.value = null
}

function startEdit(a: Appointment) {
  editing.value = a
  form.value = {
    guest_name: a.guest_name,
    guest_company: a.guest_company,
    guest_email: a.guest_email,
    guest_phone: a.guest_phone,
    guest_count: a.guest_count,
    purpose: a.purpose,
    location_id: a.location_id ?? '',
    scheduled_date: a.scheduled_date,
    scheduled_start: a.scheduled_start,
    scheduled_end: a.scheduled_end ?? '',
    notes: a.notes
  }
  if (typeof window !== 'undefined') window.scrollTo({ top: 0, behavior: 'smooth' })
}

async function submit() {
  if (!user.value) return
  if (!form.value.guest_name.trim()) { toast.error('Guest name is required'); return }
  if (!form.value.location_id) { toast.error('Pick a location'); return }
  if (!form.value.scheduled_date) { toast.error('Pick a date'); return }
  creating.value = true
  try {
    const payload: any = {
      guest_name: form.value.guest_name.trim(),
      guest_company: form.value.guest_company.trim(),
      guest_email: form.value.guest_email.trim(),
      guest_phone: form.value.guest_phone.trim(),
      guest_count: Math.max(1, Number(form.value.guest_count) || 1),
      purpose: form.value.purpose.trim(),
      location_id: form.value.location_id,
      scheduled_date: form.value.scheduled_date,
      scheduled_start: form.value.scheduled_start || '09:00',
      scheduled_end: form.value.scheduled_end || null,
      notes: form.value.notes.trim()
    }
    if (editing.value) {
      await updateAppointment(editing.value.id, payload)
      toast.success('Appointment updated')
    } else {
      payload.created_by_user_id = user.value.id
      payload.created_by_staff_id = staffId.value
      payload.status = 'scheduled'
      await createAppointment(payload)
      toast.success('Appointment booked')
    }
    resetForm()
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save')
  } finally {
    creating.value = false
  }
}

async function act(a: Appointment, to: AppointmentStatus) {
  try {
    const patch: Partial<Appointment> = {}
    if (to === 'checked_in') patch.checked_in_at = new Date().toISOString()
    if (to === 'checked_out') patch.checked_out_at = new Date().toISOString()
    await changeStatus(a.id, a.status, to, patch)
    toast.success(`Marked as ${APPOINTMENT_STATUS_LABELS[to].toLowerCase()}`)
    await reload()
    if (detail.value?.id === a.id) await openDetail(a.id)
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not update')
  }
}

async function removeAppt(a: Appointment) {
  const ok = await toast.confirm({
    title: 'Delete appointment?',
    message: `Remove ${a.guest_name}'s visit on ${a.scheduled_date}? This cannot be undone.`,
    confirmLabel: 'Delete',
    variant: 'danger'
  })
  if (!ok) return
  try {
    await deleteAppointment(a.id)
    toast.success('Appointment deleted')
    if (detail.value?.id === a.id) detail.value = null
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not delete')
  }
}

async function openDetail(id: string) {
  const a = appointments.value.find(x => x.id === id) ?? null
  detail.value = a
  locationDraft.value = a?.current_location_note ?? ''
  if (a) detailEvents.value = await loadEvents(a.id)
}

async function saveLocation() {
  if (!detail.value) return
  const prev = detail.value.current_location_note
  if (locationDraft.value.trim() === prev) return
  try {
    await updateCurrentLocation(detail.value.id, prev, locationDraft.value.trim())
    toast.success('Guest location updated')
    await reload()
    await openDetail(detail.value.id)
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save')
  }
}

function canManage(a: Appointment): boolean {
  if (isAdmin.value) return true
  if (a.created_by_user_id === user.value?.id) return true
  if (!a.location_id) return false
  return frontDeskScope.value.all || frontDeskScope.value.locationIds.includes(a.location_id)
}

function canDelete(a: Appointment): boolean {
  if (isAdmin.value && canPerform('appointments', 'delete')) return true
  return a.created_by_user_id === user.value?.id
}

function formatTime(t: string | null | undefined) {
  if (!t) return ''
  return t.slice(0, 5)
}

function formatDateTime(iso: string | null | undefined) {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toLocaleString()
}

const visible = computed(() => appointments.value)
const today0 = new Date().toISOString().slice(0, 10)
const upcomingCount = computed(() => visible.value.filter(a => a.scheduled_date >= today0 && a.status === 'scheduled').length)
const onSiteCount = computed(() => visible.value.filter(a => a.status === 'checked_in' || a.status === 'in_meeting').length)
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 sm:px-6 py-8">
    <header class="mb-6 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 class="section-title">Appointments</h1>
        <p class="section-subtitle">Let the front desk know when you're expecting a guest.</p>
      </div>
      <div class="flex items-center gap-2">
        <span v-if="isFrontDesk" class="badge badge-blue">Front desk</span>
        <span v-if="isAdmin" class="badge badge-green">Admin</span>
      </div>
    </header>

    <section class="card p-5 mb-6">
      <h2 class="text-base font-semibold text-slate-900 mb-4">
        {{ editing ? 'Edit appointment' : 'Book a visitor' }}
      </h2>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Guest name *</span>
          <input v-model="form.guest_name" type="text" class="input mt-1" placeholder="e.g. Jane Doe" />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Company</span>
          <input v-model="form.guest_company" type="text" class="input mt-1" placeholder="Organization" />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Email</span>
          <input v-model="form.guest_email" type="email" class="input mt-1" placeholder="jane@example.com" />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Phone</span>
          <input v-model="form.guest_phone" type="tel" class="input mt-1" placeholder="+234 ..." />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Number of visitors</span>
          <input v-model.number="form.guest_count" type="number" min="1" class="input mt-1" />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Office / location *</span>
          <select v-model="form.location_id" class="input mt-1">
            <option value="">Select a location</option>
            <option v-for="l in locations" :key="l.id" :value="l.id">
              {{ l.name }}<template v-if="l.city"> — {{ l.city }}</template>
            </option>
          </select>
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600">Date *</span>
          <input v-model="form.scheduled_date" type="date" class="input mt-1" />
        </label>
        <div class="grid grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Start</span>
            <input v-model="form.scheduled_start" type="time" class="input mt-1" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600">End</span>
            <input v-model="form.scheduled_end" type="time" class="input mt-1" />
          </label>
        </div>
        <label class="block md:col-span-2">
          <span class="text-xs font-medium text-slate-600">Purpose of visit</span>
          <input v-model="form.purpose" type="text" class="input mt-1" placeholder="Interview, meeting, delivery ..." />
        </label>
        <label class="block md:col-span-2">
          <span class="text-xs font-medium text-slate-600">Notes for front desk</span>
          <textarea v-model="form.notes" rows="2" class="input mt-1" placeholder="Anything the front desk should know"></textarea>
        </label>
      </div>
      <div class="flex justify-end gap-2 mt-4">
        <button v-if="editing" class="btn-secondary" @click="resetForm">Cancel</button>
        <button class="btn-primary" :disabled="creating" @click="submit">
          {{ editing ? 'Save changes' : 'Book visit' }}
        </button>
      </div>
    </section>

    <section class="card p-5">
      <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
        <div class="flex items-center gap-1 rounded-lg bg-slate-100 p-1">
          <button
            class="px-3 py-1.5 rounded-md text-sm font-medium transition-colors"
            :class="tab === 'mine' ? 'bg-white text-sycamore-700 shadow-sm' : 'text-slate-600'"
            @click="tab = 'mine'"
          >My bookings</button>
          <button
            v-if="canSeeTeamView"
            class="px-3 py-1.5 rounded-md text-sm font-medium transition-colors"
            :class="tab === 'team' ? 'bg-white text-sycamore-700 shadow-sm' : 'text-slate-600'"
            @click="tab = 'team'"
          >
            Schedule
            <span v-if="onSiteCount" class="ml-1 inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-blue-100 text-blue-700">{{ onSiteCount }} on site</span>
          </button>
        </div>
        <div class="flex flex-wrap gap-2">
          <select v-model="filterStatus" class="input !w-auto !py-1.5 text-xs">
            <option value="all">All statuses</option>
            <option v-for="(label, key) in APPOINTMENT_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
          </select>
          <select v-if="tab === 'team'" v-model="filterLocation" class="input !w-auto !py-1.5 text-xs">
            <option value="">All locations</option>
            <option v-for="l in locations" :key="l.id" :value="l.id">{{ l.name }}</option>
          </select>
          <input v-model="filterFrom" type="date" class="input !w-auto !py-1.5 text-xs" />
          <input v-model="filterTo" type="date" class="input !w-auto !py-1.5 text-xs" />
        </div>
      </div>

      <div v-if="loading" class="py-12 text-center text-sm text-slate-500">Loading...</div>
      <div v-else-if="!visible.length" class="py-12 text-center">
        <p class="text-sm text-slate-500">No appointments match these filters.</p>
        <p v-if="tab === 'mine'" class="text-xs text-slate-400 mt-1">Use the form above to book your first visitor.</p>
      </div>
      <ul v-else class="divide-y divide-slate-100">
        <li v-for="a in visible" :key="a.id" class="py-3 flex flex-wrap items-start gap-3">
          <div class="flex-1 min-w-[240px]">
            <div class="flex items-center gap-2 flex-wrap">
              <span class="font-medium text-slate-900">{{ a.guest_name || 'Unnamed guest' }}</span>
              <span v-if="a.guest_company" class="text-xs text-slate-500">· {{ a.guest_company }}</span>
              <span class="badge" :class="APPOINTMENT_STATUS_BADGE[a.status]">{{ APPOINTMENT_STATUS_LABELS[a.status] }}</span>
              <span v-if="a.guest_count > 1" class="badge badge-slate">{{ a.guest_count }} people</span>
            </div>
            <div class="mt-1 text-xs text-slate-600 flex flex-wrap gap-x-4 gap-y-1">
              <span>{{ a.scheduled_date }} · {{ formatTime(a.scheduled_start) }}<template v-if="a.scheduled_end"> – {{ formatTime(a.scheduled_end) }}</template></span>
              <span v-if="a.location">{{ a.location.name }}<template v-if="a.location.city"> · {{ a.location.city }}</template></span>
              <span v-if="a.host && tab === 'team'">Host: {{ a.host.full_name }}</span>
              <span v-if="a.current_location_note" class="text-sycamore-700">Now at: {{ a.current_location_note }}</span>
              <span v-if="a.purpose">{{ a.purpose }}</span>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <button class="btn-secondary !py-1.5 !px-3 text-xs" @click="openDetail(a.id)">Details</button>
            <template v-if="canManage(a)">
              <button
                v-if="a.status === 'scheduled'"
                class="btn-primary !py-1.5 !px-3 text-xs"
                @click="act(a, 'checked_in')"
              >Check in</button>
              <button
                v-if="a.status === 'checked_in'"
                class="btn-primary !py-1.5 !px-3 text-xs"
                @click="act(a, 'in_meeting')"
              >In meeting</button>
              <button
                v-if="a.status === 'checked_in' || a.status === 'in_meeting'"
                class="btn-secondary !py-1.5 !px-3 text-xs"
                @click="act(a, 'checked_out')"
              >Check out</button>
              <button
                v-if="a.status === 'scheduled'"
                class="btn-secondary !py-1.5 !px-3 text-xs"
                @click="act(a, 'no_show')"
              >No show</button>
              <button
                v-if="a.created_by_user_id === user?.id && a.status === 'scheduled'"
                class="btn-secondary !py-1.5 !px-3 text-xs"
                @click="startEdit(a)"
              >Edit</button>
              <button
                v-if="canDelete(a)"
                class="!py-1.5 !px-3 text-xs inline-flex items-center gap-1 rounded-lg border border-rose-200 bg-white text-rose-700 font-medium hover:bg-rose-50 transition-colors"
                @click="removeAppt(a)"
              >Delete</button>
            </template>
          </div>
        </li>
      </ul>
    </section>

    <!-- Detail panel -->
    <div
      v-if="detail"
      class="fixed inset-0 z-40 bg-slate-900/40 backdrop-blur-sm flex items-start sm:items-center justify-center p-4"
      @click.self="detail = null"
    >
      <div class="card w-full max-w-2xl p-6 max-h-[90vh] overflow-y-auto">
        <div class="flex items-start justify-between gap-4 mb-4">
          <div>
            <h3 class="text-lg font-semibold text-slate-900">{{ detail.guest_name }}</h3>
            <p class="text-sm text-slate-500">
              {{ detail.scheduled_date }} · {{ formatTime(detail.scheduled_start) }}<template v-if="detail.scheduled_end"> – {{ formatTime(detail.scheduled_end) }}</template>
              <template v-if="detail.location"> · {{ detail.location.name }}</template>
            </p>
          </div>
          <button class="text-slate-400 hover:text-slate-700" @click="detail = null">✕</button>
        </div>

        <dl class="grid grid-cols-2 gap-3 text-sm mb-5">
          <div><dt class="text-xs text-slate-500">Status</dt><dd><span class="badge" :class="APPOINTMENT_STATUS_BADGE[detail.status]">{{ APPOINTMENT_STATUS_LABELS[detail.status] }}</span></dd></div>
          <div><dt class="text-xs text-slate-500">Company</dt><dd>{{ detail.guest_company || '—' }}</dd></div>
          <div><dt class="text-xs text-slate-500">Email</dt><dd>{{ detail.guest_email || '—' }}</dd></div>
          <div><dt class="text-xs text-slate-500">Phone</dt><dd>{{ detail.guest_phone || '—' }}</dd></div>
          <div><dt class="text-xs text-slate-500">Purpose</dt><dd>{{ detail.purpose || '—' }}</dd></div>
          <div><dt class="text-xs text-slate-500">Host</dt><dd>{{ detail.host?.full_name || '—' }}</dd></div>
          <div><dt class="text-xs text-slate-500">Checked in</dt><dd>{{ formatDateTime(detail.checked_in_at) || '—' }}</dd></div>
          <div><dt class="text-xs text-slate-500">Checked out</dt><dd>{{ formatDateTime(detail.checked_out_at) || '—' }}</dd></div>
          <div class="col-span-2"><dt class="text-xs text-slate-500">Notes</dt><dd class="whitespace-pre-wrap">{{ detail.notes || '—' }}</dd></div>
        </dl>

        <div v-if="canManage(detail)" class="mb-5">
          <label class="block">
            <span class="text-xs font-medium text-slate-600">Where is the guest now?</span>
            <div class="flex gap-2 mt-1">
              <input v-model="locationDraft" type="text" class="input" placeholder="e.g. Reception, Boardroom 2" />
              <button class="btn-primary" @click="saveLocation">Save</button>
            </div>
          </label>
        </div>

        <div>
          <h4 class="text-sm font-semibold text-slate-900 mb-2">Activity</h4>
          <ul v-if="detailEvents.length" class="space-y-2 text-xs text-slate-600">
            <li v-for="ev in detailEvents" :key="ev.id" class="flex gap-2">
              <span class="text-slate-400">{{ formatDateTime(ev.created_at) }}</span>
              <span>
                <strong class="text-slate-800">{{ ev.actor?.full_name || 'Someone' }}</strong>
                <template v-if="ev.event_type === 'status_changed'"> changed status from {{ ev.from_value }} to {{ ev.to_value }}</template>
                <template v-else-if="ev.event_type === 'location_updated'"> moved guest to "{{ ev.to_value }}"</template>
                <template v-else-if="ev.event_type === 'created'"> created the appointment</template>
                <template v-else-if="ev.event_type === 'edited'"> {{ ev.note || 'edited the appointment' }}</template>
                <template v-else-if="ev.event_type === 'deleted'"> deleted the appointment</template>
              </span>
            </li>
          </ul>
          <p v-else class="text-xs text-slate-400">No activity yet.</p>
        </div>
      </div>
    </div>
  </div>
</template>
