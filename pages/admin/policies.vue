<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('policies')
const toast = useToast()

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'title', label: 'Title', required: true },
  { key: 'content', label: 'Content', type: 'textarea', required: true, placeholder: 'Full policy text. Line breaks are preserved.' },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'HR', label: 'HR' },
      { value: 'Finance', label: 'Finance' },
      { value: 'IT', label: 'IT' },
      { value: 'Legal', label: 'Legal' },
      { value: 'Operations', label: 'Operations' },
      { value: 'Marketing', label: 'Marketing' }
    ]
  },
  { key: 'effective_date', label: 'Effective date', type: 'date', required: true },
  { key: 'is_active', label: 'Active', type: 'checkbox', placeholder: 'Visible to staff' }
] as const

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'category', label: 'Category' },
  { key: 'effective_date', label: 'Effective', render: (r: any) => new Date(r.effective_date).toLocaleDateString('en-GB') },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await load([{ column: 'category', ascending: true }, { column: 'title', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = { title: payload.title, content: payload.content, category: payload.category, effective_date: payload.effective_date, is_active: !!payload.is_active }
    if (editing.value?.id) await update(editing.value.id, data)
    else await create(data)
    editorOpen.value = false
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.title}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-6xl">
    <AdminList title="Policies" description="Company policies and guidelines." :columns="columns" :rows="items" :loading="loading" new-label="New policy" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit policy' : 'New policy'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
