<script setup lang="ts">
import type { Survey, SurveyQuestion, QuestionType, DepartmentOption, StaffOption, AudienceType } from '~/composables/useSurveys'

definePageMeta({ layout: 'admin', title: 'Survey' })

const route = useRoute()
const { ready, canManageSection, canPerform } = useAuth()
const { success, error: toastError, confirm } = useToast()
const { log } = useAuditLog()
const {
  loadSurvey, loadQuestions, addQuestion, deleteQuestion, updateSurvey,
  loadDepartments, loadStaff, loadResults
} = useSurveys()

const surveyId = route.params.id as string

const canManage = computed(() => canManageSection('surveys'))
const canCreate = computed(() => canPerform('surveys', 'create'))
const canDelete = computed(() => canPerform('surveys', 'delete'))

const survey = ref<Survey | null>(null)
const questions = ref<SurveyQuestion[]>([])
const departments = ref<DepartmentOption[]>([])
const staff = ref<StaffOption[]>([])
const loading = ref(true)
const tab = ref<'questions' | 'audience' | 'results'>('questions')

// new question form
const nq = reactive<{ prompt: string; type: QuestionType; optionsText: string; scale_max: number; required: boolean; excluded: string[] }>({
  prompt: '', type: 'rating', optionsText: '', scale_max: 5, required: true, excluded: []
})
const addingQuestion = ref(false)

// audience editing
const audience = reactive<{ type: AudienceType; departmentIds: string[]; staffIds: string[] }>({
  type: 'all', departmentIds: [], staffIds: []
})
const savingAudience = ref(false)

const shareLink = computed(() => {
  if (typeof window === 'undefined') return `/surveys/${surveyId}`
  return `${window.location.origin}/surveys/${surveyId}`
})
const linkCopied = ref(false)
async function copyLink() {
  try {
    await navigator.clipboard.writeText(shareLink.value)
    linkCopied.value = true
    setTimeout(() => { linkCopied.value = false }, 2000)
  } catch {
    toastError('Could not copy the link')
  }
}

const typeLabels: Record<QuestionType, string> = {
  rating: 'Rating scale',
  department_rating: 'Rate every department (excludes each person\u2019s own)',
  single_choice: 'Single choice',
  multiple_choice: 'Multiple choice',
  text: 'Free text'
}

// results
const results = ref<{ responseCount: number; answers: any[] } | null>(null)
const loadingResults = ref(false)

async function load() {
  loading.value = true
  try {
    survey.value = await loadSurvey(surveyId)
    questions.value = await loadQuestions(surveyId)
    departments.value = await loadDepartments()
    staff.value = await loadStaff()
    if (survey.value) {
      audience.type = survey.value.audience_type
      audience.departmentIds = [...survey.value.audience_department_ids]
      audience.staffIds = [...survey.value.audience_staff_ids]
    }
  } catch {
    survey.value = null
  }
  loading.value = false
}

const audienceInvalid = computed(() =>
  (audience.type === 'departments' && audience.departmentIds.length === 0) ||
  (audience.type === 'staff' && audience.staffIds.length === 0)
)

async function saveAudience() {
  if (!survey.value) return
  if (audienceInvalid.value) {
    toastError('Pick at least one department or person for the chosen audience')
    return
  }
  savingAudience.value = true
  try {
    const payload = {
      audience_type: audience.type,
      audience_department_ids: audience.type === 'departments' ? audience.departmentIds : [],
      audience_staff_ids: audience.type === 'staff' ? audience.staffIds : []
    }
    await updateSurvey(surveyId, payload)
    Object.assign(survey.value, payload)
    await log({ action: 'update', target_type: 'survey', target_id: surveyId, target_label: `${survey.value.title} audience` })
    success('Audience updated')
  } catch {
    toastError('Could not update the audience')
  }
  savingAudience.value = false
}

const deptNameById = computed(() => {
  const m = new Map<string, string>()
  departments.value.forEach(d => m.set(d.id, d.name))
  return m
})

async function addQ() {
  if (!nq.prompt.trim()) return
  const needsOptions = nq.type === 'single_choice' || nq.type === 'multiple_choice'
  const options = needsOptions
    ? nq.optionsText.split('\n').map(o => o.trim()).filter(Boolean)
    : []
  if (needsOptions && options.length < 2) {
    toastError('Add at least two options (one per line)')
    return
  }
  addingQuestion.value = true
  try {
    const created = await addQuestion({
      survey_id: surveyId,
      prompt: nq.prompt.trim(),
      type: nq.type,
      options,
      scale_max: nq.scale_max,
      required: nq.required,
      sort_order: questions.value.length,
      excluded_department_ids: nq.type === 'department_rating' ? nq.excluded : []
    })
    questions.value.push(created)
    nq.prompt = ''
    nq.optionsText = ''
    nq.excluded = []
    success('Question added')
  } catch {
    toastError('Could not add the question')
  }
  addingQuestion.value = false
}

