<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { toEmbedUrl } from '~/composables/useVideoEmbed'
import type { LearningPath, QuizQuestion, QuizAttempt } from '~/composables/useLearningPaths'

interface Resource {
  id: string
  step_id: string
  kind: 'video' | 'article' | 'link' | 'file' | 'document' | string
  title: string
  description: string
  url: string
  body: string
  display_order: number
}

interface Step {
  id: string
  title: string
  description: string
  category: string
  resource_url: string
  is_required: boolean
  display_order: number
  is_active: boolean
  content_type: 'task' | 'video' | 'article' | 'module' | string
  body: string
  video_url: string
  cover_image_url: string
  estimated_minutes: number
  path_id: string | null
  quiz_pass_threshold: number
  onboarding_resources: Resource[]
  due_date?: string | null
  scope_types?: string[]
}

const supabase = useSupabase()
const { fetchOnboardingSteps } = useCompanyData()
const { fetchPaths, fetchQuizQuestions, fetchMyAttempts, submitQuiz, isStepUnlocked } = useLearningPaths()
const { user } = useAuth()
const toast = useToast()

const steps = ref<Step[]>([])
const paths = ref<LearningPath[]>([])
const completed = ref<Record<string, boolean>>({})
const loading = ref(true)
const saving = ref<Record<string, boolean>>({})
const expanded = ref<Record<string, boolean>>({})
const quizAttempts = ref<QuizAttempt[]>([])
const quizStepIds = ref<Set<string>>(new Set())

// Quiz modal state
const quizOpen = ref(false)
const quizStep = ref<Step | null>(null)
const quizQuestions = ref<QuizQuestion[]>([])
const quizAnswers = ref<number[]>([])
const quizSubmitting = ref(false)
const quizResult = ref<QuizAttempt | null>(null)
const quizLoading = ref(false)

async function loadAll() {
  loading.value = true
  try {
    const [allSteps, allPaths] = await Promise.all([
      fetchOnboardingSteps() as Promise<Step[]>,
      fetchPaths()
    ])
    paths.value = allPaths

    if (!user.value) {
      steps.value = []
      completed.value = {}
      return
    }

    const [{ data: assignments }, { data: progress }] = await Promise.all([
      supabase.from('learning_assignments').select('step_id, scope_type, due_date'),
      supabase.from('onboarding_progress').select('step_id').eq('user_id', user.value.id)
    ])

    const byStep = new Map<string, { scope_types: Set<string>; due: string | null }>()
    for (const a of (assignments ?? []) as any[]) {
      const entry = byStep.get(a.step_id) ?? { scope_types: new Set<string>(), due: null }
      entry.scope_types.add(a.scope_type)
      if (a.due_date && (!entry.due || a.due_date < entry.due)) entry.due = a.due_date
      byStep.set(a.step_id, entry)
    }

    steps.value = allSteps
      .filter(s => byStep.has(s.id))
      .map(s => {
        const meta = byStep.get(s.id)!
        return { ...s, due_date: meta.due, scope_types: Array.from(meta.scope_types) }
      })

    const map: Record<string, boolean> = {}
    ;(progress ?? []).forEach((r: any) => { map[r.step_id] = true })
    completed.value = map

    // Load quiz data
    const stepIds = steps.value.map(s => s.id)
    const [attempts, { data: quizQs }] = await Promise.all([
      fetchMyAttempts(stepIds),
      supabase.from('step_quiz_questions').select('step_id').in('step_id', stepIds)
    ])
    quizAttempts.value = attempts
    const qsSet = new Set<string>()
    for (const q of quizQs ?? []) qsSet.add((q as any).step_id)
    quizStepIds.value = qsSet
  } finally {
    loading.value = false
  }
}

onMounted(loadAll)
watch(() => user.value?.id, loadAll)

