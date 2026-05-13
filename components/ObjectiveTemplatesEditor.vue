<script setup lang="ts">
import {
  usePerformance,
  OBJECTIVE_CATEGORIES,
  FRAMEWORK_KINDS,
  type PerformanceObjectiveTemplate,
  type PerformanceCycle,
  type PerformanceFramework
} from '~/composables/usePerformance'
import { useSupabase } from '~/utils/supabase'

const props = defineProps<{
  cycles: PerformanceCycle[]
  frameworks: PerformanceFramework[]
}>()

const supabase = useSupabase()
const toast = useToast()
const { loadObjectiveTemplates, saveObjectiveTemplate, deleteObjectiveTemplate } = usePerformance()

const templates = ref<any[]>([])
const departments = ref<Array<{ id: string; name: string }>>([])
const loading = ref(true)
const filterCycle = ref<string>('')
const filterScope = ref<'' | 'company' | 'department'>('')

const editing = ref<Partial<PerformanceObjectiveTemplate> | null>(null)

async function reload() {
  loading.value = true
  try {
    const opts: any = {}
    if (filterCycle.value) opts.cycleId = filterCycle.value
    if (filterScope.value) opts.scope = filterScope.value
    templates.value = await loadObjectiveTemplates(opts)
  } finally {
    loading.value = false
  }
}

onMounted(async () => {
  const { data } = await supabase.from('departments').select('id, name').order('name')
  departments.value = data ?? []
  await reload()
})

watch([filterCycle, filterScope], reload)

function newTemplate() {
  editing.value = {
    scope: 'company',
    kind: 'okr',
    category: 'company',
    title: '',
    description: '',
    default_weight: 10,
    target_value: '',
    is_active: true,
    cycle_id: filterCycle.value || null,
    department_id: null,
    framework_id: null
  }
}

function edit(t: any) {
  editing.value = { ...t }
}

async function save() {
  if (!editing.value) return
  try {
    const payload: any = { ...editing.value }
    if (!payload.title?.trim()) {
      toast.error('Title is required')
      return
    }
    if (payload.scope === 'company') payload.department_id = null
    await saveObjectiveTemplate(payload)
    toast.success('Template saved')
    editing.value = null
    await reload()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save')
  }
}

async function remove(t: any) {
  if (!confirm(`Delete "${t.title}"?`)) return
  try {
    await deleteObjectiveTemplate(t.id)
    await reload()
    toast.success('Template removed')
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not delete')
  }
}
</script>

