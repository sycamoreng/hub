<script setup lang="ts">
const { fetchStaff, fetchDepartments } = useCompanyData()
const staff = ref<any[]>([])
const departments = ref<any[]>([])
const search = ref('')
const selectedDept = ref('All')
const loading = ref(true)

onMounted(async () => {
  try {
    const [s, d] = await Promise.all([fetchStaff(), fetchDepartments()])
    staff.value = s
    departments.value = d
  } finally { loading.value = false }
})

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return staff.value.filter(s => {
    const deptOk = selectedDept.value === 'All' || s.departments?.name === selectedDept.value
    if (!deptOk) return false
    if (!q) return true
    return s.full_name.toLowerCase().includes(q) || s.role.toLowerCase().includes(q) || s.email.toLowerCase().includes(q)
  })
})

function initials(name: string) {
  return name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
}
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Staff Directory</h1>
      <p class="section-subtitle">Meet the people who make Sycamore thrive.</p>
    </div>

    <div class="card p-4 mb-6 flex flex-col sm:flex-row gap-3">
      <div class="relative flex-1">
        <input v-model="search" type="text" placeholder="Search by name, role, or email..." class="input pl-10" />
        <div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><SidebarIcon name="search" /></div>
      </div>
      <select v-model="selectedDept" class="input sm:w-56">
        <option value="All">All departments</option>
        <option v-for="d in departments" :key="d.id" :value="d.name">{{ d.name }}</option>
      </select>
    </div>

    <div v-if="loading" class="text-slate-400">Loading staff...</div>
    <div v-else-if="filtered.length === 0" class="text-slate-400">No staff match your filters.</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <NuxtLink v-for="s in filtered" :key="s.id" :to="`/profile/${s.id}`" class="card card-hover p-5 flex gap-4">
        <div class="w-14 h-14 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-lg flex-shrink-0">
          {{ initials(s.full_name) }}
        </div>
        <div class="min-w-0 flex-1">
          <h3 class="font-semibold text-slate-900 truncate">{{ s.full_name }}</h3>
          <div class="text-sm text-slate-600 truncate">{{ s.role }}</div>
          <div class="text-xs text-slate-500 mt-1">
            <span v-if="s.departments?.name" class="badge badge-green">{{ s.departments.name }}</span>
          </div>
          <div class="text-xs text-slate-500 mt-2 truncate">{{ s.email }}</div>
          <div v-if="s.locations" class="text-xs text-slate-400 mt-0.5">{{ s.locations.city }}</div>
        </div>
      </NuxtLink>
    </div>
  </div>
</template>
