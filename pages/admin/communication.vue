<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('communication_tools')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Tool name', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  { key: 'url', label: 'URL', placeholder: 'https://...' },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'messaging', label: 'Messaging' },
      { value: 'email', label: 'Email' },
      { value: 'video', label: 'Video' },
      { value: 'collaboration', label: 'Collaboration' },
      { value: 'project-management', label: 'Project Management' },
      { value: 'documentation', label: 'Documentation' },
      { value: 'general', label: 'General' }
    ]
  },
  { key: 'is_primary', label: 'Primary tool', type: 'checkbox', placeholder: 'Highlight as recommended' }
] as const

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'category', label: 'Category' },
  { key: 'is_primary', label: 'Primary', render: (r: any) => r.is_primary ? 'Yes' : 'No' }
]

await load([{ column: 'is_primary', ascending: false }, { column: 'name', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = { name: payload.name, description: payload.description ?? '', url: payload.url ?? '', category: payload.category, is_primary: !!payload.is_primary }
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
    <AdminList title="Communication tools" description="Platforms staff use to stay connected." :columns="columns" :rows="items" :loading="loading" new-label="New tool" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit tool' : 'New tool'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
