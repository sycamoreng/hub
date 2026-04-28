<script setup lang="ts">
const { fetchLeadership } = useCompanyData()
const leaders = ref<any[]>([])
const loading = ref(true)

onMounted(async () => {
  try { leaders.value = await fetchLeadership() } finally { loading.value = false }
})

const groups = computed(() => ({
  board: leaders.value.filter(l => l.tier === 'board'),
  executive: leaders.value.filter(l => l.tier === 'executive'),
  senior: leaders.value.filter(l => l.tier === 'senior')
}))

const sections = computed(() => [
  { key: 'board', title: 'Board of Directors', subtitle: 'Strategic stewardship and governance.', items: groups.value.board },
  { key: 'executive', title: 'Executives', subtitle: 'Leading day-to-day direction across the business.', items: groups.value.executive },
  { key: 'senior', title: 'Senior Management', subtitle: 'Heads of teams driving execution.', items: groups.value.senior }
])

function initials(name: string) {
  return name.split(/\s+/).map(p => p[0]).slice(0, 2).join('').toUpperCase()
}
</script>

<template>
  <div class="max-w-7xl mx-auto space-y-10">
    <div class="bg-gradient-to-br from-sycamore-700 to-sycamore-900 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden">
      <div class="relative z-10">
        <div class="badge bg-white/15 text-white border-white/20 mb-4">
          <SidebarIcon name="star" />
          <span class="ml-1">Leadership</span>
        </div>
        <h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">The people steering Sycamore</h1>
        <p class="text-sycamore-100 max-w-2xl">From the boardroom to senior management, meet the leaders shaping our direction.</p>
      </div>
      <div class="absolute -right-16 -bottom-16 w-80 h-80 rounded-full bg-white/5" />
      <div class="absolute -right-8 -top-8 w-48 h-48 rounded-full bg-white/5" />
    </div>

    <div v-if="loading" class="text-slate-400">Loading leadership...</div>
    <template v-else>
      <section v-for="s in sections" :key="s.key">
        <div class="flex items-end justify-between mb-5">
          <div>
            <h2 class="section-title">{{ s.title }}</h2>
            <p class="section-subtitle">{{ s.subtitle }}</p>
          </div>
          <span class="badge badge-slate">{{ s.items.length }}</span>
        </div>
        <div v-if="s.items.length === 0" class="card p-6 text-sm text-slate-400">No {{ s.title.toLowerCase() }} listed yet.</div>
        <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          <article v-for="l in s.items" :key="l.id" class="card card-hover p-6">
            <div class="flex items-start gap-4">
              <div class="flex-shrink-0">
                <img v-if="l.photo_url" :src="l.photo_url" :alt="l.full_name" class="w-16 h-16 rounded-full object-cover border border-slate-200" />
                <div v-else class="w-16 h-16 rounded-full bg-gradient-to-br from-sycamore-500 to-sycamore-700 text-white flex items-center justify-center font-bold">{{ initials(l.full_name) }}</div>
              </div>
              <div class="min-w-0">
                <h3 class="font-bold text-slate-900 truncate">{{ l.full_name }}</h3>
                <div class="text-sm text-sycamore-700 font-medium">{{ l.title }}</div>
              </div>
            </div>
            <p v-if="l.bio" class="text-sm text-slate-600 mt-4 line-clamp-4">{{ l.bio }}</p>
            <div v-if="l.email || l.phone || l.linkedin_url" class="mt-4 pt-4 border-t border-slate-100 flex flex-wrap gap-3 text-xs">
              <a v-if="l.email" :href="`mailto:${l.email}`" class="inline-flex items-center gap-1.5 text-slate-600 hover:text-sycamore-700">
                <SidebarIcon name="mail" /> Email
              </a>
              <a v-if="l.phone" :href="`tel:${l.phone}`" class="inline-flex items-center gap-1.5 text-slate-600 hover:text-sycamore-700">
                <SidebarIcon name="phone" /> Call
              </a>
              <a v-if="l.linkedin_url" :href="l.linkedin_url" target="_blank" rel="noopener" class="inline-flex items-center gap-1.5 text-slate-600 hover:text-sycamore-700">
                <SidebarIcon name="arrow-right" /> LinkedIn
              </a>
            </div>
          </article>
        </div>
      </section>
    </template>
  </div>
</template>
