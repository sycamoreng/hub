<script setup lang="ts">
import type { Survey, SurveyQuestion, SurveyAnswerInput, DepartmentOption } from '~/composables/useSurveys'

definePageMeta({ title: 'Survey' })

const route = useRoute()
const router = useRouter()
const { ready } = useAuth()
const { success, error: toastError } = useToast()
const {
  loadSurvey, loadQuestions, loadDepartments, getMyDepartmentId,
  loadMyResponses, submitResponse
} = useSurveys()

const surveyId = route.params.id as string

const survey = ref<Survey | null>(null)
const questions = ref<SurveyQuestion[]>([])
const departments = ref<DepartmentOption[]>([])
const myDeptId = ref<string | null>(null)
const alreadyDone = ref(false)
const loading = ref(true)
const submitting = ref(false)

// answer state keyed by question id
const ratingAns = reactive<Record<string, number | null>>({})
const choiceAns = reactive<Record<string, string | null>>({})
const multiAns = reactive<Record<string, string[]>>({})
const textAns = reactive<Record<string, string>>({})
// department_rating: questionId -> { deptId: rating }
const deptAns = reactive<Record<string, Record<string, number | null>>>({})

function ratableFor(q: SurveyQuestion): DepartmentOption[] {
  const excluded = new Set(q.excluded_department_ids ?? [])
  return departments.value.filter(d => d.id !== myDeptId.value && !excluded.has(d.id))
}

async function load() {
  loading.value = true
  try {
    survey.value = await loadSurvey(surveyId)
    if (!survey.value) { loading.value = false; return }
    questions.value = await loadQuestions(surveyId)
    departments.value = await loadDepartments()
    myDeptId.value = await getMyDepartmentId()
    const done = await loadMyResponses()
    alreadyDone.value = done.has(surveyId)
    for (const q of questions.value) {
      if (q.type === 'rating' || q.type === 'department_rating') ratingAns[q.id] = null
      if (q.type === 'single_choice') choiceAns[q.id] = null
      if (q.type === 'multiple_choice') multiAns[q.id] = []
      if (q.type === 'text') textAns[q.id] = ''
      if (q.type === 'department_rating') {
        deptAns[q.id] = {}
        for (const d of ratableFor(q)) deptAns[q.id][d.id] = null
      }
    }
  } catch {
    survey.value = null
  }
  loading.value = false
}

function toggleMulti(qid: string, option: string) {
  const arr = multiAns[qid] ?? []
  const i = arr.indexOf(option)
  if (i >= 0) arr.splice(i, 1)
  else arr.push(option)
  multiAns[qid] = [...arr]
}

function questionAnswered(q: SurveyQuestion): boolean {
  if (q.type === 'rating') return ratingAns[q.id] != null
  if (q.type === 'single_choice') return !!choiceAns[q.id]
  if (q.type === 'multiple_choice') return (multiAns[q.id] ?? []).length > 0
  if (q.type === 'text') return (textAns[q.id] ?? '').trim().length > 0
  if (q.type === 'department_rating') {
    return ratableFor(q).every(d => deptAns[q.id]?.[d.id] != null)
  }
  return true
}

const missingRequired = computed(() =>
  questions.value.filter(q => q.required && !questionAnswered(q))
)