const passedQuizStepIds = computed(() => {
  const set = new Set<string>()
  for (const a of quizAttempts.value) {
    if (a.passed) set.add(a.step_id)
  }
  return set
})

const completedIds = computed(() => {
  const set = new Set<string>()
  for (const [id, done] of Object.entries(completed.value)) {
    if (done) set.add(id)
  }
  return set
})

function checkUnlocked(step: Step): boolean {
  const path = paths.value.find(p => p.id === step.path_id) || null
  if (!path) return true
  const stepsInPath = steps.value
    .filter(s => s.path_id === step.path_id)
    .map(s => ({ id: s.id, display_order: s.display_order }))
  return isStepUnlocked(step.id, path, stepsInPath, completedIds.value, passedQuizStepIds.value, quizStepIds.value)
}

function stepHasQuiz(stepId: string): boolean {
  return quizStepIds.value.has(stepId)
}

function stepQuizPassed(stepId: string): boolean {
  return passedQuizStepIds.value.has(stepId)
}

function bestAttempt(stepId: string): QuizAttempt | undefined {
  return quizAttempts.value.find(a => a.step_id === stepId && a.passed)
    || quizAttempts.value.find(a => a.step_id === stepId)
}

async function toggle(step: Step) {
  if (!user.value) {
    await navigateTo(`/login?redirect=/onboarding`)
    return
  }
  if (!checkUnlocked(step)) {
    toast.error('Complete the previous step first')
    return
  }
  // If step has quiz and not passed yet, require quiz first
  if (stepHasQuiz(step.id) && !stepQuizPassed(step.id) && !completed.value[step.id]) {
    openQuiz(step)
    return
  }

  const isDone = !!completed.value[step.id]
  saving.value[step.id] = true
  try {
    if (isDone) {
      await supabase.from('onboarding_progress').delete().eq('user_id', user.value.id).eq('step_id', step.id)
      completed.value = { ...completed.value, [step.id]: false }
    } else {
      await supabase.from('onboarding_progress').insert({ user_id: user.value.id, step_id: step.id })
      completed.value = { ...completed.value, [step.id]: true }
      try {
        await supabase.from('points_events').upsert({
          user_id: user.value.id,
          event_kind: 'onboarding_step_completed',
          ref_type: 'step',
          ref_id: step.id,
          points: 10
        }, { onConflict: 'user_id,event_kind,ref_type,ref_id', ignoreDuplicates: true })
      } catch { /* non-fatal */ }
      toast.success('Marked complete (+10 points)')
      await checkPathCompletion(step)
    }
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to update progress')
  } finally {
    saving.value[step.id] = false
  }
}

async function checkPathCompletion(step: Step) {
  if (!step.path_id || !user.value) return
  const path = paths.value.find(p => p.id === step.path_id)
  if (!path?.badge_id) return

  const stepsInPath = steps.value.filter(s => s.path_id === step.path_id)
  const allDone = stepsInPath.every(s => completed.value[s.id])
  const allQuizzesPassed = stepsInPath
    .filter(s => quizStepIds.value.has(s.id))
    .every(s => passedQuizStepIds.value.has(s.id))

  if (allDone && allQuizzesPassed) {
    try {
      await supabase.from('user_badges').upsert({
        user_id: user.value.id,
        badge_id: path.badge_id,
        awarded_at: new Date().toISOString()
      }, { onConflict: 'user_id,badge_id', ignoreDuplicates: true })
      toast.success(`Badge unlocked: ${path.name} complete!`)
    } catch { /* non-fatal */ }
  }
}

async function openQuiz(step: Step) {
  quizStep.value = step
  quizResult.value = null
  quizAnswers.value = []
  quizLoading.value = true
  quizOpen.value = true
  quizQuestions.value = await fetchQuizQuestions(step.id)
  quizAnswers.value = new Array(quizQuestions.value.length).fill(-1)
  quizLoading.value = false
}

