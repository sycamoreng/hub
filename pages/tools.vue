<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { user, isAdmin } = useAuth()

const tools = ref<any[]>([])
const departments = ref<any[]>([])
const userDepartment = ref<string | null>(null)
const loading = ref(true)
const adminDeptFilter = ref<string>('')

onMounted(async () => {
  try {
    const [toolsRes, deptRes, deptsRes] = await Promise.all([
      supabase.from('quick_tools').select('*').eq('is_active', true).order('sort_order').order('name'),
      user.value
        ? supabase.from('staff_members').select('departments(name)').eq('auth_user_id', user.value.id).maybeSingle()
        : Promise.resolve({ data: null }),
      supabase.from('departments').select('id, name').order('name')
    ])
    tools.value = toolsRes.data ?? []
    userDepartment.value = (deptRes.data as any)?.departments?.name ?? null
    departments.value = deptsRes.data ?? []
  } finally {
    loading.value = false
  }
})

const visibleTools = computed(() => {
  const dept = userDepartment.value
  const admin = isAdmin.value
  return tools.value.filter(t => {
    const allowed: string[] = t.allowed_departments ?? []
    if (admin) {
      if (!adminDeptFilter.value) return true
      if (!allowed || allowed.length === 0) return true
      return allowed.includes(adminDeptFilter.value)
    }
    if (!allowed || allowed.length === 0) return true
    return dept ? allowed.includes(dept) : false
  })
})

function initialFor(name: string) {
  return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]?.toUpperCase() ?? '').join('') || '?'
}
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <header class="mb-8 flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="section-title">Tools</h1>
        <p class="section-subtitle">Quick access to the apps and services your team uses every day.</p>
      </div>
      <div v-if="isAdmin && departments.length" class="flex items-center gap-2">
        <label class="text-xs font-semibold uppercase tracking-wide text-slate-500">Filter by department</label>
        <select v-model="adminDeptFilter" class="input py-1.5 text-sm">
          <option value="">All departments</option>
          <option v-for="d in departments" :key="d.id" :value="d.name">{{ d.name }}</option>
        </select>
      </div>
    </header>

    <div v-if="loading" class="text-sm text-slate-400">Loading tools...</div>
    <div v-else-if="visibleTools.length === 0" class="card p-10 text-center text-sm text-slate-500">
      No tools are available for you yet.
    </div>
    <div v-else class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 sm:gap-4">
      <a
        v-for="t in visibleTools"
        :key="t.id"
        :href="t.url"
        target="_blank"
        rel="noopener noreferrer"
        class="card p-5 flex flex-col items-center justify-center text-center gap-3 hover:border-sycamore-300 hover:shadow-md transition-all group"
      >
        <div class="w-14 h-14 rounded-xl bg-slate-50 border border-slate-100 flex items-center justify-center overflow-hidden group-hover:scale-105 transition-transform">
          <img
            v-if="t.logo_url"
            :src="t.logo_url"
            :alt="t.name"
            referrerpolicy="no-referrer"
            class="w-10 h-10 object-contain"
          />
          <span v-else class="text-sm font-semibold text-sycamore-700">{{ initialFor(t.name) }}</span>
        </div>
        <div class="min-w-0 w-full">
          <div class="font-semibold text-sm text-slate-900 truncate">{{ t.name }}</div>
          <div v-if="t.allowed_departments && t.allowed_departments.length" class="mt-1.5 flex flex-wrap justify-center gap-1">
            <span v-for="d in t.allowed_departments" :key="d" class="badge badge-slate">{{ d }}</span>
          </div>
        </div>
      </a>
    </div>
  </div>
</template>
