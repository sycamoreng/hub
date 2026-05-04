<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { user } = useAuth()
const loading = ref(true)
const me = ref<any | null>(null)
const allStaff = ref<any[]>([])
const departments = ref<any[]>([])
const teams = ref<any[]>([])
const manager = ref<any | null>(null)
const expanded = ref<Set<string>>(new Set())

async function load() {
  loading.value = true
  try {
    if (!user.value) return
    const [{ data: sm }, { data: all }, { data: d }, { data: t }] = await Promise.all([
      supabase.from('staff_members').select('id, full_name, email, role, department_id, team_id, manager_id').eq('auth_user_id', user.value.id).maybeSingle(),
      supabase.from('staff_members').select('id, full_name, email, role, department_id, team_id, manager_id, is_active').eq('is_active', true).order('full_name'),
      supabase.from('departments').select('id, name, head_staff_id'),
      supabase.from('teams').select('id, name, department_id, lead_staff_id')
    ])
    me.value = sm
    allStaff.value = all ?? []
    departments.value = d ?? []
    teams.value = t ?? []
    manager.value = sm?.manager_id ? (all ?? []).find((x: any) => x.id === sm.manager_id) : null
  } finally { loading.value = false }
}

function teamsLedBy(staffId: string) {
  return teams.value.filter(t => t.lead_staff_id === staffId)
}
function departmentsHeadedBy(staffId: string) {
  return departments.value.filter(d => d.head_staff_id === staffId)
}

// Determine a single effective supervisor per staff member.
// Priority: explicit manager_id > team lead > department head. Returns null if no supervisor.
function supervisorOf(s: any): { id: string, via: string } | null {
  if (!s) return null
  if (s.manager_id && s.manager_id !== s.id) {
    return { id: s.manager_id, via: 'Direct report' }
  }
  if (s.team_id) {
    const t = teams.value.find(tt => tt.id === s.team_id)
    if (t?.lead_staff_id && t.lead_staff_id !== s.id) {
      return { id: t.lead_staff_id, via: `Team: ${t.name}` }
    }
  }
  if (s.department_id) {
    const d = departments.value.find(dd => dd.id === s.department_id)
    if (d?.head_staff_id && d.head_staff_id !== s.id) {
      return { id: d.head_staff_id, via: `Dept: ${d.name}` }
    }
  }
  return null
}

// Reverse index: staffId -> [{ staff, via }] of people whose effective supervisor is them.
const reportsByManager = computed(() => {
  const map = new Map<string, { staff: any, via: string }[]>()
  for (const s of allStaff.value) {
    const sup = supervisorOf(s)
    if (!sup) continue
    if (!map.has(sup.id)) map.set(sup.id, [])
    map.get(sup.id)!.push({ staff: s, via: sup.via })
  }
  return map
})

function directReports(staffId: string) {
  return (reportsByManager.value.get(staffId) ?? []).map(r => r.staff)
}

// Build the set of all people under me using the single-supervisor chain.
const subordinates = computed(() => {
  if (!me.value) return [] as any[]
  const visited = new Set<string>([me.value.id])
  const queue: string[] = [me.value.id]
  const result: any[] = []
  while (queue.length) {
    const id = queue.shift()!
    for (const sub of (reportsByManager.value.get(id) ?? [])) {
      if (!visited.has(sub.staff.id)) { visited.add(sub.staff.id); queue.push(sub.staff.id); result.push(sub.staff) }
    }
  }
  return result
})

const role = computed(() => {
  if (!me.value) return ''
  const isHead = departments.value.some(d => d.head_staff_id === me.value.id)
  const isLead = teams.value.some(t => t.lead_staff_id === me.value.id)
  const hasReports = allStaff.value.some(s => s.manager_id === me.value.id)
  if (isHead) return 'Department Head'
  if (isLead) return 'Team Lead'
  if (hasReports) return 'Manager'
  return ''
})

function toggle(id: string) {
  const s = new Set(expanded.value)
  if (s.has(id)) s.delete(id); else s.add(id)
  expanded.value = s
}

function initials(name: string) {
  return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0]?.toUpperCase()).join('')
}

function deptName(id: string | null | undefined) {
  return departments.value.find(d => d.id === id)?.name ?? ''
}

interface ReportRow { staff: any; depth: number; via: string }
function buildTree(rootId: string, maxDepth = 6): ReportRow[] {
  const rows: ReportRow[] = []
  const seen = new Set<string>([rootId])
  function walk(id: string, depth: number) {
    if (depth > maxDepth) return
    if (!expanded.value.has(id) && depth > 0) return
    for (const r of (reportsByManager.value.get(id) ?? [])) {
      if (seen.has(r.staff.id)) continue
      seen.add(r.staff.id)
      rows.push({ staff: r.staff, depth: depth + 1, via: r.via })
      walk(r.staff.id, depth + 1)
    }
  }
  walk(rootId, 0)
  return rows
}

