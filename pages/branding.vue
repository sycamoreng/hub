<script setup lang="ts">
const { fetchBrandingGuidelines } = useCompanyData()
const guidelines = ref<any[]>([])
const loading = ref(true)

onMounted(async () => {
  try { guidelines.value = await fetchBrandingGuidelines() } finally { loading.value = false }
})

const grouped = computed(() => {
  const m: Record<string, any[]> = {}
  for (const g of guidelines.value) {
    const key = g.category || 'visual'
    ;(m[key] = m[key] || []).push(g)
  }
  return m
})

const palette = [
  { name: 'Sycamore 600', hex: '#2f6f2f', cls: 'bg-sycamore-600' },
  { name: 'Sycamore 500', hex: '#3D8B3D', cls: 'bg-sycamore-500' },
  { name: 'Sycamore 400', hex: '#62a862', cls: 'bg-sycamore-400' },
  { name: 'Sycamore 100', hex: '#dceddc', cls: 'bg-sycamore-100' },
  { name: 'Slate 900', hex: '#0f172a', cls: 'bg-slate-900' },
  { name: 'Slate 500', hex: '#64748b', cls: 'bg-slate-500' }
]
</script>

<template>
  <div class="max-w-6xl mx-auto space-y-10">
    <div>
      <h1 class="section-title">Branding Guidelines</h1>
      <p class="section-subtitle">How we present Sycamore to the world.</p>
    </div>

    <section class="card p-6">
      <h2 class="text-lg font-bold text-slate-900 mb-5">Color Palette</h2>
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        <div v-for="c in palette" :key="c.hex">
          <div :class="['aspect-square rounded-xl', c.cls]"></div>
          <div class="mt-2 text-xs font-medium text-slate-900">{{ c.name }}</div>
          <div class="text-xs text-slate-500 font-mono">{{ c.hex }}</div>
        </div>
      </div>
    </section>

    <section v-for="(items, cat) in grouped" :key="cat">
      <h2 class="text-lg font-bold text-slate-900 mb-4 capitalize">{{ cat }} Guidelines</h2>
      <div class="grid md:grid-cols-2 gap-4">
        <article v-for="g in items" :key="g.id" class="card p-6">
          <h3 class="font-semibold text-slate-900 flex items-center gap-2">
            <SidebarIcon name="palette" /> {{ g.element_name }}
          </h3>
          <p class="text-sm text-slate-600 mt-2">{{ g.description }}</p>
          <div v-if="g.guidelines" class="mt-4 p-3 bg-slate-50 rounded-lg text-sm text-slate-700 whitespace-pre-line border border-slate-100">{{ g.guidelines }}</div>
        </article>
      </div>
    </section>
  </div>
</template>
