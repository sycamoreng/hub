<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'People Analytics' })

const supabase = useSupabase()
const { ready, isAdmin } = useAuth()

interface StaffMember {
  id: string
  auth_user_id: string | null
  name: string
  department: string
  department_id: string | null
  role: string
  join_date: string | null
  exit_date: string | null
  manager_id: string | null
}

const staff = ref<StaffMember[]>([])
const leaveData = ref<any[]>([])
const attendanceData = ref<any[]>([])
const burnoutFlags = ref<any[]>([])
const loading = ref(true)
const tab = ref<'health' | 'attrition' | 'manager'>('health')

async function load() {
  loading.value = true
  const [staffRes, leaveRes, attendanceRes, burnoutRes] = await Promise.all([
    supabase
      .from('staff_members')
      .select('id, auth_user_id, full_name, role, joined_date, exited_at, manager_id, department_id, departments!staff_members_department_id_fkey(name)')
      .order('full_name'),
    supabase
      .from('leave_requests')
      .select('staff_id, start_date, end_date, working_days, status, created_at')
      .in('status', ['approved', 'pending']),
    supabase
      .from('attendance_records')
      .select('staff_id, work_date, clock_in_at, expected_start')
      .gte('work_date', new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10)),
    supabase
      .from('burnout_risk_flags')
      .select('staff_id, risk_level, resolved_at')
  ])

  staff.value = (staffRes.data ?? []).map((s: any) => ({
    id: s.id,
    auth_user_id: s.auth_user_id,
    name: s.full_name,
    department: s.departments?.name ?? '',
    department_id: s.department_id,
    role: s.role ?? '',
    join_date: s.joined_date,
    exit_date: s.exited_at,
    manager_id: s.manager_id
  }))
  leaveData.value = leaveRes.data ?? []
  attendanceData.value = attendanceRes.data ?? []
  burnoutFlags.value = burnoutRes.data ?? []
  loading.value = false
}

const activeStaff = computed(() => staff.value.filter(s => !s.exit_date))

const departmentHealth = computed(() => {
  const depts = new Map<string, {
    count: number; totalTenure: number; recentJoins: number; recentExits: number;
    leaveDays: number; lateArrivals: number; burnoutActive: number; attendanceCount: number
  }>()
  const now = Date.now()
  const sixMonths = 180 * 86400000
  const threeMonths = 90 * 86400000

  for (const s of staff.value) {
    const dept = s.department || 'Unknown'
    if (!depts.has(dept)) depts.set(dept, { count: 0, totalTenure: 0, recentJoins: 0, recentExits: 0, leaveDays: 0, lateArrivals: 0, burnoutActive: 0, attendanceCount: 0 })
    const d = depts.get(dept)!

    if (!s.exit_date) {
      d.count++
      if (s.join_date) {
        d.totalTenure += (now - new Date(s.join_date).getTime()) / 86400000 / 365
      }
      if (s.join_date && now - new Date(s.join_date).getTime() < sixMonths) d.recentJoins++
    } else {
      if (now - new Date(s.exit_date).getTime() < sixMonths) d.recentExits++
    }
  }

  const staffByDept = new Map<string, string[]>()
  for (const s of activeStaff.value) {
    const dept = s.department || 'Unknown'
    if (!staffByDept.has(dept)) staffByDept.set(dept, [])
    staffByDept.get(dept)!.push(s.id)
  }

  for (const leave of leaveData.value) {
    if (leave.status !== 'approved') continue
    const startDate = new Date(leave.start_date).getTime()
    if (now - startDate > threeMonths) continue
    const s = activeStaff.value.find(x => x.id === leave.staff_id)
    if (!s) continue
    const dept = s.department || 'Unknown'
    if (depts.has(dept)) depts.get(dept)!.leaveDays += (leave.working_days ?? 0)
  }

  for (const rec of attendanceData.value) {
    const s = activeStaff.value.find(x => x.id === rec.staff_id)
    if (!s) continue
    const dept = s.department || 'Unknown'
    if (!depts.has(dept)) continue
    depts.get(dept)!.attendanceCount++
    if (rec.clock_in_at && rec.expected_start) {
      const clockIn = new Date(rec.clock_in_at).getTime()
      const expected = new Date(rec.expected_start).getTime()
      if (clockIn > expected + 15 * 60000) depts.get(dept)!.lateArrivals++
    }
  }

  for (const flag of burnoutFlags.value) {
    if (flag.resolved_at) continue
    const s = activeStaff.value.find(x => x.id === flag.staff_id)
    if (!s) continue
    const dept = s.department || 'Unknown'
    if (depts.has(dept)) depts.get(dept)!.burnoutActive++
  }

  return [...depts.entries()]
    .map(([name, d]) => {
      const turnoverRate = d.count > 0 ? ((d.recentExits / (d.count + d.recentExits)) * 100) : 0
      const punctualityRate = d.attendanceCount > 0 ? (((d.attendanceCount - d.lateArrivals) / d.attendanceCount) * 100) : 100
      const avgLeaveDaysPerPerson = d.count > 0 ? (d.leaveDays / d.count) : 0
      const healthScore = Math.max(0, Math.min(100,
        100
        - (d.recentExits * 12)
        + (d.recentJoins * 3)
        - (d.burnoutActive * 10)
        - (turnoverRate > 20 ? 15 : 0)
        - (punctualityRate < 80 ? 10 : 0)
      ))
      return {
        name,
        count: d.count,
        avgTenure: d.count > 0 ? (d.totalTenure / d.count).toFixed(1) : '0',
        recentJoins: d.recentJoins,
        recentExits: d.recentExits,
        turnoverRate: turnoverRate.toFixed(0),
        punctualityRate: punctualityRate.toFixed(0),
        avgLeaveDays: avgLeaveDaysPerPerson.toFixed(1),
        burnoutActive: d.burnoutActive,
        healthScore: Math.round(healthScore)
      }
    })
    .filter(d => d.count > 0)
    .sort((a, b) => b.healthScore - a.healthScore)
})

