<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('company_info')
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'info_key', label: 'Key', required: true, placeholder: 'e.g. tagline, mission, founded_year', hint: 'Identifier used in the app. Use snake_case.' },
  { key: 'info_value', label: 'Value', type: 'textarea', required: true },
  {
    key: 'category', label: 'Category', type: 'select',
    options: [
      { value: 'general', label: 'General' },
      { value: 'about', label: 'About' },
      { value: 'mission', label: 'Mission & vision' },
      { value: 'history', label: 'History' },
      { value: 'leadership', label: 'Leadership' }
    ]
  },
  { key: 'display_order', label: 'Display order', type: 'number' }
] as const

const columns = [
  { key: 'info_key', label: 'Key' },
  { key: 'category', label: 'Category' },
  { key: 'info_value', label: 'Value', render: (r: any) => (r.info_value || '').slice(0, 80) + ((r.info_value || '').length > 80 ? '...' : '') }
]

await load([{ column: 'display_order', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = { info_key: payload.info_key, info_value: payload.info_value, category: payload.category || 'general', display_order: Number(payload.display_order) || 0 }
    if (editing.value?.id) await update(editing.value.id, { ...data, updated_at: new Date().toISOString() }); else await create(data)
    editorOpen.value = false
  } catch (e: any) { alert(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  if (!confirm(`Delete "${row.info_key}"?`)) return
  try { await remove(row.id) } catch (e: any) { alert(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Company info" description="Key-value content shown across the hub." :columns="columns" :rows="items" :loading="loading" new-label="New info" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit info' : 'New info'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
