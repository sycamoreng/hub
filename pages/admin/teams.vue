<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { items, loading, load, remove } = useCrud('teams')
const toast = useToast()
const { log: auditLog } = useAuditLog()
const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const departments = ref<any[]>([])
const staff = ref<any[]>([])

const form = ref({
  name: '',
  description: '',
  department_id: '',
  lead_staff_id: '',
  display_order: 0,
  member_ids: [] as string[],
  make_lead_manager: false
})
const memberSearch = ref('')

async function reloadAll() {
  await Promise.all([
    load([{ column: 'name', ascending: true }]),
    (async () => { const { data } = await supabase.from('departments').select('id, name').order('name'); departments.value = data ?? [] })(),
    (async () => { const { data } = await supabase.from('staff_members').select('id, full_name, role, department_id, team_id, manager_id, is_active').eq('is_active', true).order('full_name'); staff.value = data ?? [] })()
  ])
}
await reloadAll()

const columns = [
  { key: 'name', label: 'Team' },
  { key: 'department_id', label: 'Department', render: (r: any) => departments.value.find(d => d.id === r.department_id)?.name || '—' },
  { key: 'lead_staff_id', label: 'Lead', render: (r: any) => staff.value.find(s => s.id === r.lead_staff_id)?.full_name || '—' },
  { key: 'members', label: 'Members', render: (r: any) => staff.value.filter(s => s.team_id === r.id).length }
]

function openNew() {
  editing.value = null
  form.value = { name: '', description: '', department_id: '', lead_staff_id: '', display_order: 0, member_ids: [], make_lead_manager: false }
  memberSearch.value = ''
  editorOpen.value = true
}

function openEdit(row: any) {
  editing.value = row
  form.value = {
    name: row.name ?? '',
    description: row.description ?? '',
    department_id: row.department_id ?? '',
    lead_staff_id: row.lead_staff_id ?? '',
    display_order: row.display_order ?? 0,
    member_ids: staff.value.filter(s => s.team_id === row.id).map(s => s.id),
    make_lead_manager: false
  }
  memberSearch.value = ''
  editorOpen.value = true
}

const candidateStaff = computed(() => {
  const deptId = form.value.department_id
  const q = memberSearch.value.trim().toLowerCase()
  return staff.value.filter(s => {
    if (deptId && s.department_id !== deptId) return false
    if (!q) return true
    return (s.full_name || '').toLowerCase().includes(q) || (s.role || '').toLowerCase().includes(q)
  })
})

function toggleMember(id: string) {
  const ids = new Set(form.value.member_ids)
  if (ids.has(id)) ids.delete(id); else ids.add(id)
  form.value.member_ids = Array.from(ids)
}

function toggleSelectAllVisible() {
  const visibleIds = candidateStaff.value.map(s => s.id)
  const current = new Set(form.value.member_ids)
  const allSelected = visibleIds.every(id => current.has(id))
  if (allSelected) visibleIds.forEach(id => current.delete(id))
  else visibleIds.forEach(id => current.add(id))
  form.value.member_ids = Array.from(current)
}

