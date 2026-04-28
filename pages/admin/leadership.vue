<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('leadership')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'full_name', label: 'Full name', required: true },
  { key: 'title', label: 'Title / role', required: true },
  {
    key: 'tier', label: 'Tier', type: 'select', required: true,
    options: [
      { value: 'board', label: 'Board of Directors' },
      { value: 'executive', label: 'Executives' },
      { value: 'senior', label: 'Senior Management' }
    ]
  },
  { key: 'bio', label: 'Bio', type: 'textarea' },
  { key: 'email', label: 'Email', type: 'email' },
  { key: 'phone', label: 'Phone', type: 'tel' },
  { key: 'photo_url', label: 'Photo URL', placeholder: 'https://...' },
  { key: 'linkedin_url', label: 'LinkedIn URL', placeholder: 'https://...' },
  { key: 'display_order', label: 'Display order', type: 'number' },
  { key: 'is_active', label: 'Active', type: 'checkbox' }
] as const

const tierLabels: Record<string, string> = {
  board: 'Board',
  executive: 'Executive',
  senior: 'Senior Mgmt'
}

const columns = [
  { key: 'full_name', label: 'Name' },
  { key: 'title', label: 'Title' },
  { key: 'tier', label: 'Tier', render: (r: any) => tierLabels[r.tier] ?? r.tier },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await load([{ column: 'tier', ascending: true }, { column: 'display_order', ascending: true }, { column: 'full_name', ascending: true }])

function openNew() { editing.value = { is_active: true, tier: 'executive', display_order: 0 }; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      full_name: payload.full_name,
      title: payload.title,
      tier: payload.tier,
      bio: payload.bio ?? '',
      email: payload.email ?? '',
      phone: payload.phone ?? '',
      photo_url: payload.photo_url ?? '',
      linkedin_url: payload.linkedin_url ?? '',
      display_order: Number(payload.display_order) || 0,
      is_active: payload.is_active === undefined ? true : !!payload.is_active
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.full_name}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-6xl">
    <AdminList title="Leadership" description="Board of directors, executives, and senior management." :columns="columns" :rows="items" :loading="loading" new-label="New leader" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit leader' : 'New leader'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
