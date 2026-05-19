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
    <NuxtLink to="/performance" class="text-xs text-sycamore-700 hover:underline">← Back to my performance</NuxtLink>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading review...</div>

    <template v-else-if="review">
      <header class="space-y-2">
        <div class="flex flex-wrap items-center gap-2">
          <h1 class="text-2xl font-bold text-slate-900">{{ reviewerLabel }}</h1>
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
        <div class="text-xs text-slate-500">
          Invited {{ new Date(review.invited_at).toLocaleDateString('en-GB') }}
          <span v-if="review.due_at"> · Due {{ new Date(review.due_at).toLocaleDateString('en-GB') }}</span>
          <span v-if="review.submitted_at"> · Submitted {{ new Date(review.submitted_at).toLocaleDateString('en-GB') }}</span>
        </div>
      </header>

      <section v-if="objectiveRatings.length" class="card p-5 space-y-4">
        <header>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Objectives</h2>
          <p class="text-xs text-slate-500 mt-1">Score each objective on the same scale. Leave a comment explaining your rating.</p>
        </header>
        <ul class="space-y-4">
          <li v-for="r in objectiveRatings" :key="r.objective_id!" class="space-y-2">
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-semibold text-slate-900">{{ r.question }}</span>
            </div>
            <div class="flex items-center gap-3">
              <input
                type="range" :min="competencyScale.min" :max="competencyScale.max" step="1"
                :value="r.score ?? competencyScale.min"
                :disabled="!canEdit"
                class="flex-1"
                @change="(e) => { r.score = Number((e.target as HTMLInputElement).value); saveRow(r) }"
              />
              <span class="text-xs text-slate-600 w-40 text-right">{{ scoreLabel(r.score) }}</span>
            </div>
            <textarea
              v-model="r.comment" rows="2" class="input"
              placeholder="Evidence or example that supports this rating"
              :disabled="!canEdit"
              @change="saveRow(r)"
            ></textarea>
          </li>
        </ul>
      </section>

      <section v-if="competencyRatings.length" class="card p-5 space-y-4">
        <header>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Competencies</h2>
          <p class="text-xs text-slate-500 mt-1">Rate behaviours using the framework's scale.</p>
        </header>
        <ul class="space-y-4">
          <li v-for="r in competencyRatings" :key="r.competency_label" class="space-y-2">
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-semibold text-slate-900">{{ r.competency_label }}</span>
            </div>
            <div class="flex items-center gap-3">
              <input
                type="range" :min="competencyScale.min" :max="competencyScale.max" step="1"
                :value="r.score ?? competencyScale.min"
                :disabled="!canEdit"
                class="flex-1"
                @change="(e) => { r.score = Number((e.target as HTMLInputElement).value); saveRow(r) }"
              />
              <span class="text-xs text-slate-600 w-40 text-right">{{ scoreLabel(r.score) }}</span>
            </div>
            <textarea
              v-model="r.comment" rows="2" class="input"
              placeholder="Add context or an example"
              :disabled="!canEdit"
              @change="saveRow(r)"
            ></textarea>
          </li>
        </ul>
      </section>

      <section class="card p-5 space-y-4">
        <header>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Narrative</h2>
          <p class="text-xs text-slate-500 mt-1">The big-picture summary that the subject and their manager will see.</p>
        </header>
        <label class="block">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Strengths</span>
          <textarea
            :value="review.strengths" rows="3" class="input"
            :disabled="!canEdit"
            placeholder="What is this person doing really well?"
            @change="(e) => saveHeader({ strengths: (e.target as HTMLTextAreaElement).value })"
          ></textarea>
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Areas to improve</span>
          <textarea
            :value="review.improvements" rows="3" class="input"
            :disabled="!canEdit"
            placeholder="Where should they focus next?"
            @change="(e) => saveHeader({ improvements: (e.target as HTMLTextAreaElement).value })"
          ></textarea>
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Overall comment</span>
          <textarea
            :value="review.overall_comment" rows="3" class="input"
            :disabled="!canEdit"
            placeholder="Anything else to add"
            @change="(e) => saveHeader({ overall_comment: (e.target as HTMLTextAreaElement).value })"
          ></textarea>
        </label>
        <div class="grid sm:grid-cols-2 gap-3 items-end">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Overall rating ({{ competencyScale.min }}–{{ competencyScale.max }})</span>
            <input
              type="number" :min="competencyScale.min" :max="competencyScale.max" step="0.5"
              :value="review.overall_rating ?? ''"
              :disabled="!canEdit"
              class="input"
              @change="(e) => { const v = (e.target as HTMLInputElement).value; saveHeader({ overall_rating: v === '' ? null : Number(v) }) }"
            />
          </label>
          <div v-if="review.overall_rating !== null" class="text-xs text-slate-600">{{ scoreLabel(review.overall_rating) }}</div>
        </div>
      </section>

      <section v-if="review.reviewer_type === 'manager' || review.reviewer_type === 'self'" class="card p-5 space-y-4">
        <header>
          <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Recommendation</h2>
          <p class="text-xs text-slate-500 mt-1">Based on performance this cycle, what outcome do you recommend for this person?</p>
        </header>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Recommended outcome</span>
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
          <span class="text-xs font-medium text-slate-600 mb-1 block">Justification</span>
          <textarea
            :value="review.recommendation_notes ?? ''"
            rows="3" class="input"
            :disabled="!canEdit"
            placeholder="Why are you recommending this outcome?"
            @change="(e) => saveHeader({ recommendation_notes: (e.target as HTMLTextAreaElement).value })"
          ></textarea>
        </label>
      </section>

      <div v-if="canEdit" class="flex flex-wrap gap-2 justify-end">
        <button class="btn-secondary" @click="openDecline">Decline</button>
        <button class="btn-primary" :disabled="saving" @click="submit">
          {{ saving ? 'Submitting...' : 'Submit review' }}
        </button>
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
