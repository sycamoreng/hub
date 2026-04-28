<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('holidays_events')
const toast = useToast()

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'title', label: 'Title', required: true },
  { key: 'description', label: 'Description', type: 'textarea' },
  { key: 'event_date', label: 'Event date', type: 'date', required: true },
  { key: 'end_date', label: 'End date', type: 'date', hint: 'Optional. For multi-day events.' },
  {
    key: 'event_type', label: 'Type', type: 'select', required: true,
    options: [
      { value: 'event', label: 'Event' },
      { value: 'holiday', label: 'Holiday' },
      { value: 'company', label: 'Company' },
      { value: 'training', label: 'Training' }
    ]
  },
  { key: 'is_recurring', label: 'Recurring', type: 'checkbox', placeholder: 'Repeats annually' }
] as const

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'event_type', label: 'Type' },
  { key: 'event_date', label: 'Date', render: (r: any) => new Date(r.event_date).toLocaleDateString('en-GB') },
  { key: 'is_recurring', label: 'Recurring', render: (r: any) => r.is_recurring ? 'Yes' : 'No' }
]

await load([{ column: 'event_date', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) {
  editing.value = { ...row, event_date: row.event_date ?? '', end_date: row.end_date ?? '' }
  editorOpen.value = true
}

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      title: payload.title,
      description: payload.description ?? '',
      event_date: payload.event_date,
      end_date: payload.end_date || null,
      event_type: payload.event_type,
      is_recurring: !!payload.is_recurring
    }
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
    <AdminList title="Events & Holidays" description="Calendar events, public holidays, and important dates." :columns="columns" :rows="items" :loading="loading" new-label="New event" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit event' : 'New event'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
