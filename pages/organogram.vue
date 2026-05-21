<script setup lang="ts">
import { defineComponent, h } from 'vue'
import { useSupabase } from '~/utils/supabase'

const OrgNode: any = defineComponent({
  name: 'OrgNode',
  props: { node: { type: Object, required: true } },
  setup(props) {
    return () => {
      const s = (props.node as any).staff
      const children = (props.node as any).children as any[]
      const teamLabel = (props.node as any).teamLabel as string | null
      const init = (s.full_name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((p: string) => p[0]?.toUpperCase()).join('')
      const isLead = !!teamLabel && /lead$/i.test(teamLabel)
      return h('li', { class: 'org-node' }, [
        h('div', { class: ['org-card flex items-center gap-3', isLead ? 'org-card--lead' : ''] }, [
          h('div', { class: ['w-10 h-10 rounded-full flex items-center justify-center text-sm font-semibold flex-shrink-0', isLead ? 'bg-sycamore-600 text-white' : 'bg-sycamore-50 text-sycamore-700'] }, init),
          h('div', { class: 'min-w-0 flex-1' }, [
            h('div', { class: 'text-sm font-semibold text-slate-900 truncate' }, s.full_name),
            h('div', { class: 'text-xs text-slate-500 truncate' }, s.role || ''),
            teamLabel
              ? h('div', { class: 'mt-1 inline-flex items-center gap-1 text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-sycamore-50 text-sycamore-700 border border-sycamore-100' }, teamLabel)
              : null
          ])
        ]),
        children.length
          ? h('ul', { class: 'org-children' }, children.map((c: any) => h(OrgNode, { node: c })))
          : null
      ])
    }
  }
})


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
      supabase.from('staff_members').select('id, full_name, email, role, department_id, team_id, manager_id, is_active').eq('is_active', true).eq('directory_visible', true).is('exited_at', null).order('full_name')
    ])
    leadership.value = (ld ?? []).filter((l: any) => l.is_active)
    departments.value = d ?? []
    teams.value = t ?? []
    staff.value = sm ?? []
  } finally { loading.value = false }
}

function initials(name: string) {
  return (name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0]?.toUpperCase()).join('')
}

function onPhotoError(e: Event) {
  const el = e.target as HTMLImageElement
  el.style.display = 'none'
  const fallback = el.nextElementSibling as HTMLElement | null
  if (fallback) fallback.style.display = 'flex'
}

function teamLeadStaff(teamId: string) {
  const t = teams.value.find(x => x.id === teamId)
  if (!t?.lead_staff_id) return null
  return staff.value.find(s => s.id === t.lead_staff_id) ?? null
}

function teamMemberCount(teamId: string) {
  return staff.value.filter(s => s.team_id === teamId).length
}

const matchesSearch = (s: any) => {
  const q = search.value.trim().toLowerCase()
  if (!q) return true
  return (s.full_name || '').toLowerCase().includes(q)
    || (s.role || '').toLowerCase().includes(q)
    || (s.email || '').toLowerCase().includes(q)
}

// --- management reporting tree (per-department-head branch view) ---
type MgmtNode = { id: string; name: string; title: string; count?: number; children: MgmtNode[] }

