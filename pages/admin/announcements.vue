<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { items, loading, load, create, update, remove } = useCrud('announcements')
const toast = useToast()

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const departments = ref<{ id: string; name: string }[]>([])

async function loadDepartments() {
  const { data } = await supabase.from('departments').select('id, name').order('name')
  departments.value = data ?? []
}

const fields = computed(() => [
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
  { key: 'expires_at', label: 'Expires at', type: 'date', hint: 'Optional. Leave blank if it never expires.' },
  { key: 'email_on_publish', label: 'Email staff', type: 'checkbox', placeholder: 'Send this announcement as an email', hint: 'Queues an email to the audience below when you save.' },
  {
    key: 'email_audience', label: 'Email audience', type: 'select',
    options: [
      { value: 'all', label: 'All active staff' },
      { value: 'department', label: 'Specific department' },
      { value: 'mentioned', label: 'Only mentioned staff' }
    ],
    hint: 'Only applies if "Email staff" is ticked.'
  },
  {
    key: 'email_department_id', label: 'Department', type: 'select',
    options: departments.value.map(d => ({ value: d.id, label: d.name })),
    hint: 'Used when audience is "Specific department".'
  }
] as const)

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'priority', label: 'Priority' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' },
  { key: 'created_at', label: 'Created', render: (r: any) => new Date(r.created_at).toLocaleDateString('en-GB') }
]

await Promise.all([load([{ column: 'created_at', ascending: false }]), loadDepartments()])

function openNew() {
  editing.value = { email_audience: 'all', email_on_publish: false }
  editorOpen.value = true
}
function openEdit(row: any) {
  editing.value = {
    ...row,
    expires_at: row.expires_at ? row.expires_at.slice(0, 10) : '',
    email_audience: row.email_audience || 'all'
  }
  editorOpen.value = true
}

async function queueAnnouncementEmail(announcementId: string) {
  const apiUrl = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/email/queue_announcement`
  const { data: session } = await supabase.auth.getSession()
  const res = await fetch(apiUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.session?.access_token ?? ''}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ announcement_id: announcementId })
  })
  const body = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(body.error || 'Failed to queue email')
  return body
}

async function runQueueNow() {
  const apiUrl = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/email/run_queue`
  const { data: session } = await supabase.auth.getSession()
  await fetch(apiUrl, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.session?.access_token ?? ''}`,
      'Content-Type': 'application/json'
    }
  })
}

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const previouslySent = !!editing.value?.email_sent_at
    const data: any = {
      title: payload.title,
      content: payload.content,
      summary: payload.summary ?? '',
      image_url: payload.image_url || null,
      priority: payload.priority,
      is_active: !!payload.is_active,
      expires_at: payload.expires_at ? new Date(payload.expires_at).toISOString() : null,
      email_on_publish: !!payload.email_on_publish,
      email_audience: payload.email_audience || 'all',
      email_department_id: payload.email_department_id || null
    }
    let id: string | undefined = editing.value?.id
    if (id) {
      await update(id, data)
    } else {
      const created = await create(data)
      id = (created as any)?.id
    }
    if (data.email_on_publish && data.is_active && id && !previouslySent) {
      try {
        const res = await queueAnnouncementEmail(id)
        runQueueNow().catch(() => {})
        toast.success(`Announcement saved. Email queued to ${res.queued ?? 0} staff.`)
      } catch (e: any) {
        toast.error(e.message ?? 'Saved, but email could not be queued.')
      }
    } else {
      toast.success('Saved')
    }
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
