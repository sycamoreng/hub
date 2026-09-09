<script setup lang="ts">
import type { Survey, AudienceType, DepartmentOption, StaffOption } from '~/composables/useSurveys'

definePageMeta({ layout: 'admin', title: 'Surveys' })

const { user, ready, canManageSection, canPerform } = useAuth()
const { success, error: toastError, confirm } = useToast()
const { log } = useAuditLog()
const { loadSurveys, createSurvey, updateSurvey, deleteSurvey, loadDepartments, loadStaff } = useSurveys()

const canManage = computed(() => canManageSection('surveys'))
const canCreate = computed(() => canPerform('surveys', 'create'))
const canDelete = computed(() => canPerform('surveys', 'delete'))

const surveys = ref<Survey[]>([])
const departments = ref<DepartmentOption[]>([])
const staff = ref<StaffOption[]>([])
const loading = ref(true)

const showCreate = ref(false)
const form = reactive({
  title: '', description: '', is_anonymous: false, closes_at: '',
  audience_type: 'all' as AudienceType,
  audience_department_ids: [] as string[],
  audience_staff_ids: [] as string[]
})
const saving = ref(false)

async function load() {
  loading.value = true
  try {
    surveys.value = await loadSurveys()
    if (departments.value.length === 0) departments.value = await loadDepartments()
    if (staff.value.length === 0) staff.value = await loadStaff()
  } catch {
    surveys.value = []
  }
  loading.value = false
}

function openCreate() {
  form.title = ''
  form.description = ''
  form.is_anonymous = false
  form.closes_at = ''
  form.audience_type = 'all'
  form.audience_department_ids = []
  form.audience_staff_ids = []
  showCreate.value = true
}

const audienceInvalid = computed(() =>
  (form.audience_type === 'departments' && form.audience_department_ids.length === 0) ||
  (form.audience_type === 'staff' && form.audience_staff_ids.length === 0)
)

async function create() {
  if (!form.title.trim()) return
  if (audienceInvalid.value) {
    toastError('Pick at least one department or person for the chosen audience')
    return
  }
  saving.value = true
  try {
    const survey = await createSurvey({
      title: form.title.trim(),
      description: form.description.trim(),
      is_anonymous: form.is_anonymous,
      closes_at: form.closes_at ? new Date(form.closes_at).toISOString() : null,
      created_by: user.value?.id ?? null,
      audience_type: form.audience_type,
      audience_department_ids: form.audience_type === 'departments' ? form.audience_department_ids : [],
      audience_staff_ids: form.audience_type === 'staff' ? form.audience_staff_ids : []
    })
    await log({ action: 'create', target_type: 'survey', target_id: survey.id, target_label: survey.title })
    success('Survey created. Add questions next.')
    showCreate.value = false
    navigateTo(`/admin/surveys/${survey.id}`)
  } catch {
    toastError('Could not create the survey')
  }
  saving.value = false
}

async function setStatus(s: Survey, status: Survey['status']) {
  try {
    await updateSurvey(s.id, { status })
    s.status = status
    await log({ action: 'update', target_type: 'survey', target_id: s.id, target_label: `${s.title} -> ${status}` })
    success(status === 'open' ? 'Survey is now open' : status === 'closed' ? 'Survey closed' : 'Survey moved to draft')
  } catch {
    toastError('Could not update the survey')
  }
}

async function remove(s: Survey) {
  const ok = await confirm({
    title: 'Delete survey?',
    message: `This permanently removes "${s.title}" and all its responses.`,
    variant: 'danger',
    confirmLabel: 'Delete'
  })
  if (!ok) return
  try {
    await deleteSurvey(s.id)
    surveys.value = surveys.value.filter(x => x.id !== s.id)
    await log({ action: 'delete', target_type: 'survey', target_id: s.id, target_label: s.title })
    success('Survey deleted')
  } catch {
    toastError('Could not delete the survey')
  }
}

function statusBadge(status: Survey['status']) {
  if (status === 'open') return 'badge-green'
  if (status === 'closed') return 'badge-slate'
  return 'badge-amber'
}

