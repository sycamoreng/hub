<script setup lang="ts">
const { fetchCommunicationTools } = useCompanyData()
const tools = ref<any[]>([])
const loading = ref(true)

onMounted(async () => {
  try { tools.value = await fetchCommunicationTools() } finally { loading.value = false }
})

const grouped = computed(() => {
  const m: Record<string, any[]> = {}
  for (const t of tools.value) {
    const key = t.category || 'general'
    ;(m[key] = m[key] || []).push(t)
  }
  return m
})
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Communication Tools</h1>
      <p class="section-subtitle">Platforms and channels we use to stay connected.</p>
    </div>

    <div v-if="loading" class="text-slate-400">Loading tools...</div>
    <div v-else class="space-y-8">
      <section v-for="(items, cat) in grouped" :key="cat">
        <h2 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3 capitalize">{{ cat }}</h2>
        <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <article v-for="t in items" :key="t.id" class="card card-hover p-5">
            <div class="flex items-start justify-between mb-3">
              <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">
                <SidebarIcon name="chat" />
              </div>
              <span v-if="t.is_primary" class="badge badge-green">Primary</span>
            </div>
            <h3 class="font-semibold text-slate-900">{{ t.name }}</h3>
            <p class="text-sm text-slate-600 mt-1.5 mb-4">{{ t.description }}</p>
            <a v-if="t.url" :href="t.url" target="_blank" rel="noopener" class="text-sm text-sycamore-600 hover:underline inline-flex items-center gap-1">
              Open <SidebarIcon name="arrow-right" />
            </a>
          </article>
        </div>
      </section>
    </div>
  </div>
</template>
