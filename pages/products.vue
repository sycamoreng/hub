<script setup lang="ts">
const { fetchProducts } = useCompanyData()
const products = ref<any[]>([])
const search = ref('')
const loading = ref(true)

onMounted(async () => {
  try { products.value = await fetchProducts() } finally { loading.value = false }
})

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return products.value
  return products.value.filter((p: any) =>
    p.name.toLowerCase().includes(q) ||
    (p.tagline ?? '').toLowerCase().includes(q) ||
    (p.description ?? '').toLowerCase().includes(q) ||
    (p.category ?? '').toLowerCase().includes(q)
  )
})

const statusBadge: Record<string, string> = {
  live: 'badge-green',
  beta: 'badge-blue',
  internal: 'badge-slate',
  retired: 'badge-rose'
}
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-8">
      <div>
        <h1 class="section-title">Our Products</h1>
        <p class="section-subtitle">The fintech offerings we build, ship, and support.</p>
      </div>
      <div class="relative sm:w-72">
        <input v-model="search" type="text" placeholder="Search products..." class="input pl-10" />
        <div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><SidebarIcon name="search" /></div>
      </div>
    </div>

    <div v-if="loading" class="text-slate-400">Loading products...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-500">No products match.</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="p in filtered" :key="p.id" class="card card-hover p-6 flex flex-col">
        <div class="flex items-start justify-between gap-3 mb-3">
          <span :class="['badge capitalize', statusBadge[p.status] ?? 'badge-slate']">{{ p.status }}</span>
          <span v-if="p.category" class="badge badge-slate capitalize">{{ p.category }}</span>
        </div>
        <h3 class="text-lg font-bold text-slate-900">{{ p.name }}</h3>
        <p v-if="p.tagline" class="text-sm text-sycamore-700 font-medium mt-0.5">{{ p.tagline }}</p>
        <p class="text-sm text-slate-600 mt-3 line-clamp-4 flex-1">{{ p.description }}</p>
        <div v-if="p.target_market" class="mt-3 pt-3 border-t border-slate-100">
          <div class="text-xs text-slate-400 uppercase tracking-wide">Target market</div>
          <div class="text-sm text-slate-700">{{ p.target_market }}</div>
        </div>
        <a v-if="p.url" :href="p.url" target="_blank" rel="noopener" class="text-xs text-sycamore-600 hover:underline mt-3 inline-flex items-center gap-1">
          Learn more <SidebarIcon name="arrow-right" />
        </a>
      </article>
    </div>
  </div>
</template>