const managementBranches = computed<MgmtNode[]>(() => {
  const allStaff = staff.value
  if (!allStaff.length) return []

  const teamsByDept = new Map<string, any[]>()
  for (const t of teams.value) {
    const arr = teamsByDept.get(t.department_id) || []
    arr.push(t)
    teamsByDept.set(t.department_id, arr)
  }

  const sorter = (a: any, b: any) => (a.full_name || '').localeCompare(b.full_name || '')
  const isManagerTitle = (role: string) => /lead|manager|head|director|chief|senior/i.test(role || '')

  const branches: MgmtNode[] = []

  for (const dept of departments.value) {
    if (!dept.head_staff_id) continue
    const head = allStaff.find(s => s.id === dept.head_staff_id)
    if (!head) continue

    const members = allStaff.filter(s => s.department_id === dept.id && s.id !== head.id)
    if (members.length === 0) continue

    const deptTeams = teamsByDept.get(dept.id) || []
    const teamLeadIds = new Set(deptTeams.map(t => t.lead_staff_id).filter(Boolean))
    const teamNameById = new Map(deptTeams.map(t => [t.lead_staff_id, t.name]))

    // Find key reports: people with explicit manager_id to head who have a lead/manager title,
    // OR team leads, OR people who themselves have direct reports
    const directReportIds = new Set(members.filter(m => m.manager_id === head.id).map(m => m.id))
    const hasSubordinates = new Set<string>()
    for (const m of members) {
      if (m.manager_id && members.some(x => x.id === m.manager_id)) {
        hasSubordinates.add(m.manager_id)
      }
    }

    // Key people: team leads, people with subordinates, or people with management titles who report to head
    const keyPeople = members.filter(m =>
      teamLeadIds.has(m.id) || hasSubordinates.has(m.id) || (directReportIds.has(m.id) && isManagerTitle(m.role))
    )

    if (keyPeople.length === 0) continue

    // For each key person, find their own key reports
    const buildSubReports = (managerId: string): MgmtNode[] => {
      return members
        .filter(m => m.manager_id === managerId && m.id !== managerId)
        .filter(m => teamLeadIds.has(m.id) || hasSubordinates.has(m.id) || isManagerTitle(m.role))
        .sort(sorter)
        .map(m => ({
          id: m.id,
          name: m.full_name,
          title: m.role || '',
          children: []
        }))
    }

    // Build head's direct key reports (only top-level, not nested)
    const nestedIds = new Set<string>()
    for (const kp of keyPeople) {
      if (kp.manager_id && kp.manager_id !== head.id && keyPeople.some(x => x.id === kp.manager_id)) {
        nestedIds.add(kp.id)
      }
    }

    const topKeyPeople = keyPeople
      .filter(m => !nestedIds.has(m.id))
      .sort(sorter)
      .map(m => ({
        id: m.id,
        name: m.full_name,
        title: m.role || (teamNameById.get(m.id) ? `${teamNameById.get(m.id)} Lead` : ''),
        children: buildSubReports(m.id)
      }))

    branches.push({
      id: head.id,
      name: head.full_name,
      title: head.role || dept.head_title || '',
      count: members.length,
      children: topKeyPeople
    })
  }

  // Sort branches by number of children (most complex first)
  branches.sort((a, b) => b.children.length - a.children.length)

  // Filter by search
  const q = search.value.trim().toLowerCase()
  if (!q) return branches
  const matchNode = (n: MgmtNode): boolean => {
    if (n.name.toLowerCase().includes(q) || n.title.toLowerCase().includes(q)) return true
    return n.children.some(matchNode)
  }
  const pruneNode = (n: MgmtNode): MgmtNode => ({
    ...n,
    children: n.children.filter(matchNode).map(pruneNode)
  })
  return branches.filter(matchNode).map(pruneNode)
})

const tierOrder = ['ceo', 'executive', 'senior', 'director', 'manager']
const tierLabel: Record<string, string> = {
  ceo: 'Chief Executive',
  executive: 'Executive Leadership',
  senior: 'Senior Leadership',
  director: 'Directors',
  manager: 'Managers'
}

const leadershipTiers = computed(() => {
  const filtered = leadership.value.filter(l => !search.value.trim() || (l.full_name || '').toLowerCase().includes(search.value.trim().toLowerCase()) || (l.title || '').toLowerCase().includes(search.value.trim().toLowerCase()))
  const byTier: Record<string, any[]> = {}
  for (const row of filtered) {
    let tier = (row.tier || 'executive').toLowerCase()
    if (!tierOrder.includes(tier) && /chief executive|ceo/i.test(row.title || '')) tier = 'ceo'
    ;(byTier[tier] ||= []).push(row)
  }
  return tierOrder.filter(t => byTier[t]).map(t => ({ tier: t, label: tierLabel[t] || t, people: byTier[t] }))
    .concat(Object.keys(byTier).filter(t => !tierOrder.includes(t)).map(t => ({ tier: t, label: t, people: byTier[t] })))
})

type Node = { staff: any; children: Node[]; teamLabel: string | null }

function teamsForDept(deptId: string) {
  return teams.value.filter(t => t.department_id === deptId)
}

function teamLabelFor(staffId: string, deptId: string): string | null {
  const member = staff.value.find(s => s.id === staffId)
  if (!member?.team_id) return null
  const team = teams.value.find(t => t.id === member.team_id && t.department_id === deptId)
  if (!team) return null
  if (team.lead_staff_id === staffId) return `${team.name} lead`
  return team.name
}