const tree = computed(() => me.value ? buildTree(me.value.id) : [])

function hasChildren(id: string) {
  return (reportsByManager.value.get(id)?.length ?? 0) > 0
}

load()
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
    <header class="mb-8">
      <h1 class="text-3xl font-bold text-slate-900">My team</h1>
      <p class="text-sm text-slate-500 mt-1">Everyone reporting into you — directly, through a team you lead, or a department you head.</p>
    </header>

    <div v-if="loading" class="text-sm text-slate-500">Loading...</div>

    <div v-else-if="!me" class="bg-white border border-slate-200 rounded-xl p-8 text-sm text-slate-500">
      We couldn't find a staff record linked to your account. Ask an admin to link you in the Staff admin.
    </div>

    <div v-else-if="subordinates.length === 0" class="bg-white border border-slate-200 rounded-xl p-8">
      <div class="text-sm font-semibold text-slate-900">No reports yet</div>
      <p class="text-sm text-slate-500 mt-1">
        No one is currently assigned to you. If this doesn't look right, let an admin know so they can set your
        manager, team lead, or department head assignments.
      </p>
      <div v-if="manager" class="mt-5 pt-5 border-t border-slate-100">
        <div class="text-[11px] uppercase tracking-wide text-slate-400 mb-2">You report to</div>
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center font-semibold">{{ initials(manager.full_name) }}</div>
          <div>
            <div class="font-semibold text-slate-900">{{ manager.full_name }}</div>
            <div class="text-xs text-slate-500">{{ manager.role }}</div>
          </div>
        </div>
      </div>
    </div>

    <div v-else class="space-y-6">
      <section class="bg-white border border-slate-200 rounded-xl p-5 flex flex-wrap gap-6 items-center">
        <div class="flex items-center gap-3">
          <div class="w-11 h-11 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center font-semibold">{{ initials(me.full_name) }}</div>
          <div>
            <div class="font-semibold text-slate-900">{{ me.full_name }}</div>
            <div class="text-xs text-slate-500">{{ me.role }}<span v-if="role"> &middot; {{ role }}</span></div>
          </div>
        </div>
        <div class="flex-1"></div>
        <div class="grid grid-cols-3 gap-4 text-center">
          <div><div class="text-2xl font-bold text-slate-900">{{ subordinates.length }}</div><div class="text-[11px] uppercase tracking-wide text-slate-500">Total reports</div></div>
          <div><div class="text-2xl font-bold text-slate-900">{{ directReports(me.id).length }}</div><div class="text-[11px] uppercase tracking-wide text-slate-500">Direct</div></div>
          <div><div class="text-2xl font-bold text-slate-900">{{ teamsLedBy(me.id).length + departmentsHeadedBy(me.id).length }}</div><div class="text-[11px] uppercase tracking-wide text-slate-500">Groups led</div></div>
        </div>
      </section>

      <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
        <header class="px-5 py-3 border-b border-slate-100 text-xs font-semibold uppercase tracking-wide text-slate-500">Reporting chain</header>
        <ul class="divide-y divide-slate-100">
          <li v-for="row in tree" :key="row.staff.id + row.via" class="px-5 py-3 flex items-center gap-3" :style="{ paddingLeft: (20 + row.depth * 24) + 'px' }">
            <button type="button" @click="toggle(row.staff.id)" class="w-5 h-5 inline-flex items-center justify-center rounded text-slate-400 hover:text-slate-700" :class="{ 'opacity-0 pointer-events-none': !hasChildren(row.staff.id) }">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4 transition-transform" :class="expanded.has(row.staff.id) ? 'rotate-90' : ''">
                <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 0-1.06L10.94 10 7.21 6.29a.75.75 0 0 1 1.08-1.04l4.25 4.25a.75.75 0 0 1 0 1.04l-4.25 4.25a.75.75 0 0 1-1.08-.02Z" clip-rule="evenodd"/>
              </svg>
            </button>
            <div class="w-9 h-9 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center text-xs font-semibold">{{ initials(row.staff.full_name) }}</div>
            <div class="flex-1 min-w-0">
              <div class="font-medium text-slate-900 truncate">{{ row.staff.full_name }}</div>
              <div class="text-xs text-slate-500 truncate">{{ row.staff.role }}<span v-if="deptName(row.staff.department_id)"> &middot; {{ deptName(row.staff.department_id) }}</span></div>
            </div>
            <span class="text-[11px] text-slate-400 uppercase tracking-wide">{{ row.via }}</span>
          </li>
        </ul>
      </section>
    </div>
  </div>
</template>
