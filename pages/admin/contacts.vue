<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('key_contacts')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Name', required: true },
  { key: 'role', label: 'Role / title', required: true },
  { key: 'department', label: 'Department' },
  { key: 'email', label: 'Email', type: 'email' },
  { key: 'phone', label: 'Phone', type: 'tel' },
  {
    key: 'category', label: 'Category', type: 'select',
    options: [
      { value: 'general', label: 'General' },
      { value: 'emergency', label: 'Emergency' },
      { value: 'IT', label: 'IT' },
      { value: 'HR', label: 'HR' },
      { value: 'finance', label: 'Finance' },
      { value: 'operations', label: 'Operations' }
    ]
  },
  { key: 'is_emergency', label: 'Emergency contact', type: 'checkbox', placeholder: 'Highlighted in emergency contacts' }
] as const

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'role', label: 'Role' },
  { key: 'department', label: 'Department' },
  { key: 'is_emergency', label: 'Emergency', render: (r: any) => r.is_emergency ? 'Yes' : 'No' }
]

await load([{ column: 'is_emergency', ascending: false }, { column: 'name', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name, role: payload.role, department: payload.department ?? '',
      email: payload.email ?? '', phone: payload.phone ?? '',
      category: payload.category || 'general', is_emergency: !!payload.is_emergency
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
  <div class="max-w-6xl">
    <AdminList title="Key Contacts" description="Important people staff can reach out to." :columns="columns" :rows="items" :loading="loading" new-label="New contact" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit contact' : 'New contact'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
