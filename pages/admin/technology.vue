<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('tech_stack')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Technology', required: true },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'language', label: 'Language' },
      { value: 'framework', label: 'Framework' },
      { value: 'database', label: 'Database' },
      { value: 'cloud', label: 'Cloud / infra' },
      { value: 'devops', label: 'DevOps' },
      { value: 'data', label: 'Data & analytics' },
      { value: 'security', label: 'Security' },
      { value: 'observability', label: 'Observability' },
      { value: 'tooling', label: 'Tooling' },
      { value: 'general', label: 'General' }
    ]
  },
  { key: 'description', label: 'Description', type: 'textarea' },
  { key: 'used_for', label: 'Used for', placeholder: 'e.g. Backend services for payments' },
  { key: 'url', label: 'Reference URL', placeholder: 'https://...' },
  { key: 'display_order', label: 'Display order', type: 'number' },
  { key: 'is_active', label: 'Active', type: 'checkbox' }
] as const

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'category', label: 'Category' },
  { key: 'used_for', label: 'Used for' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await load([{ column: 'category', ascending: true }, { column: 'display_order', ascending: true }, { column: 'name', ascending: true }])

function openNew() { editing.value = { is_active: true, category: 'general', display_order: 0 }; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name,
      category: payload.category || 'general',
      description: payload.description ?? '',
      used_for: payload.used_for ?? '',
      url: payload.url ?? '',
      display_order: Number(payload.display_order) || 0,
      is_active: payload.is_active === undefined ? true : !!payload.is_active
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.name}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Technology stack" description="The tools and platforms our teams use." :columns="columns" :rows="items" :loading="loading" new-label="New technology" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit technology' : 'New technology'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
