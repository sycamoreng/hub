<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('onboarding_steps')
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'title', label: 'Title', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'general', label: 'General' },
      { value: 'paperwork', label: 'Paperwork' },
      { value: 'systems', label: 'Systems & access' },
      { value: 'culture', label: 'Culture' },
      { value: 'training', label: 'Training' },
      { value: 'product', label: 'Product knowledge' },
      { value: 'compliance', label: 'Compliance' }
    ]
  },
  { key: 'resource_url', label: 'Resource URL', placeholder: 'https://...' },
  { key: 'display_order', label: 'Display order', type: 'number' },
  { key: 'is_required', label: 'Required step', type: 'checkbox' },
  { key: 'is_active', label: 'Active', type: 'checkbox' }
] as const

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'category', label: 'Category' },
  { key: 'is_required', label: 'Required', render: (r: any) => r.is_required ? 'Yes' : 'No' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await load([{ column: 'category', ascending: true }, { column: 'display_order', ascending: true }, { column: 'title', ascending: true }])

function openNew() { editing.value = { is_required: true, is_active: true, category: 'general', display_order: 0 }; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      title: payload.title,
      description: payload.description ?? '',
      category: payload.category || 'general',
      resource_url: payload.resource_url ?? '',
      display_order: Number(payload.display_order) || 0,
      is_required: !!payload.is_required,
      is_active: payload.is_active === undefined ? true : !!payload.is_active
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
  } catch (e: any) { alert(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  if (!confirm(`Delete "${row.title}"?`)) return
  try { await remove(row.id) } catch (e: any) { alert(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Onboarding steps" description="The checklist new staff work through." :columns="columns" :rows="items" :loading="loading" new-label="New step" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit step' : 'New step'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
