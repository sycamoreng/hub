<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('quick_tools')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const departments = ref<{ name: string }[]>([])

async function loadDepartments() {
  const { data } = await supabase.from('departments').select('name').order('name')
  departments.value = data ?? []
}

const fields = computed(() => [
  { key: 'name', label: 'Tool name', required: true },
  { key: 'url', label: 'URL', required: true, placeholder: 'https://...' },
  { key: 'logo_url', label: 'Logo URL', placeholder: 'https://... (or leave blank)' },
  {
    key: 'allowed_departments',
    label: 'Visible to departments',
    type: 'textarea',
    hint: `Leave blank to show to everyone. Otherwise enter department names separated by commas. Available: ${departments.value.map(d => d.name).join(', ')}`
  },
  { key: 'sort_order', label: 'Sort order', type: 'number', placeholder: '0' },
  { key: 'is_active', label: 'Active', type: 'checkbox', placeholder: 'Show on homepage' }
] as const)

const columns = [
  { key: 'name', label: 'Name' },
  {
    key: 'allowed_departments',
    label: 'Visibility',
    render: (r: any) => {
      const arr = r.allowed_departments ?? []
      return arr.length === 0 ? 'Everyone' : arr.join(', ')
    }
  },
  { key: 'sort_order', label: 'Order' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await Promise.all([
  load([{ column: 'sort_order', ascending: true }, { column: 'name', ascending: true }]),
  loadDepartments()
])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) {
  editing.value = {
    ...row,
    allowed_departments: (row.allowed_departments ?? []).join(', ')
  }
  editorOpen.value = true
}

function parseDepartments(raw: any): string[] {
  if (!raw) return []
  if (Array.isArray(raw)) return raw
  return String(raw).split(',').map(s => s.trim()).filter(Boolean)
}

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name,
      url: payload.url,
      logo_url: payload.logo_url ?? '',
      allowed_departments: parseDepartments(payload.allowed_departments),
      sort_order: Number(payload.sort_order) || 0,
      is_active: payload.is_active !== false,
      updated_at: new Date().toISOString()
    }
    if (editing.value?.id) await update(editing.value.id, data)
    else await create(data)
    editorOpen.value = false
    toast.success('Saved')
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally {
    saving.value = false
  }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.name}"? This cannot be undone.`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList
      title="Quick access tools"
      description="Shortcuts pinned to the homepage for fast navigation to external tools. Restrict a tool to specific departments if not everyone needs it."
      :columns="columns"
      :rows="items"
      :loading="loading"
      new-label="New tool"
      @new="openNew"
      @edit="openEdit"
      @delete="del"
    />
    <AdminEditor
      :open="editorOpen"
      :title="editing ? 'Edit quick tool' : 'New quick tool'"
      :fields="(fields as any)"
      :initial="editing"
      :saving="saving"
      @close="editorOpen = false"
      @save="save"
    />
  </div>
</template>