async function removeQ(q: SurveyQuestion) {
  const ok = await confirm({
    title: 'Remove question?',
    message: 'This deletes the question and any answers already given to it.',
    variant: 'danger',
    confirmLabel: 'Remove'
  })
  if (!ok) return
  try {
    await deleteQuestion(q.id)
    questions.value = questions.value.filter(x => x.id !== q.id)
    success('Question removed')
  } catch {
    toastError('Could not remove the question')
  }
}

async function setStatus(status: Survey['status']) {
  if (!survey.value) return
  if (status === 'open' && questions.value.length === 0) {
    toastError('Add at least one question before opening the survey')
    return
  }
  try {
    await updateSurvey(surveyId, { status })
    survey.value.status = status
    await log({ action: 'update', target_type: 'survey', target_id: surveyId, target_label: `${survey.value.title} -> ${status}` })
    success(status === 'open' ? 'Survey is now open to staff' : 'Survey updated')
  } catch {
    toastError('Could not update the survey')
  }
}

async function loadResultData() {
  loadingResults.value = true
  try {
    results.value = await loadResults(surveyId)
  } catch {
    results.value = { responseCount: 0, answers: [] }
  }
  loadingResults.value = false
}

watch(tab, (t) => { if (t === 'results' && !results.value) loadResultData() })

function answersFor(qid: string) {
  return (results.value?.answers ?? []).filter(a => a.question_id === qid)
}

function ratingSummary(qid: string) {
  const vals = answersFor(qid).map(a => a.rating).filter((r): r is number => typeof r === 'number')
  if (vals.length === 0) return { avg: null as number | null, count: 0 }
  return { avg: vals.reduce((s, v) => s + v, 0) / vals.length, count: vals.length }
}

function deptRatingSummary(qid: string) {
  const map = new Map<string, { sum: number; count: number }>()
  for (const a of answersFor(qid)) {
    if (!a.subject_department_id || typeof a.rating !== 'number') continue
    const cur = map.get(a.subject_department_id) ?? { sum: 0, count: 0 }
    cur.sum += a.rating
    cur.count += 1
    map.set(a.subject_department_id, cur)
  }
  return [...map.entries()]
    .map(([id, v]) => ({ id, name: deptNameById.value.get(id) ?? 'Unknown', avg: v.sum / v.count, count: v.count }))
    .sort((a, b) => b.avg - a.avg)
}

function choiceSummary(qid: string, options: string[]) {
  const counts = new Map<string, number>()
  options.forEach(o => counts.set(o, 0))
  for (const a of answersFor(qid)) {
    if (a.choice) counts.set(a.choice, (counts.get(a.choice) ?? 0) + 1)
    if (Array.isArray(a.choices)) a.choices.forEach((c: string) => counts.set(c, (counts.get(c) ?? 0) + 1))
  }
  const total = [...counts.values()].reduce((s, v) => s + v, 0) || 1
  return [...counts.entries()].map(([opt, count]) => ({ opt, count, pct: Math.round((count / total) * 100) }))
}

function textAnswers(qid: string) {
  return answersFor(qid).map(a => a.text_answer).filter((t): t is string => !!t && t.trim().length > 0)
}