<template>
  <section class="space-y-4">
    <header class="card p-5 flex flex-wrap items-end gap-3 justify-between">
      <div>
        <h2 class="text-lg font-bold text-slate-900">Objective templates</h2>
        <p class="text-sm text-slate-500">Cascade Company and Departmental objectives that staff can adopt into their personal cycle.</p>
      </div>
      <button class="btn-primary" @click="newTemplate">New template</button>
    </header>

    <div class="card p-4 grid gap-3 sm:grid-cols-3">
      <label class="block text-xs font-medium text-slate-600">
        <span class="block mb-1 uppercase tracking-wide">Cycle</span>
        <select v-model="filterCycle" class="input">
          <option value="">All cycles</option>
          <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
        </select>
      </label>
      <label class="block text-xs font-medium text-slate-600">
        <span class="block mb-1 uppercase tracking-wide">Scope</span>
        <select v-model="filterScope" class="input">
          <option value="">All scopes</option>
          <option value="company">Company</option>
          <option value="department">Department</option>
        </select>
      </label>
    </div>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading...</div>
    <div v-else-if="templates.length === 0" class="card p-8 text-center text-sm text-slate-500">No templates yet.</div>
    <div v-else class="card overflow-hidden">
      <table class="min-w-full text-sm">
        <thead class="bg-slate-50 text-slate-600 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left py-3 px-4">Title</th>
            <th class="text-left py-3 px-4">Scope</th>
            <th class="text-left py-3 px-4">Category</th>
            <th class="text-left py-3 px-4">Cycle</th>
            <th class="text-right py-3 px-4">Weight</th>
            <th class="text-right py-3 px-4">Actions</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">
          <tr v-for="t in templates" :key="t.id" class="hover:bg-slate-50/50">
            <td class="py-3 px-4">
              <div class="font-semibold text-slate-900">{{ t.title }}</div>
              <div class="text-xs text-slate-500 truncate max-w-md">{{ t.description }}</div>
            </td>
            <td class="py-3 px-4 text-xs">
              <span class="badge" :class="t.scope === 'company' ? 'badge-blue' : 'badge-green'">{{ t.scope }}</span>
              <div v-if="t.department" class="text-[11px] text-slate-500 mt-0.5">{{ t.department.name }}</div>
            </td>
            <td class="py-3 px-4 text-xs text-slate-600">{{ t.category }}</td>
            <td class="py-3 px-4 text-xs text-slate-600">{{ t.cycle?.name ?? '—' }}</td>
            <td class="py-3 px-4 text-right font-semibold text-slate-700">{{ Number(t.default_weight).toFixed(0) }}%</td>
            <td class="py-3 px-4 text-right whitespace-nowrap">
              <button class="text-xs font-medium text-slate-700 hover:underline mr-3" @click="edit(t)">Edit</button>
              <button class="text-xs font-medium text-rose-600 hover:underline" @click="remove(t)">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      v-if="editing"
      class="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-sm flex items-start sm:items-center justify-center p-4"
      @click.self="editing = null"
    >
      <div class="card w-full max-w-xl max-h-[90vh] overflow-y-auto">
        <header class="p-5 border-b border-slate-100 flex items-center justify-between">
          <h3 class="text-base font-semibold text-slate-900">{{ editing.id ? 'Edit template' : 'New template' }}</h3>
          <button class="text-slate-400 hover:text-slate-700 text-xl leading-none" @click="editing = null">&times;</button>
        </header>
        <div class="p-5 space-y-4">
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Title</span>
            <input v-model="editing.title" class="input" placeholder="e.g. Increase customer NPS to 70" />
          </label>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Description</span>
            <textarea v-model="editing.description" rows="3" class="input"></textarea>
          </label>
          <div class="grid grid-cols-2 gap-3">
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Scope</span>
              <select v-model="editing.scope" class="input">
                <option value="company">Company</option>
                <option value="department">Department</option>
              </select>
            </label>
            <label class="block text-xs font-medium text-slate-600" v-if="editing.scope === 'department'">
              <span class="block mb-1 uppercase tracking-wide">Department</span>
              <select v-model="editing.department_id" class="input">
                <option :value="null">—</option>
                <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
              </select>
            </label>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Cycle</span>
              <select v-model="editing.cycle_id" class="input">
                <option :value="null">Any cycle</option>
                <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
              </select>
            </label>
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Framework</span>
              <select v-model="editing.framework_id" class="input">
                <option :value="null">—</option>
                <option v-for="f in frameworks" :key="f.id" :value="f.id">{{ f.name }}</option>
              </select>
            </label>
          </div>
          <div class="grid grid-cols-3 gap-3">
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Kind</span>
              <select v-model="editing.kind" class="input">
                <option v-for="k in FRAMEWORK_KINDS" :key="k" :value="k">{{ k }}</option>
              </select>
            </label>
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Category</span>
              <select v-model="editing.category" class="input">
                <option v-for="c in OBJECTIVE_CATEGORIES" :key="c" :value="c">{{ c }}</option>
              </select>
            </label>
            <label class="block text-xs font-medium text-slate-600">
              <span class="block mb-1 uppercase tracking-wide">Default weight</span>
              <input v-model.number="editing.default_weight" type="number" min="0" max="100" class="input" />
            </label>
          </div>
          <label class="block text-xs font-medium text-slate-600">
            <span class="block mb-1 uppercase tracking-wide">Target</span>
            <input v-model="editing.target_value" class="input" placeholder="e.g. 70 NPS" />
          </label>
          <label class="flex items-center gap-2 text-sm text-slate-700">
            <input type="checkbox" v-model="editing.is_active" />
            Available for adoption
          </label>
        </div>
        <footer class="p-5 border-t border-slate-100 flex justify-end gap-2">
          <button class="btn-secondary" @click="editing = null">Cancel</button>
          <button class="btn-primary" @click="save">Save template</button>
        </footer>
      </div>
    </div>
  </section>
</template>
