<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('locations')
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)

const fields = [
  { key: 'name', label: 'Office name', required: true },
  { key: 'address', label: 'Address' },
  { key: 'city', label: 'City', required: true },
  { key: 'state', label: 'State / Region' },
  { key: 'country', label: 'Country', required: true },
  {
    key: 'location_type', label: 'Type', type: 'select', required: true,
    options: [
      { value: 'headquarters', label: 'Headquarters' },
      { value: 'branch', label: 'Branch' },
      { value: 'satellite', label: 'Satellite' },
      { value: 'remote', label: 'Remote hub' }
    ]
  },
  { key: 'phone', label: 'Phone', type: 'tel' },
  { key: 'email', label: 'Email', type: 'email' },
  { key: 'timezone', label: 'Timezone', placeholder: 'e.g. Africa/Lagos' },
  { key: 'is_headquarters', label: 'Headquarters', type: 'checkbox' }
] as const

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'city', label: 'City' },
  { key: 'country', label: 'Country' },
  { key: 'is_headquarters', label: 'HQ', render: (r: any) => r.is_headquarters ? 'Yes' : 'No' }
]

await load([{ column: 'name', ascending: true }])

function openNew() { editing.value = null; editorOpen.value = true }
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      name: payload.name, address: payload.address ?? '', city: payload.city,
      state: payload.state ?? '', country: payload.country, location_type: payload.location_type,
      phone: payload.phone ?? '', email: payload.email ?? '',
      timezone: payload.timezone || 'Africa/Lagos', is_headquarters: !!payload.is_headquarters
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
  <div class="max-w-6xl">
    <AdminList title="Locations" description="Sycamore offices around the world." :columns="columns" :rows="items" :loading="loading" new-label="New location" @new="openNew" @edit="openEdit" @delete="del" />
    <AdminEditor :open="editorOpen" :title="editing ? 'Edit location' : 'New location'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
  </div>
</template>
