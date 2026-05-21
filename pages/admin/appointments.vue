<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'
import {
  useAppointments,
  APPOINTMENT_STATUS_LABELS,
  APPOINTMENT_STATUS_BADGE,
  type Appointment,
  type AppointmentStatus
} from '~/composables/useAppointments'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()
const { canPerform } = useAuth()
const {
  loadAppointments,
  updateAppointment,
  changeStatus,
  deleteAppointment,
  loadFrontDesk,
  addFrontDesk,
  removeFrontDesk
} = useAppointments()

const tab = ref<'schedule' | 'front_desk'>('schedule')
const loading = ref(true)
const appointments = ref<Appointment[]>([])
const locations = ref<{ id: string; name: string }[]>([])
const staff = ref<{ id: string; full_name: string; email: string; role: string }[]>([])

const filterStatus = ref<AppointmentStatus | 'all'>('all')
const filterLocation = ref('')
const filterFrom = ref('')
const filterTo = ref('')

const frontDesk = ref<any[]>([])
const addStaffId = ref('')
const addLocationId = ref('')

async function loadAll() {
  loading.value = true
  try {
    const [locRes, staffRes, appts, fd] = await Promise.all([
      supabase.from('locations').select('id, name').order('name'),
      supabase.from('staff_members').select('id, full_name, email, role').eq('is_active', true).order('full_name'),
      loadAppointments({
        locationIds: filterLocation.value ? [filterLocation.value] : undefined,
        fromDate: filterFrom.value || undefined,
        toDate: filterTo.value || undefined,
        status: filterStatus.value
      }),
      loadFrontDesk()
    ])
    locations.value = (locRes.data ?? []) as any
    staff.value = (staffRes.data ?? []) as any
    appointments.value = appts
    frontDesk.value = fd
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not load data')
  } finally {
    loading.value = false
  }
}
loadAll()

watch([filterStatus, filterLocation, filterFrom, filterTo], () => loadAll())

async function act(a: Appointment, to: AppointmentStatus) {
  if (!canPerform('appointments', 'update')) { toast.error('No permission'); return }
  try {
    const patch: Partial<Appointment> = {}
    if (to === 'checked_in') patch.checked_in_at = new Date().toISOString()
    if (to === 'checked_out') patch.checked_out_at = new Date().toISOString()
    await changeStatus(a.id, a.status, to, patch)
    auditLog({ action: `appointment_${to}`, target_type: 'appointment', target_id: a.id, target_label: a.guest_name })
    toast.success('Updated')
    await loadAll()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not update')
  }
}

async function removeAppt(a: Appointment) {
  if (!canPerform('appointments', 'delete')) { toast.error('No permission'); return }
  const ok = await toast.confirm({
    title: 'Delete appointment?',
    message: `Delete ${a.guest_name}'s visit? This cannot be undone.`,
    confirmLabel: 'Delete',
    variant: 'danger'
  })
  if (!ok) return
  await deleteAppointment(a.id)
  auditLog({ action: 'delete', target_type: 'appointment', target_id: a.id, target_label: a.guest_name })
  toast.success('Deleted')
  await loadAll()
}

async function saveNote(a: Appointment, note: string) {
  try {
    await updateAppointment(a.id, { notes: note }, 'Admin updated notes')
    auditLog({ action: 'update_notes', target_type: 'appointment', target_id: a.id, target_label: a.guest_name })
    toast.success('Saved')
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save')
  }
}

async function addFd() {
  if (!addStaffId.value) { toast.error('Pick a staff member'); return }
  if (!canPerform('appointments', 'create')) { toast.error('No permission'); return }
  try {
    await addFrontDesk(addStaffId.value, addLocationId.value || null)
    auditLog({ action: 'add_front_desk', target_type: 'front_desk', target_label: staff.value.find(s => s.id === addStaffId.value)?.full_name ?? addStaffId.value })
    toast.success('Front desk added')
    addStaffId.value = ''
    addLocationId.value = ''
    frontDesk.value = await loadFrontDesk()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not add')
  }
}

async function removeFd(row: any) {
  if (!canPerform('appointments', 'delete')) { toast.error('No permission'); return }
  const ok = await toast.confirm({
    title: 'Remove front desk access?',
    message: `Remove ${row.staff?.full_name} from the front desk allowlist?`,
    confirmLabel: 'Remove',
    variant: 'danger'
  })
  if (!ok) return
  await removeFrontDesk(row.id)
  auditLog({ action: 'remove_front_desk', target_type: 'front_desk', target_id: row.id, target_label: row.staff?.full_name ?? '' })
  toast.success('Removed')
  frontDesk.value = await loadFrontDesk()
}