function closeQuiz() {
  quizOpen.value = false
  quizStep.value = null
  quizQuestions.value = []
  quizAnswers.value = []
  quizResult.value = null
}

async function handleQuizSubmit() {
  if (!quizStep.value) return
  const unanswered = quizAnswers.value.findIndex(a => a === -1)
  if (unanswered !== -1) {
    toast.error(`Please answer question ${unanswered + 1}`)
    return
  }
  quizSubmitting.value = true
  try {
    const result = await submitQuiz(quizStep.value.id, quizAnswers.value)
    quizResult.value = result
    quizAttempts.value = [result, ...quizAttempts.value]

    if (result.passed) {
      // Auto-mark step as complete
      if (!completed.value[quizStep.value.id]) {
        await supabase.from('onboarding_progress').insert({ user_id: user.value!.id, step_id: quizStep.value.id })
        completed.value = { ...completed.value, [quizStep.value.id]: true }
        try {
          await supabase.from('points_events').upsert({
            user_id: user.value!.id,
            event_kind: 'onboarding_step_completed',
            ref_type: 'step',
            ref_id: quizStep.value.id,
            points: 10
          }, { onConflict: 'user_id,event_kind,ref_type,ref_id', ignoreDuplicates: true })
        } catch { /* non-fatal */ }
      }
      await checkPathCompletion(quizStep.value)
    }
  } catch (e: any) {
    toast.error(e.message || 'Failed to submit quiz')
  } finally {
    quizSubmitting.value = false
  }
}

// Grouping: steps in paths first, then ungrouped (by category)
const pathGroups = computed(() => {
  const groups: { path: LearningPath | null; label: string; steps: Step[]; isSequential: boolean; progress: number }[] = []

  for (const path of paths.value) {
    const pathSteps = steps.value
      .filter(s => s.path_id === path.id)
      .sort((a, b) => a.display_order - b.display_order)
    if (pathSteps.length === 0) continue
    const done = pathSteps.filter(s => completed.value[s.id]).length
    groups.push({
      path,
      label: path.name,
      steps: pathSteps,
      isSequential: path.is_sequential,
      progress: pathSteps.length ? Math.round((done / pathSteps.length) * 100) : 0
    })
  }

  // Ungrouped steps (no path_id) grouped by category
  const ungrouped = steps.value.filter(s => !s.path_id)
  const catMap: Record<string, Step[]> = {}
  for (const s of ungrouped) {
    const c = s.category || 'general'
    ;(catMap[c] ||= []).push(s)
  }
  for (const [cat, catSteps] of Object.entries(catMap).sort(([a], [b]) => a.localeCompare(b))) {
    const done = catSteps.filter(s => completed.value[s.id]).length
    groups.push({
      path: null,
      label: cat,
      steps: catSteps,
      isSequential: false,
      progress: catSteps.length ? Math.round((done / catSteps.length) * 100) : 0
    })
  }

  return groups
})

const stats = computed(() => {
  const total = steps.value.length
  const required = steps.value.filter(s => s.is_required).length
  const done = steps.value.filter(s => completed.value[s.id]).length
  const requiredDone = steps.value.filter(s => s.is_required && completed.value[s.id]).length
  return { total, required, done, requiredDone, percent: total ? Math.round((done / total) * 100) : 0 }
})

const kindMeta: Record<string, { label: string; tone: string }> = {
  video:    { label: 'Video',    tone: 'bg-rose-100 text-rose-700' },
  article:  { label: 'Reading',  tone: 'bg-sycamore-100 text-sycamore-700' },
  link:     { label: 'Link',     tone: 'bg-slate-100 text-slate-700' },
  file:     { label: 'Download', tone: 'bg-amber-100 text-amber-700' },
  document: { label: 'Doc',      tone: 'bg-leaf-100 text-leaf-700' },
  task:     { label: 'Task',     tone: 'bg-slate-100 text-slate-700' },
  module:   { label: 'Module',   tone: 'bg-sycamore-100 text-sycamore-700' }
}

