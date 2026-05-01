<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { toEmbedUrl } from '~/composables/useVideoEmbed'

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
  onboarding_resources: Resource[]
  due_date?: string | null
  scope_types?: string[]
}

const supabase = useSupabase()
const { fetchOnboardingSteps } = useCompanyData()
const { user } = useAuth()
const toast = useToast()

const steps = ref<Step[]>([])
const completed = ref<Record<string, boolean>>({})
const loading = ref(true)
const saving = ref<Record<string, boolean>>({})
const expanded = ref<Record<string, boolean>>({})

async function loadAll() {
  loading.value = true
  try {
    const allSteps = (await fetchOnboardingSteps()) as Step[]

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
  } finally {
    loading.value = false
  }
}

onMounted(loadAll)
watch(() => user.value?.id, loadAll)

async function toggle(step: Step) {
  if (!user.value) {
    await navigateTo(`/login?redirect=/onboarding`)
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
      toast.success('Marked complete')
    }
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to update progress')
  } finally {
    saving.value[step.id] = false
  }
}

const grouped = computed(() => {
  const m: Record<string, Step[]> = {}
  for (const s of steps.value) {
    const c = s.category || 'general'
    ;(m[c] ||= []).push(s)
  }
  return m
})

const categories = computed(() => Object.keys(grouped.value).sort())

const stats = computed(() => {
  const total = steps.value.length
  const required = steps.value.filter(s => s.is_required).length
  const done = steps.value.filter(s => completed.value[s.id]).length
  const requiredDone = steps.value.filter(s => s.is_required && completed.value[s.id]).length
  return { total, required, done, requiredDone, percent: total ? Math.round((done / total) * 100) : 0 }
})

function totalMinutes(cat: string) {
  return grouped.value[cat]?.reduce((sum, s) => sum + (s.estimated_minutes || 0), 0) ?? 0
}

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
    <div class="bg-gradient-to-br from-sycamore-700 to-sycamore-900 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden">
      <div class="relative z-10">
        <div class="badge bg-white/15 text-white border-white/20 mb-4">
          <SidebarIcon name="check" />
          <span class="ml-1">Learning</span>
        </div>
        <h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">Your learning path</h1>
        <p class="text-sycamore-100 max-w-2xl">Lessons, videos, and tasks assigned to you, your department, or the whole company.</p>
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
      <section v-for="cat in categories" :key="cat">
        <div class="flex items-baseline justify-between mb-4">
          <h2 class="section-title capitalize">{{ cat }}</h2>
          <div class="text-xs text-slate-400">
            {{ grouped[cat].length }} item{{ grouped[cat].length === 1 ? '' : 's' }}
            <template v-if="totalMinutes(cat) > 0"> &middot; ~{{ totalMinutes(cat) }} min</template>
          </div>
        </div>

        <div class="space-y-4">
          <article
            v-for="s in grouped[cat]"
            :key="s.id"
            class="card overflow-hidden transition-colors"
            :class="completed[s.id] ? 'bg-leaf-50/40 border-leaf-200' : ''"
          >
            <div v-if="s.cover_image_url" class="aspect-[16/6] w-full bg-slate-100 overflow-hidden">
              <img :src="s.cover_image_url" :alt="s.title" class="w-full h-full object-cover" />
            </div>

            <div class="p-5 flex items-start gap-4">
              <button
                type="button"
                :disabled="saving[s.id]"
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
              </div>
            </div>
          </article>
        </div>
      </section>
    </div>
  </div>
</template>
