<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

definePageMeta({ middleware: ['auth'] })

const supabase = useSupabase()

const loading = ref(true)
const leadership = ref<any[]>([])
const departments = ref<any[]>([])
const teams = ref<any[]>([])
const staff = ref<any[]>([])
const search = ref('')

async function load() {
  loading.value = true
  try {
    const [{ data: ld }, { data: d }, { data: t }, { data: sm }] = await Promise.all([
      supabase.from('leadership').select('id, full_name, title, tier, photo_url, email, display_order, is_active').order('display_order'),
      supabase.from('departments').select('id, name, description, head_staff_id, head_name, head_title').order('name'),
      supabase.from('teams').select('id, department_id, name, description, lead_staff_id, display_order').order('display_order').order('name'),
      supabase.from('staff_members').select('id, full_name, email, role, department_id, team_id, manager_id, is_active').eq('is_active', true).order('full_name')
    ])
    leadership.value = (ld ?? []).filter((l: any) => l.is_active)
    departments.value = d ?? []
    teams.value = t ?? []
    staff.value = sm ?? []
  } finally { loading.value = false }
}

function staffById(id: string | null | undefined) {
  if (!id) return null
  return staff.value.find(s => s.id === id) ?? null
}

function teamMembers(teamId: string) {
  const q = search.value.trim().toLowerCase()
  return staff.value
    .filter(s => s.team_id === teamId)
    .filter(s => !q || (s.full_name || '').toLowerCase().includes(q) || (s.email || '').toLowerCase().includes(q))
}
function departmentDirectMembers(deptId: string) {
  const q = search.value.trim().toLowerCase()
  return staff.value
    .filter(s => s.department_id === deptId && !s.team_id)
    .filter(s => !q || (s.full_name || '').toLowerCase().includes(q) || (s.email || '').toLowerCase().includes(q))
}
function departmentTeams(deptId: string) {
  return teams.value.filter(t => t.department_id === deptId)
}

function initials(name: string) {
  return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0]?.toUpperCase()).join('')
}

const executiveTiers = computed(() => {
  const q = search.value.trim().toLowerCase()
  const filtered = leadership.value.filter(l => !q || (l.full_name || '').toLowerCase().includes(q) || (l.title || '').toLowerCase().includes(q))
  const byTier: Record<string, any[]> = {}
  for (const row of filtered) {
    const tier = row.tier || 'executive'
    ;(byTier[tier] ||= []).push(row)
  }
  const order = ['executive', 'senior', 'director', 'manager']
  return order.filter(t => byTier[t]).map(t => ({ tier: t, people: byTier[t] })).concat(
    Object.keys(byTier).filter(t => !order.includes(t)).map(t => ({ tier: t, people: byTier[t] }))
  )
})

