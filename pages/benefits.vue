<script setup lang="ts">
const { fetchBenefits } = useCompanyData()
const benefits = ref<any[]>([])
const selectedCat = ref('All')
const loading = ref(true)

onMounted(async () => {
  try { benefits.value = await fetchBenefits() } finally { loading.value = false }
})

const categories = computed(() => ['All', ...new Set(benefits.value.map(b => b.category))])
const filtered = computed(() =>
  selectedCat.value === 'All' ? benefits.value : benefits.value.filter(b => b.category === selectedCat.value)
)
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Benefits &amp; Perks</h1>
      <p class="section-subtitle">We invest in you. Here's what that looks like.</p>
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

    <div v-if="loading" class="text-slate-400">Loading benefits...</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="b in filtered" :key="b.id" class="card card-hover p-6">
        <div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center mb-4">
          <SidebarIcon name="gift" />
        </div>
        <h3 class="font-bold text-slate-900">{{ b.title }}</h3>
        <p class="text-sm text-slate-600 mt-2">{{ b.description }}</p>
        <div class="mt-4 pt-4 border-t border-slate-100 flex items-center justify-between text-xs">
          <span class="badge badge-green capitalize">{{ b.category }}</span>
          <span class="text-slate-500">{{ b.eligibility }}</span>
        </div>
      </article>
    </div>
  </div>
</template>
