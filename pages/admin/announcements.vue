<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('announcements')
const toast = useToast()

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'title', label: 'Title', required: true, placeholder: 'e.g. New office grand opening' },
  { key: 'summary', label: 'Summary / standfirst', placeholder: 'Short dek shown under the title', hint: 'Optional. Adds a press-style subheading.' },
  { key: 'content', label: 'Content', type: 'textarea', required: true, mention: true, placeholder: 'What do you want to announce? Type @ to mention a colleague.' },
  { key: 'image_url', label: 'Hero image URL', placeholder: 'https://...', hint: 'Optional. Wide hero photo shown above the headline.' },
  {
    key: 'priority', label: 'Priority', type: 'select', required: true,
    options: [
      { value: 'low', label: 'Low' },
      { value: 'medium', label: 'Medium' },
      { value: 'high', label: 'High' }
    ]
  },
  { key: 'is_active', label: 'Active', type: 'checkbox', placeholder: 'Visible on the homepage' },
  { key: 'expires_at', label: 'Expires at', type: 'date', hint: 'Optional. Leave blank if it never expires.' }
] as const

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'priority', label: 'Priority' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' },
  { key: 'created_at', label: 'Created', render: (r: any) => new Date(r.created_at).toLocaleDateString('en-GB') }
]

await load([{ column: 'created_at', ascending: false }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) {
  editing.value = { ...row, expires_at: row.expires_at ? row.expires_at.slice(0, 10) : '' }
  editorOpen.value = true
}

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data: any = {
      title: payload.title,
      content: payload.content,
      summary: payload.summary ?? '',
      image_url: payload.image_url || null,
      priority: payload.priority,
      is_active: !!payload.is_active,
      expires_at: payload.expires_at ? new Date(payload.expires_at).toISOString() : null
    }
    if (editing.value?.id) await update(editing.value.id, data)
    else await create(data)
    editorOpen.value = false
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally {
    saving.value = false
  }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.title}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-6xl">
    <AdminList
      title="Announcements"
      description="Company-wide updates shown on the dashboard."
      :columns="columns"
      :rows="items"
      :loading="loading"
      new-label="New announcement"
      @new="openNew"
      @edit="openEdit"
      @delete="del"
    />
    <AdminEditor
      :open="editorOpen"
      :title="editing ? 'Edit announcement' : 'New announcement'"
      :fields="(fields as any)"
      :initial="editing"
      :saving="saving"
      @close="editorOpen = false"
      @save="save"
    />
  </div>
</template>
