<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('branding_guidelines')
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'element_name', label: 'Element name', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  { key: 'guidelines', label: 'Guidelines', type: 'textarea', placeholder: 'Detailed guidelines.' },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'visual', label: 'Visual' },
      { value: 'communication', label: 'Communication' },
      { value: 'template', label: 'Template' }
    ]
  },
  { key: 'display_order', label: 'Display order', type: 'number' }
] as const

const columns = [
  { key: 'element_name', label: 'Element' },
  { key: 'category', label: 'Category' },
  { key: 'display_order', label: 'Order' }
]

await load([{ column: 'display_order', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = { element_name: payload.element_name, description: payload.description ?? '', guidelines: payload.guidelines ?? '', category: payload.category, display_order: Number(payload.display_order) || 0 }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
  } catch (e: any) { alert(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  if (!confirm(`Delete "${row.element_name}"?`)) return
  try { await remove(row.id) } catch (e: any) { alert(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Branding guidelines" description="Visual, communication and template guidelines." :columns="columns" :rows="items" :loading="loading" new-label="New guideline" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit guideline' : 'New guideline'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