async function save() {
  if (!form.value.name.trim()) { toast.error('Team name is required'); return }
  if (!form.value.department_id) { toast.error('Department is required'); return }
  saving.value = true
  try {
    let teamId = editing.value?.id
    const payload = {
      name: form.value.name.trim(),
      description: form.value.description ?? '',
      department_id: form.value.department_id,
      lead_staff_id: form.value.lead_staff_id || null,
      display_order: Number(form.value.display_order) || 0,
      updated_at: new Date().toISOString()
    }
    if (teamId) {
      const { error } = await supabase.from('teams').update(payload).eq('id', teamId)
      if (error) throw error
    } else {
      const { data, error } = await supabase.from('teams').insert(payload).select('id').maybeSingle()
      if (error) throw error
      teamId = data?.id
    }
    if (!teamId) throw new Error('Could not save team')

    const desiredMembers = new Set(form.value.member_ids)
    const currentMembers = staff.value.filter(s => s.team_id === teamId).map(s => s.id)
    const toAdd = form.value.member_ids.filter(id => !currentMembers.includes(id))
    const toRemove = currentMembers.filter(id => !desiredMembers.has(id))

    if (toAdd.length) {
      const update: any = { team_id: teamId }
      const { error } = await supabase.from('staff_members').update(update).in('id', toAdd)
      if (error) throw error
    }
    if (toRemove.length) {
      const { error } = await supabase.from('staff_members').update({ team_id: null }).in('id', toRemove)
      if (error) throw error
    }
    if (form.value.make_lead_manager && form.value.lead_staff_id) {
      const reportIds = form.value.member_ids.filter(id => id !== form.value.lead_staff_id)
      if (reportIds.length) {
        const { error } = await supabase.from('staff_members').update({ manager_id: form.value.lead_staff_id }).in('id', reportIds)
        if (error) throw error
      }
    }

    auditLog({ action: editing.value ? 'update' : 'create', target_type: 'team', target_id: teamId, target_label: payload.name })
    await reloadAll()
    editorOpen.value = false
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete team "${row.name}"? Members will be unassigned from the team.`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id); auditLog({ action: 'delete', target_type: 'team', target_id: row.id, target_label: row.name }); await reloadAll(); toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}

function initials(name: string) {
  return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0]?.toUpperCase()).join('')
}
</script>

<template>
  <div class="max-w-5xl">
    <AdminList title="Teams" description="Sub-teams under each department. Add the lead, pick members, and you're done." :columns="columns" :rows="items" :loading="loading" new-label="New team" @new="openNew" @edit="openEdit" @delete="del" />

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="editorOpen" class="fixed inset-0 z-50 flex items-start sm:items-center justify-center bg-slate-900/40 p-4 overflow-y-auto">
          <div class="bg-white w-full max-w-2xl rounded-xl shadow-xl my-8">
            <header class="px-6 py-4 border-b border-slate-100 flex items-center justify-between">
              <div>
                <h2 class="text-lg font-semibold text-slate-900">{{ editing ? 'Edit team' : 'New team' }}</h2>
                <p class="text-xs text-slate-500 mt-0.5">Create a team, pick a lead, and add multiple members at once.</p>
              </div>
              <button type="button" @click="editorOpen = false" class="text-slate-400 hover:text-slate-700">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/></svg>
              </button>
            </header>

            <div class="p-6 space-y-5">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <label class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-slate-600">Team name</span>
                  <input v-model="form.name" type="text" class="border border-slate-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sycamore-500" placeholder="e.g. Growth Squad" />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-slate-600">Department</span>
                  <select v-model="form.department_id" class="border border-slate-300 rounded-md px-3 py-2 text-sm bg-white">
                    <option value="">Select department...</option>
                    <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
                  </select>
                </label>
                <label class="flex flex-col gap-1 sm:col-span-2">
                  <span class="text-xs font-medium text-slate-600">Description</span>
                  <textarea v-model="form.description" rows="2" class="border border-slate-300 rounded-md px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
                </label>
                <label class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-slate-600">Team lead</span>
                  <select v-model="form.lead_staff_id" class="border border-slate-300 rounded-md px-3 py-2 text-sm bg-white">
                    <option value="">None</option>
                    <option v-for="s in candidateStaff" :key="s.id" :value="s.id">{{ s.full_name }}{{ s.role ? ' — ' + s.role : '' }}</option>
                  </select>
                </label>
                <label class="flex flex-col gap-1">
                  <span class="text-xs font-medium text-slate-600">Display order</span>
                  <input v-model.number="form.display_order" type="number" class="border border-slate-300 rounded-md px-3 py-2 text-sm" />
                </label>
              </div>

              <section>
                <div class="flex items-center justify-between mb-2">
                  <div class="text-xs font-medium text-slate-600">Members <span class="text-slate-400">({{ form.member_ids.length }} selected)</span></div>
                  <button v-if="candidateStaff.length" type="button" class="text-xs text-sycamore-600 font-medium" @click="toggleSelectAllVisible">
                    {{ candidateStaff.every(s => form.member_ids.includes(s.id)) ? 'Clear visible' : 'Select all visible' }}
                  </button>
                </div>
                <div class="relative mb-2">
                  <input v-model="memberSearch" type="search" placeholder="Search staff..."
                    class="w-full border border-slate-300 rounded-md pl-9 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><path fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 1 0 3.02 10.11l3.68 3.69a.75.75 0 1 0 1.06-1.06l-3.69-3.68A5.5 5.5 0 0 0 9 3.5Zm-4 5.5a4 4 0 1 1 8 0 4 4 0 0 1-8 0Z" clip-rule="evenodd"/></svg>
                </div>
                <div class="border border-slate-200 rounded-lg max-h-64 overflow-y-auto divide-y divide-slate-100">
                  <p v-if="!form.department_id" class="px-4 py-6 text-sm text-slate-400 text-center">Pick a department first to see staff you can add.</p>
                  <p v-else-if="!candidateStaff.length" class="px-4 py-6 text-sm text-slate-400 text-center">No staff match.</p>
                  <label v-for="s in candidateStaff" :key="s.id" class="flex items-center gap-3 px-4 py-2.5 cursor-pointer hover:bg-slate-50">
                    <input type="checkbox" :checked="form.member_ids.includes(s.id)" @change="toggleMember(s.id)" class="rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500" />
                    <div class="w-8 h-8 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center text-xs font-semibold">{{ initials(s.full_name) }}</div>
                    <div class="flex-1 min-w-0">
                      <div class="text-sm font-medium text-slate-900 truncate">{{ s.full_name }}</div>
                      <div class="text-xs text-slate-500 truncate">{{ s.role }}</div>
                    </div>
                    <span v-if="s.team_id && s.team_id !== editing?.id" class="text-[10px] uppercase tracking-wide text-amber-600 bg-amber-50 border border-amber-200 rounded-full px-2 py-0.5">In another team</span>
                    <span v-if="s.id === form.lead_staff_id" class="text-[10px] uppercase tracking-wide text-sycamore-700 bg-sycamore-50 border border-sycamore-200 rounded-full px-2 py-0.5">Lead</span>
                  </label>
                </div>
              </section>

              <label v-if="form.lead_staff_id" class="flex items-start gap-2 text-sm text-slate-600">
                <input v-model="form.make_lead_manager" type="checkbox" class="mt-0.5 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500" />
                <span>Set the team lead as manager for every other member.</span>
              </label>
            </div>

            <footer class="px-6 py-4 border-t border-slate-100 flex items-center justify-end gap-3">
              <button type="button" @click="editorOpen = false" class="px-4 py-2 text-sm text-slate-600 hover:text-slate-900">Cancel</button>
              <button type="button" :disabled="saving" @click="save" class="px-4 py-2 text-sm font-medium text-white bg-sycamore-600 hover:bg-sycamore-700 rounded-md disabled:opacity-50">
                {{ saving ? 'Saving...' : (editing ? 'Save changes' : 'Create team') }}
              </button>
            </footer>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.15s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
