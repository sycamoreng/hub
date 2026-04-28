<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { fetchOnboardingSteps } = useCompanyData()
const { user } = useAuth()

const steps = ref<any[]>([])
const completed = ref<Record<string, boolean>>({})
const loading = ref(true)
const saving = ref<Record<string, boolean>>({})

async function loadAll() {
  loading.value = true
  try {
    steps.value = await fetchOnboardingSteps()
    if (user.value) {
      const { data } = await supabase
        .from('onboarding_progress')
        .select('step_id')
        .eq('user_id', user.value.id)
      const map: Record<string, boolean> = {}
      ;(data ?? []).forEach((r: any) => { map[r.step_id] = true })
      completed.value = map
    }
  } finally {
    loading.value = false
  }
}

onMounted(loadAll)
watch(() => user.value?.id, loadAll)

async function toggle(step: any) {
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
    }
  } catch (e: any) {
    alert(e.message ?? 'Failed to update progress')
  } finally {
    saving.value[step.id] = false
  }
}

const grouped = computed(() => {
  const m: Record<string, any[]> = {}
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
</script>

<template>
  <div class="max-w-5xl mx-auto space-y-8">
    <div class="bg-gradient-to-br from-sycamore-700 to-sycamore-900 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden">
      <div class="relative z-10">
        <div class="badge bg-white/15 text-white border-white/20 mb-4">
          <SidebarIcon name="check" />
          <span class="ml-1">Onboarding</span>
        </div>
        <h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">Welcome to Sycamore</h1>
        <p class="text-sycamore-100 max-w-2xl">A guided checklist of everything you should know in your first weeks.</p>
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

    <div v-if="loading" class="text-slate-400">Loading onboarding checklist...</div>
    <div v-else-if="steps.length === 0" class="card p-8 text-center text-slate-500">
      No onboarding steps have been set up yet.
    </div>
    <div v-else class="space-y-8">
      <section v-for="cat in categories" :key="cat">
        <h2 class="section-title capitalize mb-4">{{ cat }}</h2>
        <div class="space-y-3">
          <article
            v-for="s in grouped[cat]"
            :key="s.id"
            class="card p-5 flex items-start gap-4"
            :class="completed[s.id] ? 'bg-leaf-50/50 border-leaf-200' : ''"
          >
            <button
              type="button"
              :disabled="saving[s.id]"
              @click="toggle(s)"
              :class="[
                'flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center transition-colors mt-0.5',
                completed[s.id] ? 'bg-leaf-600 border-leaf-600 text-white' : 'border-slate-300 hover:border-sycamore-500'
              ]"
              :aria-label="completed[s.id] ? 'Mark incomplete' : 'Mark complete'"
            >
              <svg v-if="completed[s.id]" xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M16.7 5.3a1 1 0 0 1 0 1.4l-7.5 7.5a1 1 0 0 1-1.4 0L3.3 9.7a1 1 0 1 1 1.4-1.4L8.5 12l6.8-6.8a1 1 0 0 1 1.4 0Z" clip-rule="evenodd" />
              </svg>
            </button>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2 flex-wrap">
                <h3 class="font-semibold text-slate-900">{{ s.title }}</h3>
                <span v-if="s.is_required" class="badge badge-amber">Required</span>
                <span v-else class="badge badge-slate">Optional</span>
              </div>
              <p v-if="s.description" class="text-sm text-slate-600 mt-1">{{ s.description }}</p>
              <a v-if="s.resource_url" :href="s.resource_url" target="_blank" rel="noopener" class="text-xs text-sycamore-600 hover:underline mt-2 inline-flex items-center gap-1">
                Open resource <SidebarIcon name="arrow-right" />
              </a>
            </div>
          </article>
        </div>
      </section>
    </div>
  </div>
</template>