function buildDepartmentTree(deptId: string): Node[] {
  const members = staff.value.filter(s => s.department_id === deptId)
  const ids = new Set(members.map(m => m.id))
  const byId = new Map(members.map(m => [m.id, m]))
  const deptTeams = teamsForDept(deptId)
  const teamLeadByTeam = new Map<string, string>()
  for (const t of deptTeams) {
    if (t.lead_staff_id && ids.has(t.lead_staff_id)) teamLeadByTeam.set(t.id, t.lead_staff_id)
  }

  // Effective manager: explicit manager_id, else team lead (when not the lead themselves), else null.
  const effectiveManager = (m: any): string | null => {
    if (m.manager_id && ids.has(m.manager_id)) return m.manager_id
    if (m.team_id) {
      const lead = teamLeadByTeam.get(m.team_id)
      if (lead && lead !== m.id) return lead
    }
    return null
  }

  const childrenOf = new Map<string, any[]>()
  const roots: any[] = []
  for (const m of members) {
    const mgrId = effectiveManager(m)
    if (!mgrId) {
      roots.push(m)
    } else {
      const arr = childrenOf.get(mgrId) || []
      arr.push(m)
      childrenOf.set(mgrId, arr)
    }
  }

  const sorter = (a: any, b: any) => (a.full_name || '').localeCompare(b.full_name || '')
  const buildNode = (s: any): Node => ({
    staff: s,
    teamLabel: teamLabelFor(s.id, deptId),
    children: (childrenOf.get(s.id) || []).sort(sorter).map(buildNode)
  })

  const dept = departments.value.find(d => d.id === deptId)
  if (dept?.head_staff_id && byId.has(dept.head_staff_id)) {
    const headId = dept.head_staff_id
    const head = byId.get(headId)!
    const others = roots.filter(r => r.id !== headId).sort(sorter)
    const headChildrenSet = new Set((childrenOf.get(headId) || []).map((s: any) => s.id))
    for (const o of others) {
      if (!headChildrenSet.has(o.id)) {
        const arr = childrenOf.get(headId) || []
        arr.push(o)
        childrenOf.set(headId, arr)
      }
    }
    return [buildNode(head)]
  }
  return roots.sort(sorter).map(buildNode)
}

function nodeMatches(node: Node): boolean {
  if (matchesSearch(node.staff)) return true
  return node.children.some(nodeMatches)
}
function pruneTree(nodes: Node[]): Node[] {
  if (!search.value.trim()) return nodes
  return nodes
    .filter(nodeMatches)
    .map(n => ({ staff: n.staff, teamLabel: n.teamLabel, children: pruneTree(n.children) }))
}

const departmentTrees = computed(() => {
  return departments.value.map(d => ({
    dept: d,
    teams: teamsForDept(d.id),
    tree: pruneTree(buildDepartmentTree(d.id))
  })).filter(d => d.tree.length > 0 || !search.value.trim())
})

load()
</script>