async function submit() {
  if (!survey.value) return
  if (missingRequired.value.length > 0) {
    toastError('Please answer all required questions before submitting')
    return
  }
  submitting.value = true
  const answers: SurveyAnswerInput[] = []
  for (const q of questions.value) {
    if (q.type === 'rating' && ratingAns[q.id] != null) {
      answers.push({ question_id: q.id, rating: ratingAns[q.id] })
    } else if (q.type === 'single_choice' && choiceAns[q.id]) {
      answers.push({ question_id: q.id, choice: choiceAns[q.id] })
    } else if (q.type === 'multiple_choice' && (multiAns[q.id] ?? []).length) {
      answers.push({ question_id: q.id, choices: multiAns[q.id] })
    } else if (q.type === 'text' && (textAns[q.id] ?? '').trim()) {
      answers.push({ question_id: q.id, text_answer: textAns[q.id].trim() })
    } else if (q.type === 'department_rating') {
      for (const d of ratableFor(q)) {
        const val = deptAns[q.id]?.[d.id]
        if (val != null) {
          answers.push({ question_id: q.id, subject_department_id: d.id, rating: val })
        }
      }
    }
  }
  try {
    await submitResponse(surveyId, answers)
    success('Thanks! Your response has been recorded.')
    router.push('/surveys')
  } catch (e: any) {
    if (String(e?.message ?? e).includes('duplicate')) {
      toastError('You have already completed this survey')
    } else {
      toastError('Could not submit your response. Please try again.')
    }
  }
  submitting.value = false
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-2xl mx-auto px-4 py-8">
    <NuxtLink to="/surveys" class="text-sm text-sycamore-700 hover:underline">&larr; Back to surveys</NuxtLink>

    <div v-if="loading" class="card p-8 text-center text-slate-400 mt-4">Loading...</div>

    <div v-else-if="!survey" class="card p-8 text-center text-slate-400 mt-4">
      This survey could not be found or is no longer available.
    </div>

    <div v-else-if="survey.status !== 'open'" class="card p-8 text-center text-slate-500 mt-4">
      This survey is closed and no longer accepting responses.
    </div>

    <template v-else>
      <div class="mt-4 mb-6">
        <h1 class="section-title">{{ survey.title }}</h1>
        <p v-if="survey.description" class="section-subtitle">{{ survey.description }}</p>
        <span v-if="survey.is_anonymous" class="badge badge-slate mt-2 inline-block">Your answers are anonymous</span>
      </div>

      <div v-if="alreadyDone" class="card p-6 text-center">
        <p class="text-slate-700 font-medium">You have already completed this survey.</p>
        <p class="text-sm text-slate-400 mt-1">Thank you for your feedback.</p>
      </div>

      <form v-else @submit.prevent="submit" class="space-y-4">
        <div v-for="(q, idx) in questions" :key="q.id" class="card p-5">
          <p class="font-medium text-slate-900">
            <span class="text-slate-400 mr-1">{{ idx + 1 }}.</span>{{ q.prompt }}
            <span v-if="q.required" class="text-rose-500">*</span>
          </p>

          <!-- rating -->
          <div v-if="q.type === 'rating'" class="flex gap-2 mt-3 flex-wrap">
            <button
              v-for="n in q.scale_max" :key="n" type="button"
              @click="ratingAns[q.id] = n"
              class="w-10 h-10 rounded-lg text-sm font-semibold border transition-colors"
              :class="ratingAns[q.id] === n ? 'bg-sycamore-600 text-white border-sycamore-600' : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'"
            >{{ n }}</button>
          </div>

          <!-- single choice -->
          <div v-else-if="q.type === 'single_choice'" class="mt-3 space-y-2">
            <label v-for="opt in q.options" :key="opt" class="flex items-center gap-2 text-sm text-slate-700">
              <input type="radio" :name="`q-${q.id}`" :value="opt" v-model="choiceAns[q.id]" class="border-slate-300 text-sycamore-600">
              {{ opt }}
            </label>
          </div>

          <!-- multiple choice -->
          <div v-else-if="q.type === 'multiple_choice'" class="mt-3 space-y-2">
            <label v-for="opt in q.options" :key="opt" class="flex items-center gap-2 text-sm text-slate-700">
              <input type="checkbox" :checked="(multiAns[q.id] ?? []).includes(opt)" @change="toggleMulti(q.id, opt)" class="rounded border-slate-300 text-sycamore-600">
              {{ opt }}
            </label>
          </div>

          <!-- text -->
          <textarea v-else-if="q.type === 'text'" v-model="textAns[q.id]" class="input min-h-[90px] mt-3" placeholder="Your answer" maxlength="2000" />

          <!-- department rating -->
          <div v-else-if="q.type === 'department_rating'" class="mt-3 space-y-3">
            <p class="text-xs text-slate-400">Rate each department below. You will not see your own department.</p>
            <div v-if="ratableFor(q).length === 0" class="text-sm text-slate-400">No other departments available to rate.</div>
            <div v-for="d in ratableFor(q)" :key="d.id" class="flex items-center justify-between gap-3 border-t border-slate-100 pt-2 first:border-t-0 first:pt-0">
              <span class="text-sm text-slate-700">{{ d.name }}</span>
              <div class="flex gap-1">
                <button
                  v-for="n in q.scale_max" :key="n" type="button"
                  @click="deptAns[q.id][d.id] = n"
                  class="w-8 h-8 rounded-md text-xs font-semibold border transition-colors"
                  :class="deptAns[q.id]?.[d.id] === n ? 'bg-sycamore-600 text-white border-sycamore-600' : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'"
                >{{ n }}</button>
              </div>
            </div>
          </div>
        </div>

        <div class="flex items-center justify-between gap-3">
          <p v-if="missingRequired.length > 0" class="text-xs text-slate-400">
            {{ missingRequired.length }} required question{{ missingRequired.length > 1 ? 's' : '' }} left
          </p>
          <button type="submit" :disabled="submitting" class="btn-primary ml-auto">
            {{ submitting ? 'Submitting...' : 'Submit response' }}
          </button>
        </div>
      </form>
    </template>
  </div>
</template>