function formatTime(t: string | null | undefined) {
  return t ? t.slice(0, 5) : ''
}
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="section-title">Appointments</h1>
      <p class="section-subtitle">All visitor bookings across locations.</p>
    </header>

    <div class="flex items-center gap-1 rounded-lg bg-white border border-slate-200 p-1 w-fit">
      <button
        class="px-3 py-1.5 rounded-md text-sm font-medium transition-colors"
        :class="tab === 'schedule' ? 'bg-sycamore-600 text-white' : 'text-slate-600'"
        @click="tab = 'schedule'"
      >Schedule</button>
      <button
        class="px-3 py-1.5 rounded-md text-sm font-medium transition-colors"
        :class="tab === 'front_desk' ? 'bg-sycamore-600 text-white' : 'text-slate-600'"
        @click="tab = 'front_desk'"
      >Front desk access</button>
    </div>

    <section v-if="tab === 'schedule'" class="card p-5">
      <div class="flex flex-wrap items-center gap-2 mb-4">
        <select v-model="filterStatus" class="input !w-auto !py-1.5 text-xs">
          <option value="all">All statuses</option>
          <option v-for="(label, key) in APPOINTMENT_STATUS_LABELS" :key="key" :value="key">{{ label }}</option>
        </select>
        <select v-model="filterLocation" class="input !w-auto !py-1.5 text-xs">
          <option value="">All locations</option>
          <option v-for="l in locations" :key="l.id" :value="l.id">{{ l.name }}</option>
        </select>
        <input v-model="filterFrom" type="date" class="input !w-auto !py-1.5 text-xs" />
        <input v-model="filterTo" type="date" class="input !w-auto !py-1.5 text-xs" />
      </div>

      <div v-if="loading" class="py-12 text-center text-sm text-slate-500">Loading...</div>
      <div v-else-if="!appointments.length" class="py-12 text-center text-sm text-slate-500">No appointments match these filters.</div>
      <div v-else class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="text-xs text-slate-500 uppercase tracking-wide">
            <tr class="border-b border-slate-200">
              <th class="text-left py-2 pr-3">Guest</th>
              <th class="text-left py-2 pr-3">When</th>
              <th class="text-left py-2 pr-3">Location</th>
              <th class="text-left py-2 pr-3">Host</th>
              <th class="text-left py-2 pr-3">Status</th>
              <th class="text-left py-2 pr-3">Now at</th>
              <th class="text-right py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="a in appointments" :key="a.id" class="align-top">
              <td class="py-3 pr-3">
                <div class="font-medium text-slate-900">{{ a.guest_name }}</div>
                <div v-if="a.guest_company" class="text-xs text-slate-500">{{ a.guest_company }}</div>
                <div v-if="a.guest_count > 1" class="text-xs text-slate-400">{{ a.guest_count }} people</div>
              </td>
              <td class="py-3 pr-3 text-slate-700 whitespace-nowrap">
                <div>{{ a.scheduled_date }}</div>
                <div class="text-xs text-slate-500">{{ formatTime(a.scheduled_start) }}<template v-if="a.scheduled_end"> – {{ formatTime(a.scheduled_end) }}</template></div>
              </td>
              <td class="py-3 pr-3 text-slate-700">{{ a.location?.name || '—' }}</td>
              <td class="py-3 pr-3 text-slate-700">{{ a.host?.full_name || '—' }}</td>
              <td class="py-3 pr-3"><span class="badge" :class="APPOINTMENT_STATUS_BADGE[a.status]">{{ APPOINTMENT_STATUS_LABELS[a.status] }}</span></td>
              <td class="py-3 pr-3 text-slate-600">{{ a.current_location_note || '—' }}</td>
              <td class="py-3 text-right whitespace-nowrap">
                <div class="inline-flex gap-1">
                  <button v-if="a.status === 'scheduled'" class="btn-secondary !py-1 !px-2 text-xs" @click="act(a, 'checked_in')">Check in</button>
                  <button v-if="a.status === 'checked_in'" class="btn-secondary !py-1 !px-2 text-xs" @click="act(a, 'in_meeting')">In meeting</button>
                  <button v-if="a.status === 'checked_in' || a.status === 'in_meeting'" class="btn-secondary !py-1 !px-2 text-xs" @click="act(a, 'checked_out')">Check out</button>
                  <button v-if="canPerform('appointments', 'delete')" class="!py-1 !px-2 text-xs inline-flex items-center rounded-lg border border-rose-200 bg-white text-rose-700 font-medium hover:bg-rose-50 transition-colors" @click="removeAppt(a)">Delete</button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <section v-else class="card p-5">
      <h2 class="text-base font-semibold text-slate-900 mb-2">Front desk allowlist</h2>
      <p class="text-sm text-slate-500 mb-4">Staff on this list can see and manage every appointment at their assigned location. Leave the location blank to grant access to all offices.</p>

      <div class="flex flex-wrap gap-2 mb-5">
        <select v-model="addStaffId" class="input !w-auto !py-1.5 text-xs">
          <option value="">Select staff...</option>
          <option v-for="s in staff" :key="s.id" :value="s.id">{{ s.full_name }} — {{ s.role || s.email }}</option>
        </select>
        <select v-model="addLocationId" class="input !w-auto !py-1.5 text-xs">
          <option value="">All locations</option>
          <option v-for="l in locations" :key="l.id" :value="l.id">{{ l.name }}</option>
        </select>
        <button class="btn-primary" @click="addFd">Add to front desk</button>
      </div>

      <ul class="divide-y divide-slate-100">
        <li v-for="row in frontDesk" :key="row.id" class="py-3 flex items-center justify-between gap-3">
          <div>
            <div class="font-medium text-slate-900">{{ row.staff?.full_name || 'Unknown staff' }}</div>
            <div class="text-xs text-slate-500">
              {{ row.staff?.role || row.staff?.email || '' }}
              · {{ row.location?.name || 'All locations' }}
            </div>
          </div>
          <button class="!py-1.5 !px-3 text-xs inline-flex items-center gap-1 rounded-lg border border-rose-200 bg-white text-rose-700 font-medium hover:bg-rose-50 transition-colors" @click="removeFd(row)">Remove</button>
        </li>
        <li v-if="!frontDesk.length" class="py-6 text-center text-sm text-slate-500">No front desk users yet.</li>
      </ul>
    </section>
  </div>
</template>
