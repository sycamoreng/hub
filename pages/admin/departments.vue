<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('departments')
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Name', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  { key: 'head_name', label: 'Department head' },
  { key: 'head_title', label: 'Head title' },
  { key: 'head_email', label: 'Head email', type: 'email' }
] as const

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'head_name', label: 'Head' }
]

await load([{ column: 'name', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name, description: payload.description ?? '',
      head_name: payload.head_name ?? '', head_title: payload.head_title ?? '',
      head_email: payload.head_email ?? ''
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
  } catch (e: any) { alert(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  if (!confirm(`Delete "${row.name}"?`)) return
  try { await remove(row.id) } catch (e: any) { alert(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Departments" description="Teams that make Sycamore work." :columns="columns" :rows="items" :loading="loading" new-label="New department" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit department' : 'New department'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