watch(ready, (r) => { if (r && canManage.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-3xl mx-auto px-4 py-8">
    <NuxtLink to="/admin/surveys" class="text-sm text-sycamore-700 hover:underline">&larr; All surveys</NuxtLink>

    <div v-if="!canManage" class="card p-8 text-center text-slate-400 mt-4">You do not have access to surveys.</div>
    <div v-else-if="loading" class="card p-8 text-center text-slate-400 mt-4">Loading...</div>
    <div v-else-if="!survey" class="card p-8 text-center text-slate-400 mt-4">Survey not found.</div>

    <template v-else>
      <div class="flex items-start justify-between gap-4 mt-4 mb-5">
        <div>
          <div class="flex items-center gap-2 flex-wrap">
            <h1 class="section-title">{{ survey.title }}</h1>
            <span class="badge" :class="survey.status === 'open' ? 'badge-green' : survey.status === 'closed' ? 'badge-slate' : 'badge-amber'">{{ survey.status }}</span>
          </div>
          <p v-if="survey.description" class="section-subtitle">{{ survey.description }}</p>
        </div>
        <div class="flex gap-2 shrink-0">
          <button v-if="survey.status !== 'open'" @click="setStatus('open')" class="btn-primary">Open</button>
          <button v-if="survey.status === 'open'" @click="setStatus('closed')" class="btn-secondary">Close</button>
        </div>
      </div>

      <!-- SHARE LINK -->
      <div v-if="survey.status !== 'draft'" class="card p-4 mb-5">
        <p class="text-sm font-medium text-slate-600 mb-2">Share link</p>
        <div class="flex items-center gap-2">
          <input :value="shareLink" readonly class="input flex-1 text-sm text-slate-500" @focus="($event.target as HTMLInputElement).select()">
          <button @click="copyLink" class="btn-secondary shrink-0">{{ linkCopied ? 'Copied!' : 'Copy' }}</button>
        </div>
        <p class="text-xs text-slate-400 mt-2">Anyone in the survey's audience can open it with this link.</p>
      </div>

      <div class="flex gap-2 mb-6">
        <button
          v-for="t in (['questions', 'audience', 'results'] as const)" :key="t"
          @click="tab = t"
          class="px-4 py-2 rounded-lg text-sm font-medium transition-colors capitalize"
          :class="tab === t ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
        >{{ t }}</button>
      </div>

      <!-- QUESTIONS TAB -->
      <div v-if="tab === 'questions'" class="space-y-4">
        <div v-if="questions.length === 0" class="card p-6 text-center text-slate-400">No questions yet. Add one below.</div>
        <div v-for="(q, idx) in questions" :key="q.id" class="card p-4">
          <div class="flex items-start justify-between gap-3">
            <div class="flex-1 min-w-0">
              <p class="font-medium text-slate-900"><span class="text-slate-400 mr-1">{{ idx + 1 }}.</span>{{ q.prompt }}</p>
              <div class="flex items-center gap-2 mt-1 text-xs text-slate-400">
                <span>{{ typeLabels[q.type] }}</span>
                <span v-if="q.type === 'rating' || q.type === 'department_rating'">Scale 1&ndash;{{ q.scale_max }}</span>
                <span v-if="q.required" class="text-rose-400">Required</span>
              </div>
              <div v-if="q.options?.length" class="text-xs text-slate-500 mt-2 flex flex-wrap gap-1">
                <span v-for="opt in q.options" :key="opt" class="badge badge-slate">{{ opt }}</span>
              </div>
              <div v-if="q.type === 'department_rating' && q.excluded_department_ids?.length" class="text-xs text-slate-500 mt-2">
                <span class="text-slate-400">Excluded: </span>
                <span v-for="id in q.excluded_department_ids" :key="id" class="badge badge-rose mr-1">{{ deptNameById.get(id) || 'Unknown' }}</span>
              </div>
            </div>
            <button v-if="canDelete" @click="removeQ(q)" class="text-sm text-rose-600 hover:text-rose-700 shrink-0">Remove</button>
          </div>
        </div>

        <!-- add question -->
        <div v-if="canCreate" class="card p-5">
          <h3 class="font-semibold text-slate-900 mb-3">Add a question</h3>
          <div class="space-y-3">
            <div>
              <label class="block text-sm font-medium text-slate-600 mb-1">Question</label>
              <input v-model="nq.prompt" class="input" placeholder="What would you like to ask?" maxlength="400">
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-slate-600 mb-1">Type</label>
                <select v-model="nq.type" class="input">
                  <option v-for="(label, val) in typeLabels" :key="val" :value="val">{{ label }}</option>
                </select>
              </div>
              <div v-if="nq.type === 'rating' || nq.type === 'department_rating'">
                <label class="block text-sm font-medium text-slate-600 mb-1">Top of scale</label>
                <select v-model.number="nq.scale_max" class="input">
                  <option :value="3">1 to 3</option>
                  <option :value="5">1 to 5</option>
                  <option :value="10">1 to 10</option>
                </select>
              </div>
            </div>
            <div v-if="nq.type === 'single_choice' || nq.type === 'multiple_choice'">
              <label class="block text-sm font-medium text-slate-600 mb-1">Options (one per line)</label>
              <textarea v-model="nq.optionsText" class="input min-h-[90px]" placeholder="Option A&#10;Option B&#10;Option C" />
            </div>
            <div v-if="nq.type === 'department_rating'">
              <label class="block text-sm font-medium text-slate-600 mb-1">Exclude departments</label>
              <p class="text-xs text-slate-400 mb-2">Each person never rates their own department. Tick any others to leave out.</p>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5 max-h-48 overflow-y-auto pr-1">
                <label v-for="d in departments" :key="d.id" class="flex items-center gap-2 text-sm text-slate-600">
                  <input type="checkbox" :value="d.id" v-model="nq.excluded" class="rounded border-slate-300">
                  {{ d.name }}
                </label>
              </div>
            </div>
            <label class="flex items-center gap-2 text-sm text-slate-600">
              <input type="checkbox" v-model="nq.required" class="rounded border-slate-300">
              Required
            </label>
            <div class="flex justify-end">
              <button @click="addQ" :disabled="!nq.prompt.trim() || addingQuestion" class="btn-primary">
                {{ addingQuestion ? 'Adding...' : 'Add question' }}
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- AUDIENCE TAB -->
      <div v-else-if="tab === 'audience'" class="space-y-4">
        <div class="card p-5">
          <h3 class="font-semibold text-slate-900 mb-1">Who receives this survey</h3>
          <p class="text-sm text-slate-500 mb-4">Only the people you choose will see it in their surveys list or through the share link.</p>
          <SurveyAudience
            :departments="departments"
            :staff="staff"
            v-model:audience-type="audience.type"
            v-model:department-ids="audience.departmentIds"
            v-model:staff-ids="audience.staffIds"
          />
          <div class="flex justify-end mt-4">
            <button @click="saveAudience" :disabled="savingAudience || audienceInvalid" class="btn-primary">
              {{ savingAudience ? 'Saving...' : 'Save audience' }}
            </button>
          </div>
        </div>
      </div>

      <!-- RESULTS TAB -->
      <div v-else class="space-y-4">
        <div v-if="loadingResults" class="card p-8 text-center text-slate-400">Loading results...</div>
        <template v-else>
          <div class="card p-5">
            <p class="text-sm text-slate-500">Total responses</p>
            <p class="text-3xl font-bold text-slate-900">{{ results?.responseCount ?? 0 }}</p>
          </div>

          <div v-if="questions.length === 0" class="card p-6 text-center text-slate-400">No questions to report on.</div>

          <div v-for="(q, idx) in questions" :key="q.id" class="card p-5">
            <p class="font-medium text-slate-900 mb-3"><span class="text-slate-400 mr-1">{{ idx + 1 }}.</span>{{ q.prompt }}</p>

            <!-- rating -->
            <div v-if="q.type === 'rating'">
              <template v-if="ratingSummary(q.id).count > 0">
                <p class="text-2xl font-bold text-sycamore-700">{{ ratingSummary(q.id).avg!.toFixed(2) }}<span class="text-sm text-slate-400 font-normal"> / {{ q.scale_max }}</span></p>
                <p class="text-xs text-slate-400">{{ ratingSummary(q.id).count }} rating(s)</p>
              </template>
              <p v-else class="text-sm text-slate-400">No answers yet.</p>
            </div>

            <!-- department rating -->
            <div v-else-if="q.type === 'department_rating'">
              <div v-if="deptRatingSummary(q.id).length === 0" class="text-sm text-slate-400">No ratings yet.</div>
              <div v-else class="space-y-2">
                <div v-for="d in deptRatingSummary(q.id)" :key="d.id" class="flex items-center gap-3">
                  <span class="text-sm text-slate-700 w-40 truncate">{{ d.name }}</span>
                  <div class="flex-1 bg-slate-100 rounded-full h-2 overflow-hidden">
                    <div class="bg-sycamore-600 h-2 rounded-full" :style="{ width: `${(d.avg / q.scale_max) * 100}%` }" />
                  </div>
                  <span class="text-sm font-semibold text-slate-900 w-10 text-right">{{ d.avg.toFixed(1) }}</span>
                  <span class="text-xs text-slate-400 w-16 text-right">{{ d.count }} vote(s)</span>
                </div>
              </div>
            </div>

            <!-- choices -->
            <div v-else-if="q.type === 'single_choice' || q.type === 'multiple_choice'" class="space-y-2">
              <div v-for="row in choiceSummary(q.id, q.options)" :key="row.opt" class="flex items-center gap-3">
                <span class="text-sm text-slate-700 w-40 truncate">{{ row.opt }}</span>
                <div class="flex-1 bg-slate-100 rounded-full h-2 overflow-hidden">
                  <div class="bg-sycamore-600 h-2 rounded-full" :style="{ width: `${row.pct}%` }" />
                </div>
                <span class="text-sm font-semibold text-slate-900 w-16 text-right">{{ row.count }} ({{ row.pct }}%)</span>
              </div>
            </div>

            <!-- text -->
            <div v-else-if="q.type === 'text'">
              <div v-if="textAnswers(q.id).length === 0" class="text-sm text-slate-400">No answers yet.</div>
              <ul v-else class="space-y-2">
                <li v-for="(t, i) in textAnswers(q.id)" :key="i" class="text-sm text-slate-700 bg-slate-50 rounded-lg p-3 border border-slate-100">{{ t }}</li>
              </ul>
            </div>
          </div>
        </template>
      </div>
    </template>
  </div>
</template>