function toggleExpand(id: string) {
  expanded.value = { ...expanded.value, [id]: !expanded.value[id] }
}
</script>

<template>
  <div class="max-w-5xl mx-auto space-y-8">
    <!-- Hero -->
    <div class="bg-gradient-to-br from-sycamore-700 to-sycamore-900 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden">
      <div class="relative z-10">
        <div class="badge bg-white/15 text-white border-white/20 mb-4">
          <SidebarIcon name="check" />
          <span class="ml-1">Learning</span>
        </div>
        <h1 class="text-2xl sm:text-4xl font-bold tracking-tight mb-2 sm:mb-3">Your learning path</h1>
        <p class="text-sycamore-100 max-w-2xl text-sm sm:text-base">Lessons, videos, and training assigned to you. Complete quizzes to unlock the next level.</p>
        <div v-if="user" class="mt-6 max-w-md">
          <div class="flex items-center justify-between text-sm mb-2">
            <span>{{ stats.done }} of {{ stats.total }} completed</span>
            <span class="font-semibold">{{ stats.percent }}%</span>
          </div>
          <div class="w-full h-2 rounded-full bg-white/15 overflow-hidden">
            <div class="h-full bg-leaf-400 transition-all" :style="{ width: `${stats.percent}%` }" />
          </div>
          <div class="text-xs text-sycamore-100/80 mt-2">{{ stats.requiredDone }} / {{ stats.required }} required steps done</div>
        </div>
        <div v-else class="mt-6">
          <NuxtLink to="/login?redirect=/onboarding" class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-white text-sycamore-700 font-medium text-sm">
            Sign in to track progress
          </NuxtLink>
        </div>
      </div>
      <div class="absolute -right-16 -bottom-16 w-80 h-80 rounded-full bg-white/5" />
    </div>

    <div v-if="loading" class="text-slate-400">Loading learning path...</div>
    <div v-else-if="steps.length === 0" class="card p-8 text-center text-slate-500">
      Nothing assigned to you yet. Check back once your admin assigns lessons.
    </div>
    <div v-else class="space-y-10">
      <section v-for="group in pathGroups" :key="group.label">
        <!-- Path header -->
        <div class="flex items-center gap-3 mb-4">
          <div class="flex-1">
            <div class="flex items-center gap-2">
              <h2 class="section-title capitalize">{{ group.label }}</h2>
              <span v-if="group.isSequential" class="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded bg-sycamore-100 text-sycamore-700">Sequential</span>
            </div>
            <p v-if="group.path?.description" class="text-xs text-slate-500 mt-0.5">{{ group.path.description }}</p>
          </div>
          <div class="text-right">
            <div class="text-xs text-slate-400">{{ group.steps.length }} item{{ group.steps.length === 1 ? '' : 's' }}</div>
            <div class="w-20 h-1.5 rounded-full bg-slate-200 mt-1 overflow-hidden">
              <div class="h-full bg-leaf-500 transition-all" :style="{ width: `${group.progress}%` }" />
            </div>
          </div>
        </div>

        <div class="space-y-4">
          <article
            v-for="(s, idx) in group.steps"
            :key="s.id"
            class="card overflow-hidden transition-all"
            :class="[
              completed[s.id] ? 'bg-leaf-50/40 border-leaf-200' : '',
              !checkUnlocked(s) ? 'opacity-60' : ''
            ]"
          >
            <!-- Lock overlay for sequential paths -->
            <div v-if="!checkUnlocked(s)" class="absolute inset-0 z-10 flex items-center justify-center bg-white/60 backdrop-blur-[1px] rounded-xl">
              <div class="flex items-center gap-2 text-sm text-slate-500 font-medium">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" /></svg>
                Complete step {{ idx }} first
              </div>
            </div>

            <div v-if="s.cover_image_url" class="aspect-[16/6] w-full bg-slate-100 overflow-hidden">
              <img :src="s.cover_image_url" :alt="s.title" class="w-full h-full object-cover" />
            </div>

            <div class="p-5 flex items-start gap-4 relative">
              <!-- Step number for sequential paths -->
              <div v-if="group.isSequential" class="flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold"
                :class="completed[s.id] ? 'bg-leaf-600 text-white' : 'bg-slate-100 text-slate-500'"
              >
                <svg v-if="completed[s.id]" xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M16.7 5.3a1 1 0 0 1 0 1.4l-7.5 7.5a1 1 0 0 1-1.4 0L3.3 9.7a1 1 0 1 1 1.4-1.4L8.5 12l6.8-6.8a1 1 0 0 1 1.4 0Z" clip-rule="evenodd" />
                </svg>
                <span v-else>{{ idx + 1 }}</span>
              </div>

              <button
                v-else
                type="button"
                :disabled="saving[s.id] || !checkUnlocked(s)"
                @click="toggle(s)"
                :class="[
                  'flex-shrink-0 w-7 h-7 rounded-full border-2 flex items-center justify-center transition-colors mt-0.5',
                  completed[s.id] ? 'bg-leaf-600 border-leaf-600 text-white' : 'border-slate-300 hover:border-sycamore-500'
                ]"
                :aria-label="completed[s.id] ? 'Mark incomplete' : 'Mark complete'"
              >
                <svg v-if="completed[s.id]" xmlns="http://www.w3.org/2000/svg" class="w-4 h-4" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M16.7 5.3a1 1 0 0 1 0 1.4l-7.5 7.5a1 1 0 0 1-1.4 0L3.3 9.7a1 1 0 1 1 1.4-1.4L8.5 12l6.8-6.8a1 1 0 0 1 1.4 0Z" clip-rule="evenodd" />
                </svg>
              </button>

              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2 flex-wrap">
                  <span
                    class="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded"
                    :class="kindMeta[s.content_type || 'task']?.tone || 'bg-slate-100 text-slate-700'"
                  >{{ kindMeta[s.content_type || 'task']?.label || 'Task' }}</span>
                  <h3 class="font-semibold text-slate-900">{{ s.title }}</h3>
                  <span v-if="s.is_required" class="badge badge-amber">Required</span>
                  <span v-if="s.estimated_minutes" class="text-xs text-slate-400">~{{ s.estimated_minutes }} min</span>
                  <span v-if="s.due_date" class="text-xs text-rose-600 font-medium">Due {{ s.due_date }}</span>
                </div>
                <p v-if="s.description" class="text-sm text-slate-600 mt-1.5">{{ s.description }}</p>

                <!-- Quiz indicator -->
                <div v-if="stepHasQuiz(s.id)" class="mt-2 flex items-center gap-2">
                  <span v-if="stepQuizPassed(s.id)" class="inline-flex items-center gap-1 text-xs font-medium text-leaf-700 bg-leaf-50 px-2 py-0.5 rounded-full">
                    <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
                    Quiz passed{{ bestAttempt(s.id) ? ` (${bestAttempt(s.id)!.score}/${bestAttempt(s.id)!.total})` : '' }}
                  </span>
                  <template v-else>
                    <span class="inline-flex items-center gap-1 text-xs font-medium text-amber-700 bg-amber-50 px-2 py-0.5 rounded-full">
                      <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" /></svg>
                      Quiz required ({{ s.quiz_pass_threshold }}% to pass)
                    </span>
                    <button
                      v-if="checkUnlocked(s)"
                      @click="openQuiz(s)"
                      class="text-xs font-medium text-sycamore-700 hover:underline"
                    >Take quiz</button>
                  </template>
                </div>

                <div v-if="s.content_type === 'video' && toEmbedUrl(s.video_url)" class="mt-4 rounded-lg overflow-hidden border border-slate-200 bg-black">
                  <div class="aspect-video">
                    <iframe
                      :src="toEmbedUrl(s.video_url)!"
                      class="w-full h-full"
                      frameborder="0"
                      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                      allowfullscreen
                    />
                  </div>
                </div>
                <a
                  v-else-if="s.content_type === 'video' && s.video_url"
                  :href="s.video_url"
                  target="_blank"
                  rel="noopener"
                  class="mt-3 inline-flex items-center gap-2 text-sm text-sycamore-700 font-medium hover:underline"
                >
                  Open video <SidebarIcon name="arrow-right" />
                </a>

                <div v-if="s.content_type === 'article' && s.body" class="mt-3 prose prose-sm max-w-none text-slate-700 whitespace-pre-line">
                  {{ s.body }}
                </div>

                <div v-if="s.content_type === 'module' && s.body" class="mt-3 text-sm text-slate-700 whitespace-pre-line">
                  {{ s.body }}
                </div>

                <div v-if="s.onboarding_resources && s.onboarding_resources.length" class="mt-4">
                  <button
                    type="button"
                    class="text-xs font-medium text-sycamore-700 hover:underline inline-flex items-center gap-1"
                    @click="toggleExpand(s.id)"
                  >
                    {{ expanded[s.id] ? 'Hide' : 'Show' }} {{ s.onboarding_resources.length }} resource{{ s.onboarding_resources.length === 1 ? '' : 's' }}
                  </button>
                  <ul v-if="expanded[s.id]" class="mt-3 space-y-2">
                    <li v-for="r in s.onboarding_resources" :key="r.id" class="rounded-lg border border-slate-200 bg-slate-50/60 p-3">
                      <div class="flex items-center gap-2 flex-wrap">
                        <span
                          class="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded"
                          :class="kindMeta[r.kind]?.tone || 'bg-slate-100 text-slate-700'"
                        >{{ kindMeta[r.kind]?.label || r.kind }}</span>
                        <span class="text-sm font-medium text-slate-900">{{ r.title }}</span>
                      </div>
                      <p v-if="r.description" class="text-xs text-slate-600 mt-1">{{ r.description }}</p>
                      <div v-if="r.kind === 'video' && toEmbedUrl(r.url)" class="mt-2 rounded-md overflow-hidden border border-slate-200 bg-black">
                        <div class="aspect-video">
                          <iframe :src="toEmbedUrl(r.url)!" class="w-full h-full" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen />
                        </div>
                      </div>
                      <div v-else-if="r.kind === 'article' && r.body" class="text-sm text-slate-700 whitespace-pre-line mt-2">
                        {{ r.body }}
                      </div>
                      <a
                        v-else-if="r.url"
                        :href="r.url"
                        target="_blank"
                        rel="noopener"
                        class="mt-1.5 text-xs text-sycamore-700 font-medium hover:underline inline-flex items-center gap-1"
                      >
                        Open resource <SidebarIcon name="arrow-right" />
                      </a>
                    </li>
                  </ul>
                </div>

                <a
                  v-if="s.resource_url && s.content_type !== 'video'"
                  :href="s.resource_url"
                  target="_blank"
                  rel="noopener"
                  class="text-xs text-sycamore-600 hover:underline mt-3 inline-flex items-center gap-1"
                >
                  Open primary resource <SidebarIcon name="arrow-right" />
                </a>

                <!-- Complete button for sequential paths -->
                <div v-if="group.isSequential && checkUnlocked(s) && !completed[s.id]" class="mt-4">
                  <button
                    v-if="!stepHasQuiz(s.id)"
                    @click="toggle(s)"
                    :disabled="saving[s.id]"
                    class="btn-primary text-xs"
                  >
                    {{ saving[s.id] ? '...' : 'Mark complete' }}
                  </button>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>
    </div>

    <!-- Quiz Modal -->
    <Teleport to="body">
      <div v-if="quizOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/50 backdrop-blur-sm" @click="closeQuiz" />
        <div class="relative bg-white rounded-2xl shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
          <div class="sticky top-0 bg-white border-b border-slate-200 p-5 rounded-t-2xl z-10">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-bold text-slate-900">Quiz: {{ quizStep?.title }}</h2>
                <p class="text-sm text-slate-500 mt-0.5">Score at least {{ quizStep?.quiz_pass_threshold }}% to pass</p>
              </div>
              <button @click="closeQuiz" class="w-8 h-8 rounded-lg hover:bg-slate-100 flex items-center justify-center text-slate-400">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>
          </div>

          <div class="p-5 space-y-6">
            <div v-if="quizLoading" class="text-center py-8 text-slate-400">Loading questions...</div>

            <!-- Result screen -->
            <div v-else-if="quizResult" class="text-center py-6">
              <div
                class="w-20 h-20 rounded-full mx-auto flex items-center justify-center text-3xl mb-4"
                :class="quizResult.passed ? 'bg-leaf-100' : 'bg-red-100'"
              >
                {{ quizResult.passed ? '🎉' : '😔' }}
              </div>
              <h3 class="text-xl font-bold" :class="quizResult.passed ? 'text-leaf-700' : 'text-red-700'">
                {{ quizResult.passed ? 'Passed!' : 'Not quite...' }}
              </h3>
              <p class="text-slate-600 mt-2">
                You scored <span class="font-bold">{{ quizResult.score }}/{{ quizResult.total }}</span>
                ({{ Math.round((quizResult.score / quizResult.total) * 100) }}%)
              </p>
              <p v-if="!quizResult.passed" class="text-sm text-slate-500 mt-1">
                You need {{ quizStep?.quiz_pass_threshold }}% to pass. Review the material and try again.
              </p>
              <div class="mt-6 flex items-center justify-center gap-3">
                <button v-if="!quizResult.passed" @click="quizResult = null; quizAnswers = new Array(quizQuestions.length).fill(-1)" class="btn-primary text-sm">
                  Try again
                </button>
                <button @click="closeQuiz" class="text-sm text-slate-500 hover:text-slate-700 font-medium px-4 py-2">
                  {{ quizResult.passed ? 'Done' : 'Close' }}
                </button>
              </div>
            </div>

            <!-- Questions -->
            <template v-else>
              <div v-for="(q, qi) in quizQuestions" :key="q.id" class="p-4 rounded-xl border border-slate-200 bg-slate-50/50">
                <p class="font-medium text-slate-900 mb-3">
                  <span class="text-sm text-slate-400 mr-2">{{ qi + 1 }}.</span>
                  {{ q.question }}
                </p>
                <div class="space-y-2">
                  <label
                    v-for="(opt, oi) in q.options"
                    :key="oi"
                    class="flex items-center gap-3 px-3 py-2.5 rounded-lg border cursor-pointer transition-colors"
                    :class="quizAnswers[qi] === oi ? 'border-sycamore-300 bg-sycamore-50' : 'border-slate-200 hover:border-slate-300 bg-white'"
                  >
                    <input
                      type="radio"
                      :name="`q-${qi}`"
                      :value="oi"
                      v-model="quizAnswers[qi]"
                      class="w-4 h-4 text-sycamore-600 focus:ring-sycamore-500"
                    />
                    <span class="text-sm text-slate-700">{{ opt }}</span>
                  </label>
                </div>
              </div>

              <div class="flex items-center justify-end gap-3 pt-2">
                <button @click="closeQuiz" class="text-sm text-slate-500 hover:text-slate-700 font-medium px-4 py-2">Cancel</button>
                <button
                  @click="handleQuizSubmit"
                  :disabled="quizSubmitting"
                  class="btn-primary"
                >
                  {{ quizSubmitting ? 'Submitting...' : 'Submit answers' }}
                </button>
              </div>
            </template>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
