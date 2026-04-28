<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('benefits_perks')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'title', label: 'Title', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'health', label: 'Health' },
      { value: 'time-off', label: 'Time off' },
      { value: 'financial', label: 'Financial' },
      { value: 'learning', label: 'Learning' },
      { value: 'wellness', label: 'Wellness' },
      { value: 'family', label: 'Family' },
      { value: 'lifestyle', label: 'Lifestyle' }
    ]
  },
  { key: 'eligibility', label: 'Eligibility', placeholder: 'e.g. All staff' },
  { key: 'display_order', label: 'Display order', type: 'number' }
] as const

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'category', label: 'Category' },
  { key: 'eligibility', label: 'Eligibility' }
]

await load([{ column: 'display_order', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = { title: payload.title, description: payload.description ?? '', category: payload.category, eligibility: payload.eligibility || 'All staff', display_order: Number(payload.display_order) || 0 }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
    toast.success('Saved')
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
  <div class="max-w-5xl">
    <AdminList title="Benefits & Perks" description="What staff get for working at Sycamore." :columns="columns" :rows="items" :loading="loading" new-label="New benefit" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit benefit' : 'New benefit'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
