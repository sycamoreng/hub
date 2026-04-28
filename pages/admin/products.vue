<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('products')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Product name', required: true },
  { key: 'tagline', label: 'Tagline', placeholder: 'One sentence summary' },
  { key: 'description', label: 'Description', type: 'textarea' },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'payments', label: 'Payments' },
      { value: 'lending', label: 'Lending' },
      { value: 'savings', label: 'Savings & investments' },
      { value: 'banking', label: 'Banking' },
      { value: 'cards', label: 'Cards' },
      { value: 'business', label: 'Business / B2B' },
      { value: 'consumer', label: 'Consumer / B2C' },
      { value: 'infrastructure', label: 'Infrastructure / API' },
      { value: 'general', label: 'General' }
    ]
  },
  {
    key: 'status', label: 'Status', type: 'select', required: true,
    options: [
      { value: 'live', label: 'Live' },
      { value: 'beta', label: 'Beta' },
      { value: 'internal', label: 'Internal' },
      { value: 'retired', label: 'Retired' }
    ]
  },
  { key: 'target_market', label: 'Target market', placeholder: 'e.g. SMEs in Nigeria' },
  { key: 'url', label: 'Product URL', placeholder: 'https://...' },
  { key: 'display_order', label: 'Display order', type: 'number' },
  { key: 'is_active', label: 'Active', type: 'checkbox' }
] as const

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'category', label: 'Category' },
  { key: 'status', label: 'Status' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await load([{ column: 'display_order', ascending: true }, { column: 'name', ascending: true }])

function openNew() { editing.value = { is_active: true, status: 'live', category: 'general', display_order: 0 }; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name,
      tagline: payload.tagline ?? '',
      description: payload.description ?? '',
      category: payload.category || 'general',
      status: payload.status || 'live',
      target_market: payload.target_market ?? '',
      url: payload.url ?? '',
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
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.name}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Products" description="Sycamore's fintech offerings." :columns="columns" :rows="items" :loading="loading" new-label="New product" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit product' : 'New product'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
