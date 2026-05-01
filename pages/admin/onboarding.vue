<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('onboarding_steps')
const toast = useToast()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const resourcesOpen = ref(false)
const resourcesStep = ref<any | null>(null)
const assignOpen = ref(false)
const assignStep = ref<any | null>(null)

const fields = [
  { key: 'title', label: 'Title', required: true },
  { key: 'description', label: 'Short description', type: 'textarea', hint: 'Shown under the title in the learning path.' },
  {
    key: 'content_type', label: 'Content type', type: 'select', required: true,
    options: [
      { value: 'task', label: 'Task / checklist item' },
      { value: 'video', label: 'Video' },
      { value: 'article', label: 'Article (long-form text)' },
      { value: 'module', label: 'Module (multiple resources)' }
    ],
    hint: 'Modules group several videos, articles or links into one lesson.'
  },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'general', label: 'General' },
      { value: 'paperwork', label: 'Paperwork' },
      { value: 'systems', label: 'Systems & access' },
      { value: 'culture', label: 'Culture' },
      { value: 'training', label: 'Training' },
      { value: 'product', label: 'Product knowledge' },
      { value: 'compliance', label: 'Compliance' }
    ]
  },
  { key: 'video_url', label: 'Video URL', placeholder: 'https://youtu.be/... or vimeo.com/...', hint: 'For content type "video". YouTube, Vimeo, and Loom auto-embed.' },
  { key: 'body', label: 'Long-form body', type: 'textarea', hint: 'For content type "article", or as an intro for a module.' },
  { key: 'cover_image_url', label: 'Cover image URL', placeholder: 'https://...' },
  { key: 'resource_url', label: 'Primary resource URL', placeholder: 'https://...', hint: 'Optional fallback link shown for any content type.' },
  { key: 'estimated_minutes', label: 'Estimated minutes', type: 'number' },
  { key: 'display_order', label: 'Display order', type: 'number' },
  { key: 'is_required', label: 'Required step', type: 'checkbox' },
  { key: 'is_active', label: 'Active', type: 'checkbox' }
] as const

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'content_type', label: 'Type', render: (r: any) => (r.content_type || 'task') },
  { key: 'category', label: 'Category' },
  { key: 'is_required', label: 'Required', render: (r: any) => r.is_required ? 'Yes' : 'No' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await load([{ column: 'category', ascending: true }, { column: 'display_order', ascending: true }, { column: 'title', ascending: true }])

function openNew() {
  editing.value = {
    is_required: true,
    is_active: true,
    category: 'general',
    content_type: 'task',
    display_order: 0,
    estimated_minutes: 0
  }
  editorOpen.value = true
}
function openEdit(row: any) { editing.value = { ...row }; editorOpen.value = true }
function manageResources(row: any) { resourcesStep.value = row; resourcesOpen.value = true }
function manageAssignments(row: any) { assignStep.value = row; assignOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data = {
      title: payload.title,
      description: payload.description ?? '',
      category: payload.category || 'general',
      content_type: payload.content_type || 'task',
      body: payload.body ?? '',
      video_url: payload.video_url ?? '',
      cover_image_url: payload.cover_image_url ?? '',
      resource_url: payload.resource_url ?? '',
      estimated_minutes: Number(payload.estimated_minutes) || 0,
      display_order: Number(payload.display_order) || 0,
      is_required: !!payload.is_required,
      is_active: payload.is_active === undefined ? true : !!payload.is_active
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
    toast.success('Saved')
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
  <div class="max-w-5xl">
    <AdminList
      title="Learning"
      description="Build lessons, then assign them to individuals, departments, or the whole organization."
      :columns="columns"
      :rows="items"
      :loading="loading"
      new-label="New lesson"
      @new="openNew"
      @edit="openEdit"
      @delete="del"
    >
      <template #row-actions="{ row }">
        <button
          type="button"
          class="text-xs font-medium text-sycamore-700 hover:underline"
          @click="manageResources(row)"
        >Resources</button>
        <button
          type="button"
          class="text-xs font-medium text-sycamore-700 hover:underline ml-3"
          @click="manageAssignments(row)"
        >Assignments</button>
      </template>
    </AdminList>
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit lesson' : 'New lesson'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
    <OnboardingResourcesEditor
      :open="resourcesOpen"
      :step-id="resourcesStep?.id ?? null"
      :step-title="resourcesStep?.title ?? ''"
      @close="resourcesOpen = false"
    />
    <LearningAssignmentsEditor
      :open="assignOpen"
      :step-id="assignStep?.id ?? null"
      :step-title="assignStep?.title ?? ''"
      @close="assignOpen = false"
    />
  </div>
</template>