<template>
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">
    <header class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4 mb-10">
      <div>
        <h1 class="text-3xl font-bold text-slate-900">Organogram</h1>
        <p class="text-sm text-slate-500 mt-1">Reporting structure from leadership down to every team member.</p>
      </div>
      <label class="relative w-full sm:w-72">
        <input v-model="search" type="search" placeholder="Search people or titles..."
          class="w-full border border-slate-300 rounded-full pl-10 pr-4 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4 absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><path fill-rule="evenodd" d="M9 3.5a5.5 5.5 0 1 0 3.02 10.11l3.68 3.69a.75.75 0 1 0 1.06-1.06l-3.69-3.68A5.5 5.5 0 0 0 9 3.5Zm-4 5.5a4 4 0 1 1 8 0 4 4 0 0 1-8 0Z" clip-rule="evenodd"/></svg>
      </label>
    </header>

    <div v-if="loading" class="text-sm text-slate-500">Loading organization...</div>

    <div v-else class="space-y-16">
      <section v-if="leadership.length">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-slate-500 mb-6">Leadership</h2>
        <div class="space-y-8">
          <div v-for="group in leadershipTiers" :key="group.tier" class="space-y-4">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 capitalize text-center">{{ group.label }}</div>
            <div class="flex flex-wrap justify-center gap-5">
              <article v-for="p in group.people" :key="p.id"
                class="bg-white border border-slate-200 rounded-2xl px-6 py-5 w-64 text-center shadow-sm">
                <div class="mx-auto w-16 h-16 rounded-full bg-sycamore-50 text-sycamore-700 flex items-center justify-center font-semibold overflow-hidden">
                  <img v-if="p.photo_url" :src="p.photo_url" :alt="p.full_name" referrerpolicy="no-referrer" class="w-full h-full object-cover" @error="onPhotoError" />
                  <span :style="{ display: p.photo_url ? 'none' : 'flex' }" class="w-full h-full items-center justify-center">{{ initials(p.full_name) }}</span>
                </div>
                <div class="mt-3 font-semibold text-slate-900 text-sm">{{ p.full_name }}</div>
                <div class="text-xs text-slate-500 mt-0.5">{{ p.title }}</div>
              </article>
            </div>
          </div>
        </div>
      </section>

      <section v-if="managementBranches.length">
        <h2 class="text-xs font-semibold uppercase tracking-wider text-slate-500 mb-6">Management Reporting Tree</h2>
        <p class="text-xs text-slate-400 mb-8 -mt-4">Key reports for each department head showing leads and managers.</p>
        <div class="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-3 gap-5">
          <article v-for="branch in managementBranches" :key="branch.id" class="mgmt-branch-card">
            <div class="mgmt-branch-head">
              <div class="mgmt-head-avatar">
                {{ initials(branch.name) }}
              </div>
              <div class="min-w-0 flex-1">
                <div class="text-sm font-semibold text-slate-900 truncate">{{ branch.name }}</div>
                <div class="text-xs text-slate-500 truncate">{{ branch.title }}</div>
              </div>
              <div v-if="branch.count" class="text-[10px] text-slate-400 bg-slate-100 rounded-full px-2 py-0.5 flex-shrink-0">{{ branch.count }} staff</div>
            </div>
            <div class="mgmt-reports">
              <div v-for="child in branch.children" :key="child.id" class="mgmt-report-group">
                <div class="mgmt-report-node">
                  <div class="mgmt-node-dot"></div>
                  <div class="min-w-0 flex-1">
                    <div class="text-[13px] font-medium text-slate-800 truncate">{{ child.name }}</div>
                    <div class="text-[11px] text-slate-500 truncate">{{ child.title }}</div>
                  </div>
                </div>
                <div v-if="child.children.length" class="mgmt-sub-reports">
                  <div v-for="sub in child.children" :key="sub.id" class="mgmt-report-node mgmt-report-node--sub">
                    <div class="mgmt-node-dot mgmt-node-dot--sub"></div>
                    <div class="min-w-0 flex-1">
                      <div class="text-xs font-medium text-slate-700 truncate">{{ sub.name }}</div>
                      <div class="text-[10px] text-slate-400 truncate">{{ sub.title }}</div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </article>
        </div>
      </section>

      <section>
        <h2 class="text-xs font-semibold uppercase tracking-wider text-slate-500 mb-6">Departments &amp; reporting lines</h2>
        <div class="space-y-10">
          <article v-for="d in departmentTrees" :key="d.dept.id" class="bg-white border border-slate-200 rounded-2xl overflow-hidden">
            <header class="px-6 py-5 border-b border-slate-100 bg-slate-50/60">
              <div class="flex flex-wrap items-baseline justify-between gap-3">
                <h3 class="text-base font-semibold text-slate-900">{{ d.dept.name }}</h3>
                <div v-if="d.teams.length" class="text-[11px] uppercase tracking-wide text-slate-400">
                  {{ d.teams.length }} team{{ d.teams.length === 1 ? '' : 's' }}
                </div>
              </div>
              <p v-if="d.dept.description" class="text-xs text-slate-500 mt-1">{{ d.dept.description }}</p>
              <div v-if="d.dept.head_name" class="mt-2 text-xs text-slate-500">
                Headed by <span class="font-semibold text-slate-700">{{ d.dept.head_name }}</span>
                <span v-if="d.dept.head_title"> &middot; {{ d.dept.head_title }}</span>
              </div>
            </header>
            <div v-if="d.teams.length" class="px-6 sm:px-8 pt-5">
              <div class="text-[10px] uppercase tracking-wider text-slate-400 font-semibold mb-3">Teams &amp; leads</div>
              <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                <div v-for="t in d.teams" :key="t.id"
                  class="flex items-center gap-3 bg-sycamore-50/40 border border-sycamore-100 rounded-xl px-3.5 py-3">
                  <template v-if="teamLeadStaff(t.id)">
                    <div class="w-10 h-10 rounded-full bg-white border border-sycamore-200 text-sycamore-700 flex items-center justify-center text-xs font-semibold flex-shrink-0">
                      {{ initials(teamLeadStaff(t.id)!.full_name) }}
                    </div>
                    <div class="min-w-0 flex-1">
                      <div class="text-sm font-semibold text-slate-900 truncate">{{ t.name }}</div>
                      <div class="text-[11px] text-sycamore-700 font-medium truncate">
                        Led by {{ teamLeadStaff(t.id)!.full_name }}
                      </div>
                      <div class="text-[10px] text-slate-500">{{ teamMemberCount(t.id) }} member{{ teamMemberCount(t.id) === 1 ? '' : 's' }}</div>
                    </div>
                  </template>
                  <template v-else>
                    <div class="w-10 h-10 rounded-full bg-white border border-dashed border-slate-300 text-slate-400 flex items-center justify-center text-xs font-semibold flex-shrink-0">—</div>
                    <div class="min-w-0 flex-1">
                      <div class="text-sm font-semibold text-slate-900 truncate">{{ t.name }}</div>
                      <div class="text-[11px] text-amber-700 font-medium truncate">No team lead assigned</div>
                      <div class="text-[10px] text-slate-500">{{ teamMemberCount(t.id) }} member{{ teamMemberCount(t.id) === 1 ? '' : 's' }}</div>
                    </div>
                  </template>
                </div>
              </div>
            </div>
            <div class="px-5 sm:px-7 pt-3 pb-5">
              <div v-if="d.tree.length === 0" class="text-xs text-slate-400 italic">No active members.</div>
              <ul v-else class="org-tree">
                <OrgNode v-for="n in d.tree" :key="n.staff.id" :node="n" />
              </ul>
            </div>
          </article>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.org-tree, .org-children {
  list-style: none;
  margin: 0;
  padding: 0;
}
.org-tree {
  display: flex;
  flex-direction: column;
  gap: 1.5rem;
}
.org-children {
  margin-top: 1.25rem;
  margin-left: 1.75rem;
  border-left: 2px solid theme('colors.slate.200');
  padding-left: 1.75rem;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
}
.org-node {
  position: relative;
}
.org-children > .org-node::before {
  content: '';
  position: absolute;
  left: -1.75rem;
  top: 1.75rem;
  width: 1.5rem;
  border-top: 2px solid theme('colors.slate.200');
}
.org-card {
  background: #fff;
  border: 1px solid theme('colors.slate.200');
  border-radius: 0.875rem;
  padding: 0.875rem 1.125rem;
  transition: border-color .15s ease, box-shadow .15s ease;
}
.org-card:hover {
  border-color: theme('colors.sycamore.200');
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.05);
}
.org-card--lead {
  border-color: theme('colors.sycamore.300');
  background: theme('colors.sycamore.50');
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.05);
}