const orgSummary = computed(() => {
  const active = activeStaff.value.length
  const totalExits6mo = staff.value.filter(s => s.exit_date && (Date.now() - new Date(s.exit_date).getTime()) < 180 * 86400000).length
  const avgTenure = active > 0 ? (activeStaff.value.reduce((sum, s) => sum + (s.join_date ? (Date.now() - new Date(s.join_date).getTime()) / 86400000 / 365 : 0), 0) / active).toFixed(1) : '0'
  const activeBurnout = burnoutFlags.value.filter(f => !f.resolved_at).length
  return { active, totalExits6mo, avgTenure, activeBurnout }
})

const flightRisks = computed(() => {
  return activeStaff.value
    .map(s => {
      let risk = 0
      const reasons: string[] = []

      if (s.join_date) {
        const tenure = (Date.now() - new Date(s.join_date).getTime()) / 86400000 / 365
        if (tenure >= 2 && tenure <= 3) { risk += 20; reasons.push('2-3yr tenure (common exit window)') }
        if (tenure < 0.5) { risk += 15; reasons.push('Very new (<6mo)') }
      }

      const deptExits = staff.value.filter(x => x.department === s.department && x.exit_date).length
      const deptTotal = staff.value.filter(x => x.department === s.department).length
      if (deptTotal > 0 && (deptExits / deptTotal) > 0.2) { risk += 25; reasons.push('High-turnover department') }

      const hasBurnoutFlag = burnoutFlags.value.some(f => f.staff_id === s.id && !f.resolved_at)
      if (hasBurnoutFlag) { risk += 30; reasons.push('Active burnout flag') }

      const recentLeave = leaveData.value.filter(l => l.staff_id === s.id && l.status === 'approved')
      const totalLeaveDays = recentLeave.reduce((sum, l) => sum + (l.working_days ?? 0), 0)
      if (totalLeaveDays === 0 && s.join_date) {
        const tenure = (Date.now() - new Date(s.join_date).getTime()) / 86400000
        if (tenure > 120) { risk += 15; reasons.push('No leave taken (4+ months)') }
      }

      return { ...s, riskScore: Math.min(risk, 100), reasons }
    })
    .filter(s => s.riskScore > 0)
    .sort((a, b) => b.riskScore - a.riskScore)
    .slice(0, 20)
})

const managerStats = computed(() => {
  const managers = new Map<string, { name: string; department: string; directReports: number; exits: number; totalTenure: number; burnoutFlags: number }>()

  for (const s of staff.value) {
    if (!s.manager_id) continue
    if (!managers.has(s.manager_id)) {
      const mgr = staff.value.find(x => x.id === s.manager_id)
      managers.set(s.manager_id, { name: mgr?.name ?? 'Unknown', department: mgr?.department ?? '', directReports: 0, exits: 0, totalTenure: 0, burnoutFlags: 0 })
    }
    const m = managers.get(s.manager_id)!
    if (!s.exit_date) {
      m.directReports++
      if (s.join_date) m.totalTenure += (Date.now() - new Date(s.join_date).getTime()) / 86400000 / 365
    } else {
      m.exits++
    }
  }

  for (const flag of burnoutFlags.value) {
    if (flag.resolved_at) continue
    const s = activeStaff.value.find(x => x.id === flag.staff_id)
    if (s?.manager_id && managers.has(s.manager_id)) {
      managers.get(s.manager_id)!.burnoutFlags++
    }
  }

  return [...managers.values()]
    .map(m => ({
      ...m,
      avgTenure: m.directReports > 0 ? (m.totalTenure / m.directReports).toFixed(1) : '0',
      retentionRate: (m.directReports + m.exits) > 0
        ? ((m.directReports / (m.directReports + m.exits)) * 100).toFixed(0)
        : '100',
      spanOfControl: m.directReports
    }))
    .filter(m => m.directReports > 0)
    .sort((a, b) => Number(b.retentionRate) - Number(a.retentionRate))
})

