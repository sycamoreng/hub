<script setup lang="ts">
import {
  usePerformance,
  REVIEWER_TYPE_LABELS,
  type PerformanceReview,
  type PerformanceReviewRating,
  type ReviewerType
} from '~/composables/usePerformance'

const route = useRoute()
const toast = useToast()
const { user } = useAuth()
const {
  loadReview, loadReviewRatings, saveReview, saveRating, deleteRating, submitReview,
  loadObjectives, loadFrameworks
} = usePerformance()

const reviewId = String(route.params.id)
const loading = ref(true)
const review = ref<(PerformanceReview & { subject?: any; reviewer?: any; cycle?: any }) | null>(null)
const ratings = ref<PerformanceReviewRating[]>([])
const objectives = ref<any[]>([])
const competencyScale = ref<{ min: number; max: number; labels: string[] }>({ min: 1, max: 5, labels: ['Needs work', 'Below', 'Meets', 'Exceeds', 'Outstanding'] })
const saving = ref(false)

const COMPETENCIES = [
  'Delivery & execution',
  'Ownership & accountability',
  'Collaboration & communication',
  'Judgement & problem solving',
  'Customer focus',
  'Leadership & mentorship'
]

async function load() {
  loading.value = true
  try {
    const [r, existingRatings, fws] = await Promise.all([
      loadReview(reviewId),
      loadReviewRatings(reviewId),
      loadFrameworks()
    ])
    if (!r) {
      toast.push({ type: 'error', title: 'Review not found', message: 'You may not have access.' })
      return
    }
    review.value = r as any
    const competencyFw = fws.find(f => f.kind === 'competency')
    if (competencyFw) competencyScale.value = competencyFw.scoring_scale
    objectives.value = await loadObjectives({ cycleId: r.cycle_id, staffId: r.subject_staff_id })

    const byObjective = new Map<string, PerformanceReviewRating>()
    const byCompetency = new Map<string, PerformanceReviewRating>()
    for (const x of existingRatings) {
      if (x.objective_id) byObjective.set(x.objective_id, x)
      else if (x.competency_label) byCompetency.set(x.competency_label, x)
    }

    const seeds: PerformanceReviewRating[] = []
    for (const [i, o] of objectives.value.entries()) {
      const existing = byObjective.get(o.id)
      seeds.push(existing ?? {
        id: '',
        review_id: reviewId,
        objective_id: o.id,
        competency_label: '',
        question: o.title,
        score: null,
        comment: '',
        sort_order: i * 10
      } as PerformanceReviewRating)
    }
    if (r.reviewer_type !== 'peer' && r.reviewer_type !== 'upward' && r.reviewer_type !== 'downward') {
      // always show competencies for self/manager; optional for 360 types
    }
    const compBaseOrder = objectives.value.length * 10 + 10
    for (const [i, label] of COMPETENCIES.entries()) {
      const existing = byCompetency.get(label)
      seeds.push(existing ?? {
        id: '',
        review_id: reviewId,
        objective_id: null,
        competency_label: label,
        question: '',
        score: null,
        comment: '',
        sort_order: compBaseOrder + i * 10
      } as PerformanceReviewRating)
    }
    ratings.value = seeds
  } finally {
    loading.value = false
  }
}

onMounted(load)

const canEdit = computed(() => {
  if (!review.value || !user.value) return false
  if (!['invited', 'in_progress'].includes(review.value.status)) return false
  return review.value.reviewer?.auth_user_id === user.value.id
})

const isSubject = computed(() => review.value?.subject?.auth_user_id === user.value?.id)
const reviewerLabel = computed(() => REVIEWER_TYPE_LABELS[review.value?.reviewer_type as ReviewerType] ?? '')

const objectiveRatings = computed(() => ratings.value.filter(r => r.objective_id))
const competencyRatings = computed(() => ratings.value.filter(r => r.competency_label))

function scoreLabel(score: number | null) {
  if (score == null) return '—'
  const idx = Math.max(0, Math.min(competencyScale.value.labels.length - 1, Math.round(score) - 1))
  return `${score.toFixed(1)} · ${competencyScale.value.labels[idx] ?? ''}`
}

