<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { WEEKDAYS } from '~/composables/useAttendance'

const supabase = useSupabase()
const toast = useToast()

const templates = ref<any[]>([])
const departments = ref<any[]>([])
const locations = ref<any[]>([])
const staff = ref<any[]>([])
const loading = ref(true)
const selectedId = ref<string>('')
const editorDays = ref<Record<number, any>>({})
const editor = ref<any | null>(null)
const memberIds = ref<Set<string>>(new Set())
const memberSearch = ref('')
const saving = ref(false)

function emptyDays() {
  const map: Record<number, any> = {}
  for (let d = 0; d < 7; d++) map[d] = { weekday: d, is_working: d >= 1 && d <= 5, start_time: '09:00', end_time: '17:00' }
  return map
}

async function loadAll() {
  loading.value = true
  try {
    const [{ data: t }, { data: d }, { data: l }, { data: sm }] = await Promise.all([
      supabase.from('schedule_templates').select('*').order('scope').order('name'),
      supabase.from('departments').select('id, name').order('name'),
      supabase.from('locations').select('id, name, city').order('name'),
      supabase.from('staff_members').select('id, full_name, email, is_active, department_id, location_id').order('full_name')
    ])
    templates.value = t ?? []
    departments.value = d ?? []
    locations.value = l ?? []
    staff.value = (sm ?? []).filter((s: any) => s.is_active)
  } finally { loading.value = false }
}

async function selectTemplate(id: string) {
  selectedId.value = id
  const tpl = templates.value.find(t => t.id === id) ?? null
  editor.value = tpl ? { ...tpl } : null
  memberSearch.value = ''
  if (tpl) {
    const [{ data: days }, { data: members }] = await Promise.all([
      supabase.from('schedule_template_days').select('*').eq('template_id', id),
      supabase.from('schedule_template_members').select('staff_id').eq('template_id', id)
    ])
    const map = emptyDays()
    for (const r of (days ?? [])) {
      map[r.weekday] = {
        ...r,
        start_time: (r.start_time || '09:00').slice(0, 5),
        end_time: (r.end_time || '17:00').slice(0, 5)
      }
    }
    editorDays.value = map
    memberIds.value = new Set((members ?? []).map((m: any) => m.staff_id))
  } else {
    editorDays.value = emptyDays()
    memberIds.value = new Set()
  }
}

function toggleMember(id: string) {
  const next = new Set(memberIds.value)
  if (next.has(id)) next.delete(id); else next.add(id)
  memberIds.value = next
}

const filteredStaff = computed(() => {
  const q = memberSearch.value.trim().toLowerCase()
  if (!q) return staff.value
  return staff.value.filter(s => (s.full_name + ' ' + s.email).toLowerCase().includes(q))
})

function addAllBy(kind: 'department' | 'location', groupId: string | null | undefined) {
  if (!groupId) return
  const next = new Set(memberIds.value)
  for (const s of staff.value) {
    if (kind === 'department' && s.department_id === groupId) next.add(s.id)
    if (kind === 'location' && s.location_id === groupId) next.add(s.id)
  }
  memberIds.value = next
}

function clearMembers() { memberIds.value = new Set() }

function newTemplate(scope: 'organization' | 'department' | 'location') {
  selectedId.value = ''
  editor.value = { name: '', scope, department_id: null, location_id: null, is_default: scope === 'organization', notes: '' }
  editorDays.value = emptyDays()
  memberIds.value = new Set()
  memberSearch.value = ''
}

