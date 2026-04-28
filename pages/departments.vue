<script setup lang="ts">
const { fetchDepartments } = useCompanyData()
const departments = ref<any[]>([])
const search = ref('')
const loading = ref(true)

onMounted(async () => {
  try { departments.value = await fetchDepartments() } finally { loading.value = false }
})

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return departments.value
  return departments.value.filter(d =>
    d.name.toLowerCase().includes(q) ||
    d.description.toLowerCase().includes(q) ||
    d.head_name.toLowerCase().includes(q)
  )
})
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-8">
      <div>
        <h1 class="section-title">Departments</h1>
        <p class="section-subtitle">Explore the teams that make Sycamore work.</p>
      </div>
      <div class="relative sm:w-72">
        <input v-model="search" type="text" placeholder="Search departments..." class="input pl-10" />
        <div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><SidebarIcon name="search" /></div>
      </div>
    </div>

    <div v-if="loading" class="text-slate-400">Loading departments...</div>
    <div v-else-if="filtered.length === 0" class="text-slate-400">No departments match your search.</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="d in filtered" :key="d.id" class="card card-hover p-6">
        <div class="flex items-start justify-between mb-3">
          <div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">
            <SidebarIcon name="building" />
          </div>
          <span class="badge badge-green">{{ d.staff_count }} staff</span>
        </div>
        <h3 class="font-bold text-slate-900 text-lg">{{ d.name }}</h3>
        <p class="text-sm text-slate-600 mt-2 line-clamp-3">{{ d.description }}</p>
        <div class="mt-4 pt-4 border-t border-slate-100">
          <div class="text-xs text-slate-400 uppercase tracking-wide mb-1">Department Head</div>
          <div class="text-sm font-semibold text-slate-900">{{ d.head_name }}</div>
          <div class="text-xs text-slate-500">{{ d.head_title }}</div>
          <a v-if="d.head_email" :href="`mailto:${d.head_email}`" class="text-xs text-sycamore-600 hover:underline">{{ d.head_email }}</a>
        </div>
      </article>
    </div>
  </div>
</template>
