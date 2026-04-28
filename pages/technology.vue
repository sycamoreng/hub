<script setup lang="ts">
const { fetchTechStack } = useCompanyData()
const stack = ref<any[]>([])
const loading = ref(true)
const selected = ref('All')

onMounted(async () => {
  try { stack.value = await fetchTechStack() } finally { loading.value = false }
})

const categories = computed(() => ['All', ...Array.from(new Set(stack.value.map((t: any) => t.category || 'general'))).sort()])
const filtered = computed(() => selected.value === 'All' ? stack.value : stack.value.filter((t: any) => (t.category || 'general') === selected.value))
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Technology Stack</h1>
      <p class="section-subtitle">The tools, languages, and platforms powering Sycamore.</p>
    </div>

    <div class="flex flex-wrap gap-2 mb-6">
      <button
        v-for="c in categories"
        :key="c"
        @click="selected = c"
        :class="[
          'px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors',
          selected === c ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300'
        ]"
      >{{ c }}</button>
    </div>

    <div v-if="loading" class="text-slate-400">Loading tech stack...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-500">No technologies listed.</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="t in filtered" :key="t.id" class="card card-hover p-6">
        <div class="flex items-start justify-between mb-3">
          <div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">
            <SidebarIcon name="palette" />
          </div>
          <span class="badge badge-slate capitalize">{{ t.category }}</span>
        </div>
        <h3 class="text-lg font-bold text-slate-900">{{ t.name }}</h3>
        <p v-if="t.description" class="text-sm text-slate-600 mt-2 line-clamp-3">{{ t.description }}</p>
        <div v-if="t.used_for" class="mt-3 pt-3 border-t border-slate-100">
          <div class="text-xs text-slate-400 uppercase tracking-wide">Used for</div>
          <div class="text-sm text-slate-700">{{ t.used_for }}</div>
        </div>
        <a v-if="t.url" :href="t.url" target="_blank" rel="noopener" class="text-xs text-sycamore-600 hover:underline mt-3 inline-flex items-center gap-1">
          Learn more <SidebarIcon name="arrow-right" />
        </a>
      </article>
    </div>
  </div>
</template>