async function save() {
  if (!editor.value?.name) { toast.error('Name is required'); return }
  saving.value = true
  try {
    const payload: any = {
      name: editor.value.name,
      scope: editor.value.scope,
      department_id: editor.value.scope === 'department' ? (editor.value.department_id || null) : null,
      location_id: editor.value.scope === 'location' ? (editor.value.location_id || null) : null,
      is_default: Boolean(editor.value.is_default),
      notes: editor.value.notes || '',
      updated_at: new Date().toISOString()
    }
    let tplId = editor.value.id
    if (tplId) {
      const { error } = await supabase.from('schedule_templates').update(payload).eq('id', tplId)
      if (error) throw error
    } else {
      const { data, error } = await supabase.from('schedule_templates').insert(payload).select().maybeSingle()
      if (error) throw error
      tplId = data!.id
    }

    // if set as default for its scope+group, unset other defaults in same scope/group
    if (payload.is_default) {
      let q = supabase.from('schedule_templates').update({ is_default: false }).eq('scope', payload.scope).neq('id', tplId)
      if (payload.scope === 'department') q = q.eq('department_id', payload.department_id)
      if (payload.scope === 'location') q = q.eq('location_id', payload.location_id)
      await q
    }

    // upsert days
    const rows = Object.values(editorDays.value).map((r: any) => ({
      template_id: tplId,
      weekday: r.weekday,
      is_working: Boolean(r.is_working),
      start_time: r.start_time || '09:00',
      end_time: r.end_time || '17:00'
    }))
    const { error: daysErr } = await supabase.from('schedule_template_days').upsert(rows, { onConflict: 'template_id,weekday' })
    if (daysErr) throw daysErr

    // sync members
    const { data: currentMembers } = await supabase.from('schedule_template_members').select('staff_id').eq('template_id', tplId)
    const currentSet = new Set((currentMembers ?? []).map((m: any) => m.staff_id))
    const desired = memberIds.value
    const toAdd = [...desired].filter(id => !currentSet.has(id))
    const toRemove = [...currentSet].filter(id => !desired.has(id))
    if (toAdd.length) {
      const { error: addErr } = await supabase.from('schedule_template_members').insert(toAdd.map(staff_id => ({ template_id: tplId, staff_id })))
      if (addErr) throw addErr
    }
    if (toRemove.length) {
      const { error: rmErr } = await supabase.from('schedule_template_members').delete().eq('template_id', tplId).in('staff_id', toRemove)
      if (rmErr) throw rmErr
    }

    toast.success('Template saved')
    await loadAll()
    await selectTemplate(tplId)
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del() {
  if (!editor.value?.id) return
  if (!(await toast.confirm({ title: 'Delete template', message: `Delete "${editor.value.name}"?`, variant: 'danger', confirmLabel: 'Delete' }))) return
  try {
    const { error } = await supabase.from('schedule_templates').delete().eq('id', editor.value.id)
    if (error) throw error
    toast.success('Deleted')
    editor.value = null
    selectedId.value = ''
    await loadAll()
  } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}

function groupLabel(t: any) {
  if (t.scope === 'organization') return 'Organization'
  if (t.scope === 'department') return 'Department: ' + (departments.value.find(d => d.id === t.department_id)?.name ?? '—')
  return 'Location: ' + (locations.value.find(l => l.id === t.location_id)?.name ?? '—')
}

const grouped = computed(() => {
  const org = templates.value.filter(t => t.scope === 'organization')
  const dept = templates.value.filter(t => t.scope === 'department')
  const loc = templates.value.filter(t => t.scope === 'location')
  return { org, dept, loc }
})

loadAll()
</script>

<template>
  <div class="grid grid-cols-1 lg:grid-cols-[260px_1fr] gap-4">
    <aside class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <div class="p-3 border-b border-slate-100 space-y-1">
        <button type="button" @click="newTemplate('organization')" class="w-full text-left px-3 py-2 text-sm font-medium rounded-md hover:bg-slate-50">+ Organization template</button>
        <button type="button" @click="newTemplate('department')" class="w-full text-left px-3 py-2 text-sm font-medium rounded-md hover:bg-slate-50">+ Department template</button>
        <button type="button" @click="newTemplate('location')" class="w-full text-left px-3 py-2 text-sm font-medium rounded-md hover:bg-slate-50">+ Location template</button>
      </div>
      <div v-if="loading" class="p-4 text-sm text-slate-500">Loading...</div>
      <div v-else class="divide-y divide-slate-100">
        <div v-if="grouped.org.length" class="py-2">
          <div class="px-4 text-[10px] uppercase tracking-wide text-slate-400 mb-1">Organization</div>
          <button v-for="t in grouped.org" :key="t.id" type="button" @click="selectTemplate(t.id)"
            class="w-full flex items-center justify-between gap-2 px-4 py-2 text-sm text-left hover:bg-slate-50"
            :class="selectedId === t.id ? 'bg-sycamore-50 text-sycamore-700' : 'text-slate-700'">
            <span class="truncate">{{ t.name }}</span>
            <span v-if="t.is_default" class="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200">Default</span>
          </button>
        </div>
        <div v-if="grouped.dept.length" class="py-2">
          <div class="px-4 text-[10px] uppercase tracking-wide text-slate-400 mb-1">Departments</div>
          <button v-for="t in grouped.dept" :key="t.id" type="button" @click="selectTemplate(t.id)"
            class="w-full flex items-center justify-between gap-2 px-4 py-2 text-sm text-left hover:bg-slate-50"
            :class="selectedId === t.id ? 'bg-sycamore-50 text-sycamore-700' : 'text-slate-700'">
            <span class="truncate">{{ t.name }}</span>
            <span v-if="t.is_default" class="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200">Default</span>
          </button>
        </div>
        <div v-if="grouped.loc.length" class="py-2">
          <div class="px-4 text-[10px] uppercase tracking-wide text-slate-400 mb-1">Locations</div>
          <button v-for="t in grouped.loc" :key="t.id" type="button" @click="selectTemplate(t.id)"
            class="w-full flex items-center justify-between gap-2 px-4 py-2 text-sm text-left hover:bg-slate-50"
            :class="selectedId === t.id ? 'bg-sycamore-50 text-sycamore-700' : 'text-slate-700'">
            <span class="truncate">{{ t.name }}</span>
            <span v-if="t.is_default" class="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700 border border-emerald-200">Default</span>
          </button>
        </div>
        <div v-if="templates.length === 0" class="p-4 text-sm text-slate-500">No templates yet.</div>
      </div>
    </aside>

    <section v-if="editor" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <header class="px-5 py-4 border-b border-slate-200 flex items-center justify-between">
        <div>
          <h3 class="text-sm font-semibold text-slate-900">{{ editor.id ? 'Edit template' : 'New template' }}</h3>
          <p class="text-xs text-slate-500 mt-0.5 capitalize">{{ editor.scope }} scope</p>
        </div>
        <div class="flex items-center gap-2">
          <button v-if="editor.id" type="button" @click="del" class="text-rose-600 text-sm font-medium">Delete</button>
          <button type="button" @click="save" :disabled="saving" class="px-4 py-1.5 bg-sycamore-600 hover:bg-sycamore-700 disabled:opacity-50 text-white rounded-md text-sm font-medium">
            {{ saving ? 'Saving...' : 'Save' }}
          </button>
        </div>
      </header>
      <div class="p-5 space-y-5">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <label class="text-sm">
            <span class="block text-slate-600 mb-1">Name</span>
            <input v-model="editor.name" type="text" class="w-full border border-slate-300 rounded-md px-3 py-2" placeholder="e.g. Standard office hours" />
          </label>
          <label v-if="editor.scope === 'department'" class="text-sm">
            <span class="block text-slate-600 mb-1">Department</span>
            <select v-model="editor.department_id" class="w-full border border-slate-300 rounded-md px-3 py-2">
              <option :value="null">Select...</option>
              <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
            </select>
          </label>
          <label v-if="editor.scope === 'location'" class="text-sm">
            <span class="block text-slate-600 mb-1">Location</span>
            <select v-model="editor.location_id" class="w-full border border-slate-300 rounded-md px-3 py-2">
              <option :value="null">Select...</option>
              <option v-for="l in locations" :key="l.id" :value="l.id">{{ l.name }}<span v-if="l.city"> ({{ l.city }})</span></option>
            </select>
          </label>
          <label class="flex items-center gap-2 text-sm sm:col-span-2">
            <input type="checkbox" v-model="editor.is_default" class="rounded" />
            <span>Use as default for this {{ editor.scope }}</span>
          </label>
        </div>

        <div class="border border-slate-200 rounded-lg overflow-hidden">
          <table class="w-full text-sm">
            <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
              <tr>
                <th class="text-left px-4 py-2">Day</th>
                <th class="text-left px-4 py-2">Working</th>
                <th class="text-left px-4 py-2">Start</th>
                <th class="text-left px-4 py-2">End</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="d in 7" :key="d - 1" class="border-t border-slate-100">
                <td class="px-4 py-2 font-medium text-slate-900">{{ WEEKDAYS[d - 1] }}</td>
                <td class="px-4 py-2">
                  <label class="inline-flex items-center gap-2">
                    <input type="checkbox" v-model="editorDays[d - 1].is_working" class="rounded" />
                    <span class="text-xs text-slate-500">{{ editorDays[d - 1].is_working ? 'On shift' : 'Off' }}</span>
                  </label>
                </td>
                <td class="px-4 py-2"><input type="time" v-model="editorDays[d - 1].start_time" :disabled="!editorDays[d - 1].is_working" class="border border-slate-300 rounded-md px-2 py-1 text-sm disabled:bg-slate-50" /></td>
                <td class="px-4 py-2"><input type="time" v-model="editorDays[d - 1].end_time" :disabled="!editorDays[d - 1].is_working" class="border border-slate-300 rounded-md px-2 py-1 text-sm disabled:bg-slate-50" /></td>
              </tr>
            </tbody>
          </table>
        </div>

        <div>
          <div class="flex items-center justify-between mb-2">
            <div>
              <h4 class="text-sm font-semibold text-slate-900">Assigned staff</h4>
              <p class="text-xs text-slate-500">Specific employees on this schedule ({{ memberIds.size }} selected). Overrides scope defaults.</p>
            </div>
            <button v-if="memberIds.size" type="button" @click="clearMembers" class="text-xs text-rose-600 font-medium">Clear all</button>
          </div>

          <div class="flex flex-wrap items-center gap-2 mb-3">
            <input v-model="memberSearch" type="text" placeholder="Search name or email..."
              class="flex-1 min-w-[200px] border border-slate-300 rounded-md px-3 py-1.5 text-sm" />
            <details class="relative">
              <summary class="cursor-pointer list-none text-xs px-3 py-1.5 border border-slate-300 rounded-md hover:bg-slate-50">
                Add by department
              </summary>
              <div class="absolute right-0 mt-1 w-56 bg-white border border-slate-200 rounded-md shadow-lg z-10 max-h-60 overflow-auto">
                <button v-for="d in departments" :key="d.id" type="button" @click="addAllBy('department', d.id)"
                  class="w-full text-left px-3 py-2 text-sm hover:bg-slate-50">{{ d.name }}</button>
                <div v-if="!departments.length" class="px-3 py-2 text-sm text-slate-500">No departments</div>
              </div>
            </details>
            <details class="relative">
              <summary class="cursor-pointer list-none text-xs px-3 py-1.5 border border-slate-300 rounded-md hover:bg-slate-50">
                Add by location
              </summary>
              <div class="absolute right-0 mt-1 w-56 bg-white border border-slate-200 rounded-md shadow-lg z-10 max-h-60 overflow-auto">
                <button v-for="l in locations" :key="l.id" type="button" @click="addAllBy('location', l.id)"
                  class="w-full text-left px-3 py-2 text-sm hover:bg-slate-50">{{ l.name }}<span v-if="l.city" class="text-slate-400"> · {{ l.city }}</span></button>
                <div v-if="!locations.length" class="px-3 py-2 text-sm text-slate-500">No locations</div>
              </div>
            </details>
          </div>

          <div class="border border-slate-200 rounded-lg max-h-72 overflow-auto divide-y divide-slate-100">
            <label v-for="s in filteredStaff" :key="s.id"
              class="flex items-center gap-3 px-4 py-2 text-sm hover:bg-slate-50 cursor-pointer">
              <input type="checkbox" :checked="memberIds.has(s.id)" @change="toggleMember(s.id)" class="rounded" />
              <div class="flex-1">
                <div class="font-medium text-slate-900">{{ s.full_name }}</div>
                <div class="text-xs text-slate-500">{{ s.email }}</div>
              </div>
            </label>
            <div v-if="filteredStaff.length === 0" class="px-4 py-6 text-sm text-slate-500 text-center">No staff matches.</div>
          </div>
        </div>
      </div>
    </section>

    <section v-else class="bg-white border border-dashed border-slate-300 rounded-xl p-10 text-center text-sm text-slate-500">
      Select a template on the left, or create one. Organization defaults apply to everyone; department and location templates override for their group. A per-staff schedule (set in the Schedules tab) overrides templates.
    </section>
  </div>
</template>
