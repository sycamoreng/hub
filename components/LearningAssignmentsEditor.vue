<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

interface Assignment {
  id: string
  step_id: string
  scope_type: 'user' | 'department' | 'organization'
  scope_id: string | null
  due_date: string | null
  created_at: string
}

interface Dept { id: string; name: string }
interface StaffRef { id: string; auth_user_id: string | null; full_name: string; email: string }

const props = defineProps<{ open: boolean; stepId: string | null; stepTitle: string }>()
const emit = defineEmits<{ (e: 'close'): void }>()

const supabase = useSupabase()
const toast = useToast()

const assignments = ref<Assignment[]>([])
const departments = ref<Dept[]>([])
const staff = ref<StaffRef[]>([])
const loading = ref(false)
const saving = ref(false)

const scopeType = ref<'user' | 'department' | 'organization'>('organization')
const scopeId = ref<string>('')
const userIds = ref<string[]>([])
const userPick = ref<string>('')
const dueDate = ref<string>('')

async function loadAll() {
  if (!props.stepId) return
  loading.value = true
  try {
    const [{ data: a }, { data: d }, { data: s }] = await Promise.all([
      supabase
        .from('learning_assignments')
        .select('*')
        .eq('step_id', props.stepId)
        .order('created_at', { ascending: false }),
      supabase.from('departments').select('id, name').order('name'),
      supabase
        .from('staff_members')
        .select('id, auth_user_id, full_name, email')
        .eq('is_active', true)
        .order('full_name')
    ])
    assignments.value = (a ?? []) as Assignment[]
    departments.value = (d ?? []) as Dept[]
    staff.value = ((s ?? []) as StaffRef[]).filter(x => x.auth_user_id)
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to load assignments')
  } finally {
    loading.value = false
  }
}

watch(() => [props.open, props.stepId], () => {
  if (props.open) {
    scopeType.value = 'organization'
    scopeId.value = ''
    userIds.value = []
    userPick.value = ''
    dueDate.value = ''
    loadAll()
  }
})

const deptName = computed(() => new Map(departments.value.map(d => [d.id, d.name])))
const staffByAuth = computed(() => new Map(staff.value.map(s => [s.auth_user_id as string, s])))

function scopeLabel(a: Assignment) {
  if (a.scope_type === 'organization') return 'Entire organization'
  if (a.scope_type === 'department') return `Department: ${deptName.value.get(a.scope_id ?? '') ?? 'Unknown'}`
  const st = staffByAuth.value.get(a.scope_id ?? '')
  return `User: ${st ? (st.full_name || st.email) : 'Unknown'}`
}

function addUserPick() {
  const id = userPick.value
  if (!id) return
  if (!userIds.value.includes(id)) userIds.value = [...userIds.value, id]
  userPick.value = ''
}

function removeUserPick(id: string) {
  userIds.value = userIds.value.filter(x => x !== id)
}

const availableStaff = computed(() => staff.value.filter(s => !userIds.value.includes(s.auth_user_id as string)))

async function add() {
  if (!props.stepId) return
  const due = dueDate.value || null
  let rows: Array<Record<string, any>> = []

  if (scopeType.value === 'organization') {
    rows = [{ step_id: props.stepId, scope_type: 'organization', scope_id: null, due_date: due }]
  } else if (scopeType.value === 'department') {
    if (!scopeId.value) { toast.error('Pick a department'); return }
    rows = [{ step_id: props.stepId, scope_type: 'department', scope_id: scopeId.value, due_date: due }]
  } else {
    if (userIds.value.length === 0) { toast.error('Pick at least one user'); return }
    rows = userIds.value.map(id => ({ step_id: props.stepId, scope_type: 'user', scope_id: id, due_date: due }))
  }

  saving.value = true
  try {
    const { error } = await supabase.from('learning_assignments').insert(rows)
    if (error) throw error
    toast.success(rows.length > 1 ? `Assigned to ${rows.length} users` : 'Assigned')
    scopeId.value = ''
    userIds.value = []
    userPick.value = ''
    dueDate.value = ''
    await loadAll()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to assign')
  } finally {
    saving.value = false
  }
}

