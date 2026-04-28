<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

interface Resource {
  id?: string
  step_id?: string
  kind: string
  title: string
  description: string
  url: string
  body: string
  display_order: number
}

const props = defineProps<{ open: boolean; stepId: string | null; stepTitle: string }>()
const emit = defineEmits<{ (e: 'close'): void }>()

const supabase = useSupabase()
const toast = useToast()
const items = ref<Resource[]>([])
const loading = ref(false)
const form = ref<Resource>(blank())
const editingId = ref<string | null>(null)

function blank(): Resource {
  return { kind: 'link', title: '', description: '', url: '', body: '', display_order: 0 }
}

async function load() {
  if (!props.stepId) return
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('onboarding_resources')
      .select('*')
      .eq('step_id', props.stepId)
      .order('display_order', { ascending: true })
    if (error) throw error
    items.value = (data ?? []) as Resource[]
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to load resources')
  } finally {
    loading.value = false
  }
}

watch(() => [props.open, props.stepId], () => {
  if (props.open) {
    form.value = blank()
    editingId.value = null
    load()
  }
})

function startEdit(r: Resource) {
  editingId.value = r.id ?? null
  form.value = { ...r }
}

function reset() {
  editingId.value = null
  form.value = blank()
}

async function save() {
  if (!props.stepId) return
  if (!form.value.title.trim()) { toast.warning('Title is required'); return }
  try {
    const payload = {
      step_id: props.stepId,
      kind: form.value.kind || 'link',
      title: form.value.title,
      description: form.value.description ?? '',
      url: form.value.url ?? '',
      body: form.value.body ?? '',
      display_order: Number(form.value.display_order) || 0
    }
    if (editingId.value) {
      const { error } = await supabase.from('onboarding_resources').update(payload).eq('id', editingId.value)
      if (error) throw error
      toast.success('Resource updated')
    } else {
      const { error } = await supabase.from('onboarding_resources').insert(payload)
      if (error) throw error
      toast.success('Resource added')
    }
    reset()
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save resource')
  }
}

async function del(r: Resource) {
  if (!r.id) return
  const ok = await toast.confirm({ title: 'Delete resource', message: `Remove "${r.title}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('onboarding_resources').delete().eq('id', r.id)
    if (error) throw error
    toast.success('Removed')
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to delete')
  }
}

const kinds = [
  { value: 'video', label: 'Video' },
  { value: 'article', label: 'Article (inline body)' },
  { value: 'link', label: 'External link' },
  { value: 'document', label: 'Document' },
  { value: 'file', label: 'File / download' }
]
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200"
      enter-from-class="opacity-0"
      leave-active-class="transition duration-150"
      leave-to-class="opacity-0"
    >
      <div v-if="open" class="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4" @click.self="emit('close')">
        <div class="bg-white rounded-2xl shadow-xl max-w-3xl w-full max-h-[90vh] flex flex-col">
          <header class="flex items-center justify-between p-6 border-b border-slate-100">
            <div class="min-w-0">
              <h2 class="text-xl font-bold text-slate-900 truncate">Resources</h2>
              <p class="text-xs text-slate-500 mt-0.5 truncate">{{ stepTitle }}</p>
            </div>
            <button class="p-2 rounded-lg hover:bg-slate-100" @click="emit('close')" aria-label="Close">
              <SidebarIcon name="close" />
            </button>
          </header>

          <div class="flex-1 overflow-y-auto">
            <div class="p-6 border-b border-slate-100 bg-slate-50/40">
              <h3 class="text-sm font-semibold text-slate-900 mb-3">{{ editingId ? 'Edit resource' : 'Add resource' }}</h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Kind</label>
                  <select v-model="form.kind" class="input">
                    <option v-for="k in kinds" :key="k.value" :value="k.value">{{ k.label }}</option>
                  </select>
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Display order</label>
                  <input v-model="form.display_order" type="number" class="input" />
                </div>
                <div class="sm:col-span-2">
                  <label class="block text-xs font-medium text-slate-700 mb-1">Title <span class="text-rose-600">*</span></label>
                  <input v-model="form.title" class="input" placeholder="e.g. Welcome video from the CEO" />
                </div>
                <div class="sm:col-span-2">
                  <label class="block text-xs font-medium text-slate-700 mb-1">Description</label>
                  <input v-model="form.description" class="input" placeholder="Short summary shown in the list" />
                </div>
                <div v-if="form.kind !== 'article'" class="sm:col-span-2">
                  <label class="block text-xs font-medium text-slate-700 mb-1">URL</label>
                  <input v-model="form.url" class="input" placeholder="https://..." />
                  <p v-if="form.kind === 'video'" class="text-xs text-slate-500 mt-1">YouTube, Vimeo, and Loom links are auto-embedded.</p>
                </div>
                <div v-else class="sm:col-span-2">
                  <label class="block text-xs font-medium text-slate-700 mb-1">Article body</label>
                  <textarea v-model="form.body" rows="5" class="input" placeholder="Write the article inline..." />
                </div>
              </div>
              <div class="flex items-center justify-end gap-2 mt-4">
                <button v-if="editingId" type="button" class="btn-secondary" @click="reset">Cancel</button>
                <button type="button" class="btn-primary" @click="save">{{ editingId ? 'Update' : 'Add resource' }}</button>
              </div>
            </div>

            <div class="p-6">
              <h3 class="text-sm font-semibold text-slate-900 mb-3">All resources</h3>
              <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
              <div v-else-if="items.length === 0" class="text-sm text-slate-400">No resources yet.</div>
              <ul v-else class="space-y-2">
                <li v-for="r in items" :key="r.id" class="flex items-start gap-3 p-3 rounded-lg border border-slate-200">
                  <span class="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded bg-slate-100 text-slate-700 mt-0.5">{{ r.kind }}</span>
                  <div class="min-w-0 flex-1">
                    <div class="text-sm font-medium text-slate-900 truncate">{{ r.title }}</div>
                    <div v-if="r.description" class="text-xs text-slate-500 truncate">{{ r.description }}</div>
                    <a v-if="r.url" :href="r.url" target="_blank" rel="noopener" class="text-xs text-sycamore-700 hover:underline truncate block">{{ r.url }}</a>
                  </div>
                  <div class="flex items-center gap-1 flex-shrink-0">
                    <button type="button" class="p-1.5 rounded hover:bg-slate-100 text-slate-500" @click="startEdit(r)" aria-label="Edit"><SidebarIcon name="edit" /></button>
                    <button type="button" class="p-1.5 rounded hover:bg-rose-50 text-rose-600" @click="del(r)" aria-label="Delete"><SidebarIcon name="trash" /></button>
                  </div>
                </li>
              </ul>
            </div>
          </div>

          <footer class="flex items-center justify-end gap-3 p-6 border-t border-slate-100">
            <button type="button" class="btn-secondary" @click="emit('close')">Done</button>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
