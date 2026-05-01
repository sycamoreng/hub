<script setup lang="ts">
definePageMeta({ layout: 'admin' })

const { isAdmin, ready } = useAuth()
const { order, load, save } = useSidebarOrder()
const toast = useToast()

const GROUP_META: Record<string, { label: string; icon: string; description: string }> = {
  company: { label: 'Company', icon: 'building', description: 'Leadership, Departments, Locations, Staff Directory' },
  productivity: { label: 'Productivity', icon: 'sparkle', description: 'Tools, Onboarding' },
  work: { label: 'Products & Tech', icon: 'gift', description: 'Products, Technology' },
  people: { label: 'People & Culture', icon: 'users', description: 'Policies, Benefits, Branding' },
  comms: { label: 'Communication', icon: 'chat', description: 'Communication, Key Contacts, Calendar' }
}

const draft = ref<string[]>([])
const saving = ref(false)

watchEffect(() => {
  if (ready.value && isAdmin.value) load()
})

watch(order, (val) => {
  draft.value = [...val]
}, { immediate: true })

const dirty = computed(() => {
  if (draft.value.length !== order.value.length) return true
  return draft.value.some((id, i) => id !== order.value[i])
})

function move(index: number, delta: number) {
  const target = index + delta
  if (target < 0 || target >= draft.value.length) return
  const next = [...draft.value]
  ;[next[index], next[target]] = [next[target], next[index]]
  draft.value = next
}

const dragIndex = ref<number | null>(null)
const dragOverIndex = ref<number | null>(null)

function onDragStart(idx: number, e: DragEvent) {
  dragIndex.value = idx
  if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move'
}
function onDragOver(idx: number, e: DragEvent) {
  if (dragIndex.value === null || dragIndex.value === idx) return
  e.preventDefault()
  if (e.dataTransfer) e.dataTransfer.dropEffect = 'move'
  dragOverIndex.value = idx
}
function onDrop(idx: number, e: DragEvent) {
  e.preventDefault()
  const from = dragIndex.value
  dragIndex.value = null
  dragOverIndex.value = null
  if (from === null || from === idx) return
  const next = [...draft.value]
  const [moved] = next.splice(from, 1)
  next.splice(idx, 0, moved)
  draft.value = next
}
function onDragEnd() {
  dragIndex.value = null
  dragOverIndex.value = null
}

async function submit() {
  saving.value = true
  try {
    await save(draft.value)
    toast.success('Sidebar order saved')
  } catch (e: any) {
    toast.error(e?.message || 'Failed to save sidebar order')
  } finally {
    saving.value = false
  }
}

function resetDraft() {
  draft.value = [...order.value]
}
</script>

<template>
  <div class="space-y-6">
    <header class="flex items-start justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">Sidebar order</h1>
        <p class="text-sm text-slate-500 mt-1">Drag to reorder the section groups shown in the client sidebar. Changes apply to everyone in the organization.</p>
      </div>
      <div class="flex items-center gap-2">
        <button
          type="button"
          class="px-3 py-2 rounded-lg border border-slate-200 text-sm text-slate-700 hover:bg-slate-50 disabled:opacity-50"
          :disabled="!dirty || saving"
          @click="resetDraft"
        >
          Discard
        </button>
        <button
          type="button"
          class="px-3 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-semibold hover:bg-sycamore-700 disabled:opacity-50"
          :disabled="!dirty || saving"
          @click="submit"
        >
          {{ saving ? 'Saving...' : 'Save order' }}
        </button>
      </div>
    </header>

    <div class="card p-4 max-w-2xl">
      <ul class="flex flex-col gap-2">
        <li
          v-for="(id, idx) in draft"
          :key="id"
          draggable="true"
          class="flex items-center gap-3 p-3 rounded-lg border border-slate-200 bg-white transition-colors"
          :class="[
            dragIndex === idx ? 'opacity-40' : '',
            dragOverIndex === idx ? 'ring-2 ring-sycamore-400 bg-sycamore-50/60' : ''
          ]"
          @dragstart="onDragStart(idx, $event)"
          @dragover="onDragOver(idx, $event)"
          @drop="onDrop(idx, $event)"
          @dragend="onDragEnd"
        >
          <span class="text-slate-300 cursor-grab active:cursor-grabbing">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
              <path d="M7 4a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm6 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2ZM7 11a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm6 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2ZM7 18a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm6 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z" />
            </svg>
          </span>
          <div class="w-8 h-8 rounded-lg bg-slate-100 flex items-center justify-center text-slate-600">
            <SidebarIcon :name="GROUP_META[id]?.icon || 'star'" />
          </div>
          <div class="flex-1 min-w-0">
            <div class="text-sm font-semibold text-slate-900">{{ GROUP_META[id]?.label || id }}</div>
            <div class="text-xs text-slate-500 truncate">{{ GROUP_META[id]?.description || '' }}</div>
          </div>
          <div class="flex items-center gap-1">
            <button
              type="button"
              class="p-1.5 rounded hover:bg-slate-100 text-slate-500 disabled:opacity-30"
              :disabled="idx === 0"
              @click="move(idx, -1)"
              aria-label="Move up"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path fill-rule="evenodd" d="M10 5a.75.75 0 0 1 .53.22l4.25 4.25a.75.75 0 1 1-1.06 1.06L10 6.81l-3.72 3.72a.75.75 0 1 1-1.06-1.06l4.25-4.25A.75.75 0 0 1 10 5Z" clip-rule="evenodd" />
              </svg>
            </button>
            <button
              type="button"
              class="p-1.5 rounded hover:bg-slate-100 text-slate-500 disabled:opacity-30"
              :disabled="idx === draft.length - 1"
              @click="move(idx, 1)"
              aria-label="Move down"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path fill-rule="evenodd" d="M10 15a.75.75 0 0 1-.53-.22L5.22 10.53a.75.75 0 1 1 1.06-1.06L10 13.19l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25A.75.75 0 0 1 10 15Z" clip-rule="evenodd" />
              </svg>
            </button>
          </div>
        </li>
      </ul>
      <p class="text-xs text-slate-400 mt-4">Only section groups are reorderable. Standalone links (Home, Feed, Raffle) always appear at the top.</p>
    </div>
  </div>
</template>