/* --- Management Reporting Tree (branch cards) --- */
.mgmt-branch-card {
  background: #fff;
  border: 1px solid theme('colors.slate.200');
  border-radius: 1rem;
  overflow: hidden;
  transition: box-shadow .15s ease;
}
.mgmt-branch-card:hover {
  box-shadow: 0 2px 12px rgba(15, 23, 42, 0.06);
}
.mgmt-branch-head {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 1rem 1.25rem;
  border-bottom: 1px solid theme('colors.slate.100');
  background: theme('colors.slate.50');
}
.mgmt-head-avatar {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 9999px;
  background: theme('colors.sycamore.600');
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.75rem;
  font-weight: 600;
  flex-shrink: 0;
}
.mgmt-reports {
  padding: 0.75rem 0 0.5rem 0;
}
.mgmt-report-group {
  position: relative;
}
.mgmt-report-node {
  display: flex;
  align-items: center;
  gap: 0.625rem;
  padding: 0.5rem 1.25rem 0.5rem 1.75rem;
  position: relative;
}
.mgmt-report-node::before {
  content: '';
  position: absolute;
  left: 1.25rem;
  top: 0;
  bottom: 0;
  width: 1px;
  background: theme('colors.slate.200');
}
.mgmt-report-group:first-child > .mgmt-report-node::before {
  top: 50%;
}
.mgmt-report-group:last-child > .mgmt-report-node::before {
  bottom: 50%;
}
.mgmt-report-group:only-child > .mgmt-report-node::before {
  display: none;
}
.mgmt-node-dot {
  width: 8px;
  height: 8px;
  border-radius: 9999px;
  background: theme('colors.sycamore.400');
  flex-shrink: 0;
  position: relative;
  z-index: 1;
}
.mgmt-node-dot--sub {
  width: 6px;
  height: 6px;
  background: theme('colors.slate.300');
}
.mgmt-sub-reports {
  padding-left: 1.5rem;
}
.mgmt-report-node--sub {
  padding: 0.325rem 1.25rem 0.325rem 1.75rem;
}
.mgmt-report-node--sub::before {
  left: 1.25rem;
}
.mgmt-sub-reports > .mgmt-report-node--sub:first-child::before {
  top: 50%;
}
.mgmt-sub-reports > .mgmt-report-node--sub:last-child::before {
  bottom: 50%;
}
.mgmt-sub-reports > .mgmt-report-node--sub:only-child::before {
  display: none;
}
</style>