load()
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
    <header class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4 mb-8">
      <div>
        <h1 class="text-3xl font-bold text-slate-900">Organogram</h1>
        <p class="text-sm text-slate-500 mt-1">How the organization is structured — leadership, departments, and the teams within them.</p>
      </div>
      <label class="relative w-full sm:w-72">
        <input v-model="search" type="search" placeholder="Search people or titles..."
          class="w-full border border-slate-300 rounded-full pl-10 pr-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><path fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 1 0 3.02 10.11l3.68 3.69a.75.75 0 1 0 1.06-1.06l-3.69-3.68A5.5 5.5 0 0 0 9 3.5Zm-4 5.5a4 4 0 1 1 8 0 4 4 0 0 1-8 0Z" clip-rule="evenodd"/></svg>
      </label>
    </header>

    <div v-if="loading" class="text-sm text-slate-500">Loading organization...</div>

    <div v-else class="space-y-10">
      <!-- Leadership -->
      <section v-if="leadership.length">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-slate-500 mb-4">Leadership</h2>
        <div v-for="group in executiveTiers" :key="group.tier" class="mb-6">
          <div class="text-[11px] uppercase tracking-wide text-slate-400 mb-3 capitalize">{{ group.tier }}</div>
          <div class="flex flex-wrap justify-center gap-4">
            <article v-for="p in group.people" :key="p.id"
              class="bg-white border border-slate-200 rounded-xl px-5 py-4 w-60 text-center shadow-sm">
              <div class="mx-auto w-14 h-14 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center font-semibold overflow-hidden">
                <img v-if="p.photo_url" :src="p.photo_url" :alt="p.full_name" class="w-full h-full object-cover" />
                <span v-else>{{ initials(p.full_name) }}</span>
              </div>
              <div class="mt-2 font-semibold text-slate-900 text-sm">{{ p.full_name }}</div>
              <div class="text-xs text-slate-500">{{ p.title }}</div>
            </article>
          </div>
        </div>
      </section>

      <!-- Departments -->
      <section>
        <h2 class="text-xs font-semibold uppercase tracking-wider text-slate-500 mb-4">Departments</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <article v-for="dept in departments" :key="dept.id" class="bg-white border border-slate-200 rounded-xl overflow-hidden">
            <header class="px-5 py-4 border-b border-slate-100 bg-slate-50/50">
              <h3 class="text-base font-semibold text-slate-900">{{ dept.name }}</h3>
              <p v-if="dept.description" class="text-xs text-slate-500 mt-1">{{ dept.description }}</p>
              <div v-if="staffById(dept.head_staff_id) || dept.head_name" class="mt-3 flex items-center gap-3">
                <div class="w-9 h-9 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center text-xs font-semibold">
                  {{ initials(staffById(dept.head_staff_id)?.full_name || dept.head_name) }}
                </div>
                <div class="text-xs">
                  <div class="font-semibold text-slate-900">{{ staffById(dept.head_staff_id)?.full_name || dept.head_name }}</div>
                  <div class="text-slate-500">{{ staffById(dept.head_staff_id)?.role || dept.head_title || 'Department Head' }}</div>
                </div>
              </div>
            </header>

            <div class="p-5 space-y-4">
              <div v-for="tm in departmentTeams(dept.id)" :key="tm.id" class="border border-slate-100 rounded-lg p-4">
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <div class="text-sm font-semibold text-slate-900">{{ tm.name }}</div>
                    <div v-if="tm.description" class="text-xs text-slate-500 mt-0.5">{{ tm.description }}</div>
                  </div>
                  <div v-if="staffById(tm.lead_staff_id)" class="text-xs text-slate-500 text-right">
                    <div class="text-[10px] uppercase tracking-wide">Lead</div>
                    <div class="font-semibold text-slate-900">{{ staffById(tm.lead_staff_id)?.full_name }}</div>
                  </div>
                </div>
                <ul v-if="teamMembers(tm.id).length" class="mt-3 flex flex-wrap gap-2">
                  <li v-for="m in teamMembers(tm.id)" :key="m.id" class="text-xs bg-slate-50 border border-slate-200 rounded-full px-2.5 py-1 text-slate-700">
                    {{ m.full_name }}
                  </li>
                </ul>
                <p v-else class="mt-3 text-xs text-slate-400 italic">No members yet.</p>
              </div>

              <div v-if="departmentDirectMembers(dept.id).length">
                <div class="text-[11px] uppercase tracking-wide text-slate-400 mb-2">
                  {{ departmentTeams(dept.id).length ? 'Unassigned to a team' : 'Members' }}
                </div>
                <ul class="flex flex-wrap gap-2">
                  <li v-for="m in departmentDirectMembers(dept.id)" :key="m.id" class="text-xs bg-white border border-slate-200 rounded-full px-2.5 py-1 text-slate-700">
                    {{ m.full_name }}
                  </li>
                </ul>
              </div>

              <p v-if="!departmentTeams(dept.id).length && !departmentDirectMembers(dept.id).length" class="text-xs text-slate-400 italic">No teams or staff assigned yet.</p>
            </div>
          </article>
        </div>
      </section>
    </div>
  </div>
</template>