async function ensureInProgress() {
  if (!review.value || !canEdit.value) return
  if (review.value.status === 'invited') {
    await saveReview({ id: review.value.id, status: 'in_progress' })
    review.value.status = 'in_progress'
  }
}

async function saveRow(r: PerformanceReviewRating) {
  if (!canEdit.value) return
  await ensureInProgress()
  try {
    const payload: Partial<PerformanceReviewRating> = {
      id: r.id || undefined,
      review_id: reviewId,
      objective_id: r.objective_id,
      competency_label: r.competency_label,
      question: r.question,
      score: r.score,
      comment: r.comment,
      sort_order: r.sort_order
    }
    const saved = await saveRating(payload)
    if (saved?.id) r.id = saved.id
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}

async function saveHeader(patch: Partial<PerformanceReview>) {
  if (!review.value || !canEdit.value) return
  await ensureInProgress()
  try {
    await saveReview({ id: review.value.id, ...patch })
    Object.assign(review.value, patch)
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}

async function submit() {
  if (!review.value || !canEdit.value) return
  // Persist any un-saved ratings that have values
  saving.value = true
  try {
    for (const r of ratings.value) {
      if (r.id) continue
      if (r.score == null && !r.comment) continue
      await saveRow(r)
    }
    await submitReview(review.value.id)
    toast.push({ type: 'success', title: 'Review submitted', message: reviewerLabel.value })
    review.value.status = 'submitted'
    review.value.submitted_at = new Date().toISOString()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not submit', message: e?.message ?? 'Unexpected error' })
  } finally {
    saving.value = false
  }
}

const declineOpen = ref(false)
const declineReasonDraft = ref('')
function openDecline() {
  if (!review.value || !canEdit.value) return
  declineReasonDraft.value = ''
  declineOpen.value = true
}
async function confirmDecline() {
  if (!review.value) return
  declineOpen.value = false
  try {
    await saveReview({ id: review.value.id, status: 'declined', declined_reason: declineReasonDraft.value.trim() })
    toast.push({ type: 'success', title: 'Review declined', message: 'Thanks for letting us know.' })
    review.value.status = 'declined'
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not decline', message: e?.message ?? 'Unexpected error' })
  }
}

function statusBadge(status: string) {
  const map: Record<string, string> = {
    invited: 'badge-blue', in_progress: 'badge-amber', submitted: 'badge-green',
    declined: 'badge-rose', cancelled: 'badge-slate'
  }
  return map[status] ?? 'badge-slate'
}
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-10 space-y-6">
    <NuxtLink to="/performance" class="inline-flex items-center gap-1 text-sm text-sycamore-700 hover:underline font-medium">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M12.79 5.23a.75.75 0 0 1-.02 1.06L8.832 10l3.938 3.71a.75.75 0 1 1-1.04 1.08l-4.5-4.25a.75.75 0 0 1 0-1.08l4.5-4.25a.75.75 0 0 1 1.06.02Z" clip-rule="evenodd" /></svg>
      Back to performance
    </NuxtLink>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading review...</div>

    <template v-else-if="review">
      <!-- Header card with contextual color -->
      <header class="card overflow-hidden">
        <div class="h-2" :class="review.status === 'submitted' ? 'bg-leaf-500' : review.status === 'in_progress' ? 'bg-amber-400' : 'bg-sycamore-500'" />
        <div class="p-5 sm:p-6 space-y-2">
          <div class="flex flex-wrap items-center gap-2">
            <h1 class="text-xl sm:text-2xl font-bold text-slate-900">{{ reviewerLabel }}</h1>
            <span class="badge" :class="statusBadge(review.status)">{{ review.status.replaceAll('_', ' ') }}</span>
            <span v-if="review.anonymous && isSubject" class="badge badge-blue">Anonymous</span>
          </div>
          <p class="text-sm text-slate-600">
            <span v-if="review.reviewer_type === 'self'">Evaluating yourself for the cycle <span class="font-semibold">{{ review.cycle?.name }}</span>.</span>
            <span v-else-if="isSubject">
              Feedback from {{ review.anonymous ? 'an anonymous reviewer' : review.reviewer?.full_name }} for <span class="font-semibold">{{ review.cycle?.name }}</span>.
            </span>
            <span v-else>
              Reviewing <span class="font-semibold">{{ review.subject?.full_name }}</span> for <span class="font-semibold">{{ review.cycle?.name }}</span>.
            </span>
          </p>
          <div class="text-xs text-slate-500 flex flex-wrap gap-x-3 gap-y-1">
            <span>Invited {{ new Date(review.invited_at).toLocaleDateString('en-GB') }}</span>
            <span v-if="review.due_at">Due {{ new Date(review.due_at).toLocaleDateString('en-GB') }}</span>
            <span v-if="review.submitted_at">Submitted {{ new Date(review.submitted_at).toLocaleDateString('en-GB') }}</span>
          </div>

          <!-- Progress indicator -->
          <div v-if="canEdit" class="mt-3 pt-3 border-t border-slate-100">
            <div class="flex items-center gap-3 text-xs text-slate-500">
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded-full border-2 border-sycamore-500 bg-sycamore-100" />
                <span>Objectives ({{ objectiveRatings.filter(r => r.score != null).length }}/{{ objectiveRatings.length }})</span>
              </div>
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded-full border-2 border-amber-500 bg-amber-100" />
                <span>Competencies ({{ competencyRatings.filter(r => r.score != null).length }}/{{ competencyRatings.length }})</span>
              </div>
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded-full border-2 border-leaf-500 bg-leaf-100" />
                <span>Narrative</span>
              </div>
            </div>
          </div>
        </div>
      </header>

      <!-- OBJECTIVES SECTION - Blue/Sycamore theme -->
      <section v-if="objectiveRatings.length" class="card overflow-hidden">
        <div class="bg-sycamore-50 border-b border-sycamore-100 px-5 sm:px-6 py-4">
          <div class="flex items-center gap-2">
            <span class="w-8 h-8 rounded-lg bg-sycamore-600 text-white flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M10 18a8 8 0 1 0 0-16 8 8 0 0 0 0 16Zm3.857-9.809a.75.75 0 0 0-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 1 0-1.06 1.061l2.5 2.5a.75.75 0 0 0 1.137-.089l4-5.5Z" clip-rule="evenodd" /></svg>
            </span>
            <div>
              <h2 class="text-sm font-bold text-sycamore-900">Objectives</h2>
              <p class="text-xs text-sycamore-700/70">Score each objective and provide supporting evidence.</p>
            </div>
          </div>
        </div>
        <div class="p-5 sm:p-6 space-y-5">
          <div
            v-for="(r, idx) in objectiveRatings"
            :key="r.objective_id!"
            class="relative pl-4 border-l-[3px] border-sycamore-200 space-y-3"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-[11px] font-bold text-sycamore-600 uppercase tracking-wider">Objective {{ idx + 1 }}</span>
              <span v-if="r.score != null" class="w-2 h-2 rounded-full bg-sycamore-500" title="Scored" />
            </div>
            <h3 class="text-[15px] font-semibold text-slate-900 leading-snug">{{ r.question }}</h3>

            <!-- Score selector with visual labels -->
            <div class="space-y-2">
              <div class="flex items-center gap-2">
                <div class="flex-1 flex items-center gap-1">
                  <button
                    v-for="s in Array.from({ length: competencyScale.max - competencyScale.min + 1 }, (_, i) => i + competencyScale.min)"
                    :key="s"
                    type="button"
                    :disabled="!canEdit"
                    class="w-9 h-9 sm:w-10 sm:h-10 rounded-lg text-sm font-bold transition-all"
                    :class="r.score === s
                      ? 'bg-sycamore-600 text-white shadow-sm ring-2 ring-sycamore-600 ring-offset-1'
                      : 'bg-slate-100 text-slate-500 hover:bg-sycamore-100 hover:text-sycamore-700'"
                    @click="() => { r.score = s; saveRow(r) }"
                  >
                    {{ s }}
                  </button>
                </div>
                <span v-if="r.score != null" class="text-xs font-medium text-sycamore-700 ml-2 hidden sm:block">{{ scoreLabel(r.score) }}</span>
              </div>
              <div class="flex justify-between text-[10px] text-slate-400 px-1">
                <span>{{ competencyScale.labels[0] }}</span>
                <span>{{ competencyScale.labels[competencyScale.labels.length - 1] }}</span>
              </div>
            </div>

            <textarea
              v-model="r.comment" rows="2" class="input"
              placeholder="Evidence or example that supports this rating"
              :disabled="!canEdit"
              @change="saveRow(r)"
            ></textarea>
          </div>
        </div>
      </section>

      <!-- COMPETENCIES SECTION - Amber/Warm theme -->
      <section v-if="competencyRatings.length" class="card overflow-hidden">
        <div class="bg-amber-50 border-b border-amber-100 px-5 sm:px-6 py-4">
          <div class="flex items-center gap-2">
            <span class="w-8 h-8 rounded-lg bg-amber-500 text-white flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path d="M10 1a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 1ZM5.05 3.05a.75.75 0 0 1 1.06 0l1.062 1.06a.75.75 0 1 1-1.06 1.061L5.05 4.11a.75.75 0 0 1 0-1.06ZM14.95 3.05a.75.75 0 0 1 0 1.06l-1.06 1.062a.75.75 0 0 1-1.062-1.061l1.061-1.06a.75.75 0 0 1 1.06 0ZM3 8a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 0 1.5h-1.5A.75.75 0 0 1 3 8ZM14 8a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 0 1.5h-1.5A.75.75 0 0 1 14 8ZM7.172 13.828a.75.75 0 0 1 0 1.061l-1.06 1.06a.75.75 0 0 1-1.061-1.06l1.06-1.06a.75.75 0 0 1 1.06 0ZM10 11a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 10 11Z" /><path d="M10 4a4 4 0 1 0 0 8 4 4 0 0 0 0-8Z" /></svg>
            </span>
            <div>
              <h2 class="text-sm font-bold text-amber-900">Competencies</h2>
              <p class="text-xs text-amber-700/70">Rate behaviours and soft skills using the framework's scale.</p>
            </div>
          </div>
        </div>
        <div class="p-5 sm:p-6 space-y-5">
          <div
            v-for="(r, idx) in competencyRatings"
            :key="r.competency_label"
            class="relative pl-4 border-l-[3px] border-amber-200 space-y-3"
          >
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-[11px] font-bold text-amber-600 uppercase tracking-wider">Competency {{ idx + 1 }}</span>
              <span v-if="r.score != null" class="w-2 h-2 rounded-full bg-amber-500" title="Scored" />
            </div>
            <h3 class="text-[15px] font-semibold text-slate-900 leading-snug">{{ r.competency_label }}</h3>

            <div class="space-y-2">
              <div class="flex items-center gap-2">
                <div class="flex-1 flex items-center gap-1">
                  <button
                    v-for="s in Array.from({ length: competencyScale.max - competencyScale.min + 1 }, (_, i) => i + competencyScale.min)"
                    :key="s"
                    type="button"
                    :disabled="!canEdit"
                    class="w-9 h-9 sm:w-10 sm:h-10 rounded-lg text-sm font-bold transition-all"
                    :class="r.score === s
                      ? 'bg-amber-500 text-white shadow-sm ring-2 ring-amber-500 ring-offset-1'
                      : 'bg-slate-100 text-slate-500 hover:bg-amber-100 hover:text-amber-700'"
                    @click="() => { r.score = s; saveRow(r) }"
                  >
                    {{ s }}
                  </button>
                </div>
                <span v-if="r.score != null" class="text-xs font-medium text-amber-700 ml-2 hidden sm:block">{{ scoreLabel(r.score) }}</span>
              </div>
              <div class="flex justify-between text-[10px] text-slate-400 px-1">
                <span>{{ competencyScale.labels[0] }}</span>
                <span>{{ competencyScale.labels[competencyScale.labels.length - 1] }}</span>
              </div>
            </div>

            <textarea
              v-model="r.comment" rows="2" class="input"
              placeholder="Add context or an example"
              :disabled="!canEdit"
              @change="saveRow(r)"
            ></textarea>
          </div>
        </div>
      </section>

      <!-- NARRATIVE SECTION - Green/Leaf theme -->
      <section class="card overflow-hidden">
        <div class="bg-leaf-50 border-b border-leaf-100 px-5 sm:px-6 py-4">
          <div class="flex items-center gap-2">
            <span class="w-8 h-8 rounded-lg bg-leaf-600 text-white flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M2 3.5A1.5 1.5 0 0 1 3.5 2h9A1.5 1.5 0 0 1 14 3.5v11.75A2.75 2.75 0 0 0 16.75 18h-12A2.75 2.75 0 0 1 2 15.25V3.5Zm3.75 7a.75.75 0 0 0 0 1.5h4.5a.75.75 0 0 0 0-1.5h-4.5Zm0 3a.75.75 0 0 0 0 1.5h4.5a.75.75 0 0 0 0-1.5h-4.5ZM5 5.75A.75.75 0 0 1 5.75 5h4.5a.75.75 0 0 1 .75.75v2.5a.75.75 0 0 1-.75.75h-4.5A.75.75 0 0 1 5 8.25v-2.5Z" clip-rule="evenodd" /><path d="M16.5 6.5h-1v8.75a1.25 1.25 0 1 0 2.5 0V8a1.5 1.5 0 0 0-1.5-1.5Z" /></svg>
            </span>
            <div>
              <h2 class="text-sm font-bold text-leaf-900">Narrative Summary</h2>
              <p class="text-xs text-leaf-700/70">The big-picture view that the subject and their manager will see.</p>
            </div>
          </div>
        </div>
        <div class="p-5 sm:p-6 space-y-4">
          <label class="block">
            <span class="text-xs font-semibold text-leaf-700 mb-1.5 block flex items-center gap-1.5">
              <span class="w-1.5 h-1.5 rounded-full bg-leaf-500" /> Strengths
            </span>
            <textarea
              :value="review.strengths" rows="3" class="input"
              :disabled="!canEdit"
              placeholder="What is this person doing really well?"
              @change="(e) => saveHeader({ strengths: (e.target as HTMLTextAreaElement).value })"
            ></textarea>
          </label>
          <label class="block">
            <span class="text-xs font-semibold text-amber-700 mb-1.5 block flex items-center gap-1.5">
              <span class="w-1.5 h-1.5 rounded-full bg-amber-500" /> Areas to improve
            </span>
            <textarea
              :value="review.improvements" rows="3" class="input"
              :disabled="!canEdit"
              placeholder="Where should they focus next?"
              @change="(e) => saveHeader({ improvements: (e.target as HTMLTextAreaElement).value })"
            ></textarea>
          </label>
          <label class="block">
            <span class="text-xs font-semibold text-slate-600 mb-1.5 block flex items-center gap-1.5">
              <span class="w-1.5 h-1.5 rounded-full bg-slate-400" /> Overall comment
            </span>
            <textarea
              :value="review.overall_comment" rows="3" class="input"
              :disabled="!canEdit"
              placeholder="Anything else to add"
              @change="(e) => saveHeader({ overall_comment: (e.target as HTMLTextAreaElement).value })"
            ></textarea>
          </label>
          <div class="pt-3 border-t border-slate-100">
            <div class="grid sm:grid-cols-2 gap-3 items-end">
              <label class="block">
                <span class="text-xs font-semibold text-slate-700 mb-1.5 block">Overall rating ({{ competencyScale.min }}–{{ competencyScale.max }})</span>
                <input
                  type="number" :min="competencyScale.min" :max="competencyScale.max" step="0.5"
                  :value="review.overall_rating ?? ''"
                  :disabled="!canEdit"
                  class="input"
                  @change="(e) => { const v = (e.target as HTMLInputElement).value; saveHeader({ overall_rating: v === '' ? null : Number(v) }) }"
                />
              </label>
              <div v-if="review.overall_rating !== null" class="pb-2">
                <span class="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-sycamore-50 border border-sycamore-200 text-sm font-semibold text-sycamore-800">
                  {{ scoreLabel(review.overall_rating) }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- RECOMMENDATION SECTION - Slate/Neutral theme with emphasis -->
      <section v-if="review.reviewer_type === 'manager' || review.reviewer_type === 'self'" class="card overflow-hidden">
        <div class="bg-slate-800 px-5 sm:px-6 py-4">
          <div class="flex items-center gap-2">
            <span class="w-8 h-8 rounded-lg bg-white/10 text-white flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Zm-7-4a1 1 0 1 1-2 0 1 1 0 0 1 2 0ZM9 9a.75.75 0 0 0 0 1.5h.253a.25.25 0 0 1 .244.304l-.459 2.066A1.75 1.75 0 0 0 10.747 15H11a.75.75 0 0 0 0-1.5h-.253a.25.25 0 0 1-.244-.304l.459-2.066A1.75 1.75 0 0 0 9.253 9H9Z" clip-rule="evenodd" /></svg>
            </span>
            <div>
              <h2 class="text-sm font-bold text-white">Recommendation</h2>
              <p class="text-xs text-white/60">Based on this cycle, what outcome do you recommend?</p>
            </div>
          </div>
        </div>
        <div class="p-5 sm:p-6 space-y-4">
          <div class="grid sm:grid-cols-2 gap-3">
            <label class="block">
              <span class="text-xs font-semibold text-slate-700 mb-1.5 block">Recommended outcome</span>
              <select
                :value="review.recommendation ?? ''"
                :disabled="!canEdit"
                class="input"
                @change="(e) => saveHeader({ recommendation: (e.target as HTMLSelectElement).value || null })"
              >
                <option value="">-- Select --</option>
                <option value="promotion">Promotion</option>
                <option value="same_grade">Stay on same grade</option>
                <option value="pip">Performance Improvement Plan (PIP)</option>
                <option value="termination">Termination</option>
              </select>
            </label>
          </div>
          <label class="block">
            <span class="text-xs font-semibold text-slate-700 mb-1.5 block">Justification</span>
            <textarea
              :value="review.recommendation_notes ?? ''"
              rows="3" class="input"
              :disabled="!canEdit"
              placeholder="Why are you recommending this outcome?"
              @change="(e) => saveHeader({ recommendation_notes: (e.target as HTMLTextAreaElement).value })"
            ></textarea>
          </label>
        </div>
      </section>

      <!-- Submit actions -->
      <div v-if="canEdit" class="card p-4 sm:p-5 flex flex-wrap items-center justify-between gap-3 sticky bottom-20 lg:bottom-4 z-10 shadow-lg border-sycamore-200">
        <div class="text-xs text-slate-500">
          Auto-saved as you go. Submit when you're done.
        </div>
        <div class="flex gap-2">
          <button class="btn-secondary" @click="openDecline">Decline</button>
          <button class="btn-primary" :disabled="saving" @click="submit">
            {{ saving ? 'Submitting...' : 'Submit review' }}
          </button>
        </div>
      </div>

      <Teleport to="body">
        <Transition name="fade">
          <div v-if="declineOpen" class="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm" @click.self="declineOpen = false">
            <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
              <div class="p-6 space-y-3">
                <h3 class="text-base font-semibold text-slate-900">Decline this review?</h3>
                <p class="text-sm text-slate-600">Share an optional note so HR or your manager knows why.</p>
                <textarea v-model="declineReasonDraft" rows="3" class="input" placeholder="e.g. Too new to give fair feedback" />
              </div>
              <div class="bg-slate-50 px-6 py-3.5 flex items-center justify-end gap-2 border-t border-slate-100">
                <button type="button" class="btn-secondary" @click="declineOpen = false">Cancel</button>
                <button type="button" class="btn-primary bg-rose-600 hover:bg-rose-700 border-rose-600" @click="confirmDecline">Decline</button>
              </div>
            </div>
          </div>
        </Transition>
      </Teleport>

      <div v-if="!canEdit && review.status === 'declined' && review.declined_reason" class="card p-5 bg-rose-50 border-rose-200">
        <div class="text-xs font-semibold uppercase tracking-wide text-rose-700 mb-1">Declined</div>
        <p class="text-sm text-rose-900">{{ review.declined_reason }}</p>
      </div>
    </template>
  </div>
</template>