function audienceLabel(s: Survey) {
  if (s.audience_type === 'departments') return `${s.audience_department_ids.length} department(s)`
  if (s.audience_type === 'staff') return `${s.audience_staff_ids.length} person(s)`
  return 'Everyone'
}

watch(ready, (r) => { if (r && canManage.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Surveys</h1>
        <p class="section-subtitle">Create surveys, open them to staff, and review the results</p>
      </div>
      <button v-if="canCreate" @click="openCreate" class="btn-primary">New survey</button>
    </div>

    <div v-if="!canManage" class="card p-8 text-center text-slate-400">
      You do not have access to surveys.
    </div>
    <div v-else-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="surveys.length === 0" class="card p-8 text-center text-slate-400">
      No surveys yet. Create your first one to get started.
    </div>
    <div v-else class="space-y-3">
      <div v-for="s in surveys" :key="s.id" class="card p-5">
        <div class="flex items-start justify-between gap-4">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 flex-wrap">
              <NuxtLink :to="`/admin/surveys/${s.id}`" class="font-semibold text-slate-900 hover:text-sycamore-700">{{ s.title }}</NuxtLink>
              <span class="badge" :class="statusBadge(s.status)">{{ s.status }}</span>
              <span v-if="s.is_anonymous" class="badge badge-slate">Anonymous</span>
              <span class="badge badge-slate">{{ audienceLabel(s) }}</span>
            </div>
            <p v-if="s.description" class="text-sm text-slate-500 mt-1 line-clamp-2">{{ s.description }}</p>
            <p class="text-xs text-slate-400 mt-2">Created {{ new Date(s.created_at).toLocaleDateString() }}</p>
          </div>
        </div>
        <div class="flex items-center gap-2 mt-4 flex-wrap">
          <NuxtLink :to="`/admin/surveys/${s.id}`" class="btn-secondary">Manage &amp; results</NuxtLink>
          <button v-if="s.status !== 'open'" @click="setStatus(s, 'open')" class="btn-secondary">Open</button>
          <button v-if="s.status === 'open'" @click="setStatus(s, 'closed')" class="btn-secondary">Close</button>
          <button v-if="s.status === 'closed'" @click="setStatus(s, 'draft')" class="btn-secondary">Reopen as draft</button>
          <button v-if="canDelete" @click="remove(s)" class="text-sm text-rose-600 hover:text-rose-700 px-3 py-2">Delete</button>
        </div>
      </div>
    </div>

    <!-- create modal -->
    <div v-if="showCreate" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showCreate = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6 max-h-[90vh] overflow-y-auto">
        <h2 class="text-lg font-bold text-slate-900 mb-4">New survey</h2>
        <div class="space-y-3">
          <div>
            <label class="block text-sm font-medium text-slate-600 mb-1">Title</label>
            <input v-model="form.title" class="input" placeholder="e.g. Rate the departments" maxlength="200">
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-600 mb-1">Description (optional)</label>
            <textarea v-model="form.description" class="input min-h-[80px]" placeholder="Add any instructions for respondents" maxlength="1000" />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-600 mb-1">Closes on (optional)</label>
            <input v-model="form.closes_at" type="date" class="input">
          </div>
          <label class="flex items-center gap-2 text-sm text-slate-600">
            <input type="checkbox" v-model="form.is_anonymous" class="rounded border-slate-300">
            Anonymous — hide who answered in the results
          </label>
          <SurveyAudience
            :departments="departments"
            :staff="staff"
            v-model:audience-type="form.audience_type"
            v-model:department-ids="form.audience_department_ids"
            v-model:staff-ids="form.audience_staff_ids"
          />
        </div>
        <div class="flex justify-end gap-2 mt-5">
          <button @click="showCreate = false" class="btn-secondary">Cancel</button>
          <button @click="create" :disabled="!form.title.trim() || saving" class="btn-primary">
            {{ saving ? 'Creating...' : 'Create' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
