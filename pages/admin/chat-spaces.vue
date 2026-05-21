<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('google_chat_spaces')
const toast = useToast()
const { log: auditLog } = useAuditLog()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Label', required: true, placeholder: 'e.g. #general' },
  { key: 'webhook_url', label: 'Incoming webhook URL', required: true, placeholder: 'https://chat.googleapis.com/v1/spaces/...' , hint: 'Create an incoming webhook inside the Google Chat space and paste its URL here.' },
  { key: 'is_active', label: 'Active', type: 'checkbox', placeholder: 'Available for broadcasting' }
] as const

const columns = [
  { key: 'name', label: 'Label' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' },
  { key: 'created_at', label: 'Created', render: (r: any) => new Date(r.created_at).toLocaleDateString('en-GB') }
]

await load([{ column: 'name', ascending: true }])

function openNew() {
  editing.value = { is_active: true }
  editorOpen.value = true
}
function openEdit(row: any) {
  editing.value = { ...row }
  editorOpen.value = true
}

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name?.trim(),
      webhook_url: payload.webhook_url?.trim(),
      is_active: !!payload.is_active,
      updated_at: new Date().toISOString()
    }
    if (editing.value?.id) await update(editing.value.id, data)
    else await create(data)
    auditLog({ action: editing.value?.id ? 'update' : 'create', target_type: 'chat_space', target_label: data.name })
    toast.success('Saved')
    editorOpen.value = false
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.name}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); auditLog({ action: 'delete', target_type: 'chat_space', target_id: row.id, target_label: row.name }); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed') }
}
</script>

<template>
  <div class="max-w-4xl">
    <AdminList
      title="Google Chat spaces"
      description="Webhooks for broadcasting announcements to Google Workspace."
      :columns="columns"
      :rows="items"
      :loading="loading"
      new-label="New space"
      @new="openNew"
      @edit="openEdit"
      @delete="del"
    />
    <AdminEditor
      :open="editorOpen"
      :title="editing?.id ? 'Edit chat space' : 'New chat space'"
      :fields="(fields as any)"
      :initial="editing"
      :saving="saving"
      @close="editorOpen = false"
      @save="save"
    />
  </div>
</template>
