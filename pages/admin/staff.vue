<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('staff_members')
const toast = useToast()
const departments = ref<any[]>([])
const locations = ref<any[]>([])

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
  { key: 'joined_date', label: 'Joined date', type: 'date' },
  { key: 'bio', label: 'Bio', type: 'textarea' },
  { key: 'is_active', label: 'Active', type: 'checkbox', placeholder: 'Currently employed' }
])

const columns = [
  { key: 'full_name', label: 'Name' },
  { key: 'role', label: 'Role' },
  { key: 'email', label: 'Email' },
  { key: 'auth_user_id', label: 'Profile', render: (r: any) => r.auth_user_id ? 'Claimed' : 'Pending' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await Promise.all([
  load([{ column: 'full_name', ascending: true }]),
  (async () => { const { data } = await supabase.from('departments').select('id, name').order('name'); departments.value = data ?? [] })(),
  (async () => { const { data } = await supabase.from('locations').select('id, name, city').order('name'); locations.value = data ?? [] })()
])

function openNew() { editing.value = { is_active: true }; editorOpen.value = true }
function openEdit(row: any) {
  editing.value = { ...row, department_id: row.department_id ?? '', location_id: row.location_id ?? '', joined_date: row.joined_date ?? '' }
  editorOpen.value = true
}

const SYNCED_FIELDS = ['full_name', 'email', 'phone', 'department_id', 'joined_date', 'is_active'] as const

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      full_name: payload.full_name, email: payload.email, phone: payload.phone ?? '', role: payload.role,
      department_id: payload.department_id || null, location_id: payload.location_id || null,
      joined_date: payload.joined_date || null, bio: payload.bio ?? '', is_active: !!payload.is_active
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
    <AdminList title="Staff" description="Manage staff directory entries." :columns="columns" :rows="items" :loading="loading" new-label="New staff member" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit staff member' : 'New staff member'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