async function remove(a: Assignment) {
  const ok = await toast.confirm({ title: 'Remove assignment', message: `Remove "${scopeLabel(a)}"?`, variant: 'danger', confirmLabel: 'Remove' })
  if (!ok) return
  try {
    const { error } = await supabase.from('learning_assignments').delete().eq('id', a.id)
    if (error) throw error
    toast.success('Removed')
    await loadAll()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to remove')
  }
}
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
        <div class="bg-white rounded-2xl shadow-xl max-w-2xl w-full max-h-[90vh] flex flex-col">
          <header class="flex items-center justify-between p-6 border-b border-slate-100">
            <div class="min-w-0">
              <h2 class="text-xl font-bold text-slate-900 truncate">Assignments</h2>
              <p class="text-xs text-slate-500 mt-0.5 truncate">{{ stepTitle }}</p>
            </div>
            <button class="p-2 rounded-lg hover:bg-slate-100" @click="emit('close')" aria-label="Close">
              <SidebarIcon name="close" />
            </button>
          </header>

          <div class="flex-1 overflow-y-auto">
            <div class="p-6 border-b border-slate-100 bg-slate-50/40">
              <h3 class="text-sm font-semibold text-slate-900 mb-3">New assignment</h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Assign to</label>
                  <select v-model="scopeType" class="input">
                    <option value="organization">Entire organization</option>
                    <option value="department">A department</option>
                    <option value="user">A specific user</option>
                  </select>
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-700 mb-1">Due date (optional)</label>
                  <input v-model="dueDate" type="date" class="input" />
                </div>
                <div v-if="scopeType === 'department'" class="sm:col-span-2">
                  <label class="block text-xs font-medium text-slate-700 mb-1">Department</label>
                  <select v-model="scopeId" class="input">
                    <option value="">Select a department...</option>
                    <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
                  </select>
                </div>
                <div v-else-if="scopeType === 'user'" class="sm:col-span-2">
                  <label class="block text-xs font-medium text-slate-700 mb-1">
                    Users <span class="text-slate-400 font-normal">(add one or more)</span>
                  </label>
                  <div class="flex gap-2">
                    <select v-model="userPick" class="input flex-1" @change="addUserPick">
                      <option value="">Add a user...</option>
                      <option v-for="u in availableStaff" :key="u.auth_user_id!" :value="u.auth_user_id">
                        {{ u.full_name || u.email }}
                      </option>
                    </select>
                  </div>
                  <div v-if="userIds.length" class="flex flex-wrap gap-2 mt-2">
                    <span
                      v-for="id in userIds"
                      :key="id"
                      class="inline-flex items-center gap-1.5 text-xs bg-sycamore-100 text-sycamore-800 px-2 py-1 rounded-full"
                    >
                      {{ staffByAuth.get(id)?.full_name || staffByAuth.get(id)?.email || 'User' }}
                      <button type="button" class="hover:text-sycamore-900" @click="removeUserPick(id)" aria-label="Remove">
                        <svg xmlns="http://www.w3.org/2000/svg" class="w-3 h-3" viewBox="0 0 20 20" fill="currentColor">
                          <path fill-rule="evenodd" d="M4.3 4.3a1 1 0 0 1 1.4 0L10 8.6l4.3-4.3a1 1 0 1 1 1.4 1.4L11.4 10l4.3 4.3a1 1 0 0 1-1.4 1.4L10 11.4l-4.3 4.3a1 1 0 0 1-1.4-1.4L8.6 10 4.3 5.7a1 1 0 0 1 0-1.4Z" clip-rule="evenodd" />
                        </svg>
                      </button>
                    </span>
                  </div>
                </div>
              </div>
              <div class="flex items-center justify-end gap-2 mt-4">
                <button type="button" class="btn-primary" :disabled="saving" @click="add">
                  {{ saving ? 'Saving...' : 'Add assignment' }}
                </button>
              </div>
            </div>

            <div class="p-6">
              <h3 class="text-sm font-semibold text-slate-900 mb-3">Current assignments</h3>
              <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
              <div v-else-if="assignments.length === 0" class="text-sm text-slate-400">
                No assignments yet. This lesson will not appear in any learner's path.
              </div>
              <ul v-else class="space-y-2">
                <li v-for="a in assignments" :key="a.id" class="flex items-start gap-3 p-3 rounded-lg border border-slate-200">
                  <span
                    class="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded mt-0.5"
                    :class="{
                      'bg-sycamore-100 text-sycamore-700': a.scope_type === 'organization',
                      'bg-leaf-100 text-leaf-700': a.scope_type === 'department',
                      'bg-amber-100 text-amber-700': a.scope_type === 'user'
                    }"
                  >{{ a.scope_type }}</span>
                  <div class="min-w-0 flex-1">
                    <div class="text-sm font-medium text-slate-900 truncate">{{ scopeLabel(a) }}</div>
                    <div v-if="a.due_date" class="text-xs text-slate-500 mt-0.5">Due {{ a.due_date }}</div>
                  </div>
                  <button type="button" class="p-1.5 rounded hover:bg-rose-50 text-rose-600 flex-shrink-0" @click="remove(a)" aria-label="Remove">
                    <SidebarIcon name="trash" />
                  </button>
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
