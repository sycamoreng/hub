<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('departments')
const toast = useToast()
const { log: auditLog } = useAuditLog()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const staff = ref<any[]>([])

const fields = computed(() => [
  { key: 'name', label: 'Name', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  { key: 'head_staff_id', label: 'Department head (staff)', type: 'select',
    options: [{ value: '', label: 'None' }, ...staff.value.map((s: any) => ({ value: s.id, label: `${s.full_name}${s.role ? ' — ' + s.role : ''}` }))] },
  { key: 'head_name', label: 'Head name (legacy)' },
  { key: 'head_title', label: 'Head title (legacy)' },
  { key: 'head_email', label: 'Head email (legacy)', type: 'email' }
])

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'head_name', label: 'Head' }
]

await Promise.all([
  load([{ column: 'name', ascending: true }]),
  (async () => { const { data } = await supabase.from('staff_members').select('id, full_name, role, is_active').eq('is_active', true).order('full_name'); staff.value = data ?? [] })()
])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row, head_staff_id: row.head_staff_id ?? '' }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name, description: payload.description ?? '',
      head_staff_id: payload.head_staff_id || null,
      head_name: payload.head_name ?? '', head_title: payload.head_title ?? '',
      head_email: payload.head_email ?? ''
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    auditLog({ action: editing.value?.id ? 'update' : 'create', target_type: 'department', target_label: data.name })
    editorOpen.value = false
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.name}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); auditLog({ action: 'delete', target_type: 'department', target_id: row.id, target_label: row.name }); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Departments" description="Teams that make Sycamore work." :columns="columns" :rows="items" :loading="loading" new-label="New department" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit department' : 'New department'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