function healthColor(score: number) {
  if (score >= 80) return 'text-leaf-600'
  if (score >= 60) return 'text-amber-600'
  return 'text-red-600'
}

function healthBg(score: number) {
  if (score >= 80) return 'bg-leaf-50 border-leaf-200'
  if (score >= 60) return 'bg-amber-50 border-amber-200'
  return 'bg-red-50 border-red-200'
}

function riskBadge(score: number) {
  if (score >= 40) return 'bg-red-100 text-red-700 border-red-200'
  if (score >= 20) return 'bg-amber-100 text-amber-700 border-amber-200'
  return 'bg-slate-100 text-slate-600 border-slate-200'
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 py-8">
    <div class="mb-6">
      <h1 class="section-title">People Analytics</h1>
      <p class="section-subtitle">Team health, attrition prediction, and manager effectiveness insights</p>
    </div>

    <!-- Org-wide summary -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-slate-900">{{ orgSummary.active }}</div>
        <div class="text-xs text-slate-500 mt-1">Active Staff</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-sycamore-600">{{ orgSummary.avgTenure }}y</div>
        <div class="text-xs text-slate-500 mt-1">Avg Tenure</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-red-600">{{ orgSummary.totalExits6mo }}</div>
        <div class="text-xs text-slate-500 mt-1">Exits (6 months)</div>
      </div>
      <div class="card p-4 text-center">
        <div class="text-2xl font-bold text-amber-600">{{ orgSummary.activeBurnout }}</div>
        <div class="text-xs text-slate-500 mt-1">Burnout Flags</div>
      </div>
    </div>

    <div class="flex gap-2 mb-6">
      <button
        v-for="t in (['health', 'attrition', 'manager'] as const)"
        :key="t"
        @click="tab = t"
        class="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
        :class="tab === t ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >{{ t === 'health' ? 'Team Health' : t === 'attrition' ? 'Flight Risk' : 'Manager Effectiveness' }}</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>

    <!-- Team Health -->
    <template v-else-if="tab === 'health'">
      <div class="card p-4 mb-4 bg-sycamore-50 border-sycamore-200">
        <p class="text-sm text-sycamore-800">Health scores factor in turnover rate, new hires, burnout flags, punctuality, and leave usage across the last 3-6 months.</p>
      </div>
      <div v-if="departmentHealth.length === 0" class="card p-8 text-center text-slate-400">No department data available.</div>
      <div v-else class="space-y-3">
        <div v-for="dept in departmentHealth" :key="dept.name" class="card p-5">
          <div class="flex items-center justify-between mb-3">
            <div>
              <h3 class="font-semibold text-slate-900">{{ dept.name }}</h3>
              <span class="text-xs text-slate-500">{{ dept.count }} active members</span>
            </div>
            <div class="text-right">
              <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full border" :class="healthBg(dept.healthScore)">
                <div class="text-xl font-bold" :class="healthColor(dept.healthScore)">{{ dept.healthScore }}</div>
                <div class="text-xs text-slate-600">/ 100</div>
              </div>
            </div>
          </div>
          <div class="grid grid-cols-3 sm:grid-cols-6 gap-2 text-center text-xs">
            <div class="bg-slate-50 rounded-lg p-2.5">
              <div class="font-bold text-slate-700">{{ dept.avgTenure }}y</div>
              <div class="text-slate-500 mt-0.5">Avg Tenure</div>
            </div>
            <div class="bg-slate-50 rounded-lg p-2.5">
              <div class="font-bold text-leaf-600">+{{ dept.recentJoins }}</div>
              <div class="text-slate-500 mt-0.5">New (6mo)</div>
            </div>
            <div class="bg-slate-50 rounded-lg p-2.5">
              <div class="font-bold text-red-600">-{{ dept.recentExits }}</div>
              <div class="text-slate-500 mt-0.5">Exits (6mo)</div>
            </div>
            <div class="bg-slate-50 rounded-lg p-2.5">
              <div class="font-bold" :class="Number(dept.turnoverRate) > 15 ? 'text-red-600' : 'text-slate-700'">{{ dept.turnoverRate }}%</div>
              <div class="text-slate-500 mt-0.5">Turnover</div>
            </div>
            <div class="bg-slate-50 rounded-lg p-2.5">
              <div class="font-bold" :class="Number(dept.punctualityRate) < 85 ? 'text-amber-600' : 'text-slate-700'">{{ dept.punctualityRate }}%</div>
              <div class="text-slate-500 mt-0.5">Punctuality</div>
            </div>
            <div class="bg-slate-50 rounded-lg p-2.5">
              <div class="font-bold" :class="dept.burnoutActive > 0 ? 'text-red-600' : 'text-slate-700'">{{ dept.burnoutActive }}</div>
              <div class="text-slate-500 mt-0.5">Burnout Flags</div>
            </div>
          </div>
          <div v-if="Number(dept.turnoverRate) > 20 || dept.burnoutActive > 1 || Number(dept.punctualityRate) < 80" class="mt-3 flex flex-wrap gap-2">
            <span v-if="Number(dept.turnoverRate) > 20" class="text-[11px] px-2 py-0.5 rounded-full bg-red-50 text-red-700 border border-red-200">High turnover risk</span>
            <span v-if="dept.burnoutActive > 1" class="text-[11px] px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 border border-amber-200">Multiple burnout flags</span>
            <span v-if="Number(dept.punctualityRate) < 80" class="text-[11px] px-2 py-0.5 rounded-full bg-amber-50 text-amber-700 border border-amber-200">Low punctuality</span>
          </div>
        </div>
      </div>
    </template>

    <!-- Attrition / Flight Risk -->
    <template v-else-if="tab === 'attrition'">
      <div class="card p-4 mb-4 bg-amber-50 border-amber-200">
        <p class="text-sm text-amber-800">Flight risk scores combine tenure patterns, departmental turnover, burnout flags, and leave usage. Use as directional signals to proactively engage at-risk staff.</p>
      </div>
      <div v-if="flightRisks.length === 0" class="card p-8 text-center text-slate-400">No elevated flight risks detected.</div>
      <div v-else class="space-y-2">
        <div v-for="s in flightRisks" :key="s.id" class="card p-3 flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center text-sm font-bold text-slate-600">
            {{ s.name.split(' ').map(n => n[0]).join('').slice(0, 2) }}
          </div>
          <div class="flex-1 min-w-0">
            <div class="font-medium text-slate-900 truncate">{{ s.name }}</div>
            <div class="text-xs text-slate-500">{{ s.role }} - {{ s.department }}</div>
          </div>
          <div class="text-right">
            <span class="badge border" :class="riskBadge(s.riskScore)">{{ s.riskScore }}% risk</span>
            <div class="text-[10px] text-slate-400 mt-1 max-w-[240px] truncate">{{ s.reasons.join(', ') }}</div>
          </div>
        </div>
      </div>
    </template>

    <!-- Manager Effectiveness -->
    <template v-else>
      <div v-if="managerStats.length === 0" class="card p-8 text-center text-slate-400">No manager data available.</div>
      <div v-else class="space-y-3">
        <div v-for="m in managerStats" :key="m.name" class="card p-4">
          <div class="flex items-center justify-between">
            <div>
              <h3 class="font-semibold text-slate-900">{{ m.name }}</h3>
              <div class="text-xs text-slate-500">{{ m.department }} - {{ m.spanOfControl }} direct reports</div>
            </div>
            <div class="flex items-center gap-4 text-center">
              <div>
                <div class="text-lg font-bold" :class="Number(m.retentionRate) >= 80 ? 'text-leaf-600' : Number(m.retentionRate) >= 60 ? 'text-amber-600' : 'text-red-600'">{{ m.retentionRate }}%</div>
                <div class="text-[10px] text-slate-500">Retention</div>
              </div>
              <div>
                <div class="text-lg font-bold text-slate-700">{{ m.avgTenure }}y</div>
                <div class="text-[10px] text-slate-500">Avg Tenure</div>
              </div>
              <div>
                <div class="text-lg font-bold text-slate-700">{{ m.exits }}</div>
                <div class="text-[10px] text-slate-500">Exits</div>
              </div>
              <div v-if="m.burnoutFlags > 0">
                <div class="text-lg font-bold text-red-600">{{ m.burnoutFlags }}</div>
                <div class="text-[10px] text-slate-500">Burnout</div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
