<script setup lang="ts">
import type { Survey } from '~/composables/useSurveys'

definePageMeta({ title: 'Surveys' })

const { ready } = useAuth()
const { loadSurveys, loadMyResponses } = useSurveys()

const surveys = ref<Survey[]>([])
const completed = ref<Set<string>>(new Set())
const loading = ref(true)

async function load() {
  loading.value = true
  try {
    const all = await loadSurveys()
    surveys.value = all.filter(s => s.status === 'open')
    completed.value = await loadMyResponses()
  } catch {
    surveys.value = []
  }
  loading.value = false
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-3xl mx-auto px-4 py-8">
    <div class="mb-6">
      <h1 class="section-title">Surveys</h1>
      <p class="section-subtitle">Share your feedback on the surveys open to you right now</p>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="surveys.length === 0" class="card p-8 text-center text-slate-400">
      There are no open surveys at the moment. Check back later.
    </div>
    <div v-else class="space-y-3">
      <div v-for="s in surveys" :key="s.id" class="card p-5 flex items-start justify-between gap-4">
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <h2 class="font-semibold text-slate-900">{{ s.title }}</h2>
            <span v-if="completed.has(s.id)" class="badge badge-green">Completed</span>
            <span v-if="s.is_anonymous" class="badge badge-slate">Anonymous</span>
          </div>
          <p v-if="s.description" class="text-sm text-slate-500 mt-1 line-clamp-2">{{ s.description }}</p>
          <p v-if="s.closes_at" class="text-xs text-slate-400 mt-2">Closes {{ new Date(s.closes_at).toLocaleDateString() }}</p>
        </div>
        <NuxtLink
          v-if="completed.has(s.id)"
          :to="`/surveys/${s.id}`"
          class="btn-secondary shrink-0"
        >View</NuxtLink>
        <NuxtLink v-else :to="`/surveys/${s.id}`" class="btn-primary shrink-0">Take survey</NuxtLink>
      </div>
    </div>
  </div>
</template>
