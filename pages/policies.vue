<script setup lang="ts">
const { fetchPolicies } = useCompanyData()
const policies = ref<any[]>([])
const expanded = ref<Record<string, boolean>>({})
const selectedCat = ref('All')
const loading = ref(true)

onMounted(async () => {
  try { policies.value = await fetchPolicies() } finally { loading.value = false }
})

const categories = computed(() => ['All', ...new Set(policies.value.map(p => p.category))])
const filtered = computed(() =>
  selectedCat.value === 'All' ? policies.value : policies.value.filter(p => p.category === selectedCat.value)
)

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}
</script>

<template>
  <div class="max-w-5xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Policies</h1>
      <p class="section-subtitle">Guidelines that shape how we work at Sycamore.</p>
    </div>

    <div class="flex flex-wrap gap-2 mb-6">
      <button
        v-for="c in categories"
        :key="c"
        @click="selectedCat = c"
        :class="[
          'px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors',
          selectedCat === c ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300'
        ]"
      >{{ c }}</button>
    </div>

    <div v-if="loading" class="text-slate-400">Loading policies...</div>
    <div v-else class="space-y-3">
      <article v-for="p in filtered" :key="p.id" class="card">
        <button @click="expanded[p.id] = !expanded[p.id]" class="w-full p-5 flex items-center gap-4 text-left">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center flex-shrink-0">
            <SidebarIcon name="book" />
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="font-semibold text-slate-900">{{ p.title }}</h3>
            <div class="flex flex-wrap items-center gap-2 mt-1 text-xs text-slate-500">
              <span class="badge badge-slate capitalize">{{ p.category }}</span>
              <span>Effective {{ formatDate(p.effective_date) }}</span>
            </div>
          </div>
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5 text-slate-400 transition-transform" :class="{ 'rotate-180': expanded[p.id] }">
            <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
          </svg>
        </button>
        <div v-if="expanded[p.id]" class="px-5 pb-5 pl-[74px] text-sm text-slate-700 whitespace-pre-line border-t border-slate-100 pt-4">
          {{ p.content }}
        </div>
      </article>
    </div>
  </div>
</template>
