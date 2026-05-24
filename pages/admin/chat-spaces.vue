<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('google_chat_spaces')
const toast = useToast()
const { log: auditLog } = useAuditLog()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const celebrationSpaceId = ref('')
const celebrationSaving = ref(false)

async function loadCelebrationConfig() {
  const { data } = await supabase
    .from('company_info')
    .select('info_value')
    .eq('info_key', 'celebration_chat_space_id')
    .maybeSingle()
  celebrationSpaceId.value = (data as any)?.info_value || ''
}

async function saveCelebrationConfig() {
  celebrationSaving.value = true
  try {
    await supabase
      .from('company_info')
      .update({ info_value: celebrationSpaceId.value, updated_at: new Date().toISOString() })
      .eq('info_key', 'celebration_chat_space_id')
    auditLog({ action: 'update', target_type: 'company_info', target_label: 'celebration_chat_space_id' })
    toast.success('Celebration broadcast space updated')
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally { celebrationSaving.value = false }
}

loadCelebrationConfig()

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
  <div class="max-w-4xl space-y-8">
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

    <section class="card p-5 space-y-4">
      <div>
        <h3 class="font-semibold text-slate-900">Celebration broadcasts</h3>
        <p class="text-sm text-slate-500 mt-0.5">Automatically send birthday and work anniversary posts to a Google Chat space.</p>
      </div>
      <div class="max-w-sm">
        <label class="block text-xs font-semibold text-slate-600 uppercase tracking-wide mb-1">Google Chat space</label>
        <select v-model="celebrationSpaceId" class="input">
          <option value="">-- None (disabled) --</option>
          <option v-for="space in items.filter((s: any) => s.is_active)" :key="space.id" :value="space.id">
            {{ space.name }}
          </option>
        </select>
      </div>
      <button
        type="button"
        class="btn-primary !px-4"
        :disabled="celebrationSaving"
        @click="saveCelebrationConfig"
      >
        {{ celebrationSaving ? 'Saving...' : 'Save' }}
      </button>
    </section>

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
