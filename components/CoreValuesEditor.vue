<script setup lang="ts">
import { usePerformance, type PerformanceCoreValue } from '~/composables/usePerformance'

const toast = useToast()
const { log: auditLog } = useAuditLog()
const { loadCoreValues, saveCoreValue, deleteCoreValue } = usePerformance()

const items = ref<PerformanceCoreValue[]>([])
const loading = ref(true)
const editing = ref<Partial<PerformanceCoreValue> | null>(null)

async function reload() {
  loading.value = true
  try {
    items.value = await loadCoreValues()
  } finally {
    loading.value = false
  }
}
onMounted(reload)

function newValue() {
  editing.value = { name: '', description: '', behaviour_anchors: '', weight: 1, sort_order: items.value.length, is_active: true }
}

async function save() {
  if (!editing.value) return
  if (!editing.value.name?.trim()) { toast.error('Name is required'); return }
  try {
    await saveCoreValue(editing.value)
    auditLog({ action: editing.value.id ? 'update' : 'create', target_type: 'core_value', target_label: editing.value.name })
    editing.value = null
    await reload()
    toast.success('Saved')
  } catch (e: any) { toast.error(e?.message ?? 'Could not save') }
}

async function remove(v: PerformanceCoreValue) {
  if (!confirm(`Delete "${v.name}"?`)) return
  try {
    await deleteCoreValue(v.id)
    auditLog({ action: 'delete', target_type: 'core_value', target_id: v.id, target_label: v.name })
    await reload()
  } catch (e: any) { toast.error(e?.message ?? 'Could not delete') }
}
</script>

<template>
  <section class="space-y-4">
    <header class="card p-5 flex items-end justify-between">
      <div>
        <h2 class="text-lg font-bold text-slate-900">Core values</h2>
        <p class="text-sm text-slate-500">Behavioural rubric used in the behavioural assessment portion of appraisals.</p>
      </div>
      <button class="btn-primary" @click="newValue">Add value</button>
    </header>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading...</div>
    <div v-else-if="items.length === 0" class="card p-8 text-center text-sm text-slate-500">No core values defined yet.</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
      <article v-for="v in items" :key="v.id" class="card p-4 flex flex-col gap-2">
        <div class="flex items-start justify-between gap-2">
          <div>
            <h3 class="font-semibold text-slate-900">{{ v.name }}</h3>
            <p class="text-[11px] text-slate-500">Weight {{ Number(v.weight).toFixed(2) }}</p>
          </div>
          <span v-if="!v.is_active" class="badge badge-slate">Hidden</span>
        </div>
        <p class="text-sm text-slate-600 whitespace-pre-line">{{ v.description }}</p>
        <p v-if="v.behaviour_anchors" class="text-xs text-slate-500 whitespace-pre-line border-t border-slate-100 pt-2">{{ v.behaviour_anchors }}</p>
        <div class="flex justify-end gap-3 mt-auto pt-2 border-t border-slate-100">
          <button class="text-xs font-medium text-slate-700 hover:underline" @click="editing = { ...v }">Edit</button>
          <button class="text-xs font-medium text-rose-600 hover:underline" @click="remove(v)">Delete</button>
        </div>
      </article>
    </div>

    <div
      v-if="editing"
      class="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-sm flex items-start sm:items-center justify-center p-4"
      @click.self="editing = null"
    >
      <div class="card w-full max-w-lg">
        <header class="p-5 border-b border-slate-100 flex items-center justify-between">
          <h3 class="text-base font-semibold text-slate-900">{{ editing.id ? 'Edit value' : 'New value' }}</h3>
          <button class="text-slate-400 hover:text-slate-700 text-xl leading-none" @click="editing = null">&times;</button>
        </header>
        <div class="p-5 space-y-4">
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Name</span>
            <input v-model="editing.name" class="input" placeholder="e.g. Ownership" />
          </label>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Description</span>
            <textarea v-model="editing.description" rows="3" class="input"></textarea>
          </label>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Behaviour anchors</span>
            <textarea v-model="editing.behaviour_anchors" rows="4" class="input" placeholder="What does living this value look like?"></textarea>
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Weight</span>
              <input v-model.number="editing.weight" type="number" step="0.25" min="0" class="input" />
            </label>
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Sort order</span>
              <input v-model.number="editing.sort_order" type="number" min="0" class="input" />
            </label>
          </div>
          <label class="flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" v-model="editing.is_active" />
            Active
          </label>
        </div>
        <footer class="p-5 border-t border-slate-100 flex justify-end gap-2">
          <button class="btn-secondary" @click="editing = null">Cancel</button>
          <button class="btn-primary" @click="save">Save</button>
        </footer>
      </div>
    </div>
  </section>
</template>
