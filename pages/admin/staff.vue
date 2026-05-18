<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('staff_members')
const toast = useToast()
const departments = ref<any[]>([])
const locations = ref<any[]>([])
const teams = ref<any[]>([])
const managerCandidates = ref<any[]>([])

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = computed(() => [
  { key: 'full_name', label: 'Full name', required: true },
  { key: 'email', label: 'Email', type: 'email', required: true },
  { key: 'phone', label: 'Phone', type: 'tel' },
  { key: 'role', label: 'Role / title', required: true, placeholder: 'e.g. Senior Software Engineer' },
  {
    key: 'department_id', label: 'Department', type: 'select',
    options: [{ value: '', label: 'None' }, ...departments.value.map(d => ({ value: d.id, label: d.name }))]
  },
  {
    key: 'location_id', label: 'Location', type: 'select',
    options: [{ value: '', label: 'None' }, ...locations.value.map(l => ({ value: l.id, label: `${l.name} (${l.city})` }))]
  },
  {
    key: 'team_id', label: 'Team', type: 'select',
    options: [{ value: '', label: 'None' }, ...teams.value
      .filter(t => !editing.value?.department_id || t.department_id === editing.value.department_id)
      .map(t => ({ value: t.id, label: t.name }))]
  },
  {
    key: 'manager_id', label: 'Reports to', type: 'select',
    options: [{ value: '', label: 'None' }, ...managerCandidates.value
      .filter(m => m.id !== editing.value?.id)
      .map(m => ({ value: m.id, label: `${m.full_name}${m.role ? ' — ' + m.role : ''}` }))]
  },
  { key: 'joined_date', label: 'Joined date', type: 'date' },
  { key: 'bio', label: 'Bio', type: 'textarea' },
  { key: 'is_active', label: 'Active', type: 'checkbox', placeholder: 'Currently employed' },
  { key: 'directory_visible', label: 'Show in directory', type: 'checkbox', placeholder: 'Visible to staff in the directory and organogram' },
  { key: 'exited_at', label: 'Exit date', type: 'date', placeholder: 'Set when this person has left the company' }
])

const columns = [
  { key: 'full_name', label: 'Name' },
  { key: 'role', label: 'Role' },
  { key: 'email', label: 'Email' },
  { key: 'auth_user_id', label: 'Profile', render: (r: any) => r.auth_user_id ? 'Claimed' : 'Pending' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' },
  { key: 'directory_visible', label: 'In directory', render: (r: any) => r.directory_visible === false ? 'Hidden' : 'Yes' },
  { key: 'exited_at', label: 'Exited', render: (r: any) => r.exited_at || '—' }
]

const statusFilter = ref<'all'|'active'|'inactive'|'exited'>('all')

const filteredItems = computed(() => {
  return items.value.filter((r: any) => {
    if (statusFilter.value === 'active') return r.is_active && !r.exited_at
    if (statusFilter.value === 'inactive') return !r.is_active && !r.exited_at
    if (statusFilter.value === 'exited') return !!r.exited_at
    return true
  })
})

const statusCounts = computed(() => {
  const all = items.value.length
  let active = 0, inactive = 0, exited = 0
  for (const r of items.value as any[]) {
    if (r.exited_at) exited++
    else if (r.is_active) active++
    else inactive++
  }
  return { all, active, inactive, exited }
})

await Promise.all([
  load([{ column: 'full_name', ascending: true }]),
  (async () => { const { data } = await supabase.from('departments').select('id, name').order('name'); departments.value = data ?? [] })(),
  (async () => { const { data } = await supabase.from('locations').select('id, name, city').order('name'); locations.value = data ?? [] })(),
  (async () => { const { data } = await supabase.from('teams').select('id, name, department_id').order('name'); teams.value = data ?? [] })(),
  (async () => { const { data } = await supabase.from('staff_members').select('id, full_name, role, is_active').eq('is_active', true).order('full_name'); managerCandidates.value = data ?? [] })()
])

function openNew() { editing.value = { is_active: true, directory_visible: true }; editorOpen.value = true }
function openEdit(row: any) {
  editing.value = {
    ...row,
    department_id: row.department_id ?? '',
    location_id: row.location_id ?? '',
    team_id: row.team_id ?? '',
    manager_id: row.manager_id ?? '',
    joined_date: row.joined_date ?? '',
    exited_at: row.exited_at ?? '',
    directory_visible: row.directory_visible !== false
  }
  editorOpen.value = true
}

const SYNCED_FIELDS = ['full_name', 'email', 'phone', 'department_id', 'joined_date', 'is_active'] as const

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      full_name: payload.full_name, email: payload.email, phone: payload.phone ?? '', role: payload.role,
      department_id: payload.department_id || null, location_id: payload.location_id || null,
      team_id: payload.team_id || null, manager_id: payload.manager_id || null,
      joined_date: payload.joined_date || null, bio: payload.bio ?? '', is_active: !!payload.is_active,
      directory_visible: payload.directory_visible !== false,
      exited_at: payload.exited_at || null
    }
    let staffId = editing.value?.id
    if (staffId) {
      await update(staffId, data)
    } else {
      const created = await create(data)
      staffId = created?.id
    }
    if (staffId) {
      const prev = editing.value?.id ? editing.value : {}
      const changed: string[] = []
      for (const f of SYNCED_FIELDS) {
        const before = prev?.[f] ?? null
        const after = (data as any)[f] ?? null
        if (before !== after) changed.push(f)
      }
      if (changed.length) {
        await supabase.from('staff_member_locks').upsert(
          changed.map(field => ({ staff_member_id: staffId, field })),
          { onConflict: 'staff_member_id,field' }
        )
      }
    }
    editorOpen.value = false
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.full_name}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-6xl">
    <div class="mb-4 flex flex-wrap items-center gap-2">
      <span class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold mr-1">Filter</span>
      <button
        v-for="opt in ([
          { key: 'all', label: 'All', count: statusCounts.all },
          { key: 'active', label: 'Active', count: statusCounts.active },
          { key: 'inactive', label: 'Inactive', count: statusCounts.inactive },
          { key: 'exited', label: 'Exited', count: statusCounts.exited }
        ] as const)"
        :key="opt.key"
        type="button"
        class="px-3 py-1.5 rounded-full text-xs font-medium border transition-colors inline-flex items-center gap-1.5"
        :class="statusFilter === opt.key
          ? 'bg-sycamore-600 text-white border-sycamore-600'
          : 'bg-white text-slate-600 border-slate-200 hover:border-sycamore-300 hover:text-sycamore-700'"
        @click="statusFilter = opt.key"
      >
        {{ opt.label }}
        <span class="text-[10px] px-1.5 py-0.5 rounded-full"
          :class="statusFilter === opt.key ? 'bg-white/20' : 'bg-slate-100 text-slate-500'">
          {{ opt.count }}
        </span>
      </button>
    </div>
    <AdminList title="Staff" description="Manage staff directory entries." :columns="columns" :rows="filteredItems" :loading="loading" new-label="New staff member" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit staff member' : 'New staff member'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
