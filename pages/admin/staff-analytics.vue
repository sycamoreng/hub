<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const loading = ref(true)

interface StaffRow {
  id: string
  full_name: string
  gender: string | null
  joined_date: string | null
  department_id: string | null
  is_active: boolean
  exited_at: string | null
}

interface DobRow {
  id: string
  date_of_birth: string | null
}

interface DeptRow {
  id: string
  name: string
}

const staff = ref<StaffRow[]>([])
const dobs = ref<Record<string, string | null>>({})
const departments = ref<DeptRow[]>([])

onMounted(async () => {
  try {
    const [staffRes, dobRes, deptRes] = await Promise.all([
      supabase.from('staff_members').select('id, full_name, gender, joined_date, department_id, is_active, exited_at'),
      supabase.from('staff_private_data').select('id, date_of_birth'),
      supabase.from('departments').select('id, name').order('name')
    ])
    staff.value = staffRes.data ?? []
    const dobMap: Record<string, string | null> = {}
    for (const row of (dobRes.data ?? []) as DobRow[]) {
      dobMap[row.id] = row.date_of_birth
    }
    dobs.value = dobMap
    departments.value = deptRes.data ?? []
  } finally {
    loading.value = false
  }
})

const activeStaff = computed(() => staff.value.filter(s => s.is_active && !s.exited_at))
const exitedStaff = computed(() => staff.value.filter(s => !!s.exited_at))

// --- Gender ---
const genderStats = computed(() => {
  const active = activeStaff.value
  const male = active.filter(s => s.gender === 'male').length
  const female = active.filter(s => s.gender === 'female').length
  const unset = active.length - male - female
  return { male, female, unset, total: active.length }
})

const genderPercent = computed(() => {
  const t = genderStats.value.total || 1
  return {
    male: Math.round((genderStats.value.male / t) * 100),
    female: Math.round((genderStats.value.female / t) * 100)
  }
})

// --- Age Groups ---
function getAge(dob: string): number {
  const birth = new Date(dob)
  const today = new Date()
  let age = today.getFullYear() - birth.getFullYear()
  const m = today.getMonth() - birth.getMonth()
  if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) age--
  return age
}

const ageGroups = computed(() => {
  const groups: Record<string, number> = {
    '18-24': 0,
    '25-29': 0,
    '30-34': 0,
    '35-39': 0,
    '40-44': 0,
    '45-49': 0,
    '50+': 0
  }
  for (const s of activeStaff.value) {
    const dob = dobs.value[s.id]
    if (!dob) continue
    const age = getAge(dob)
    if (age < 25) groups['18-24']++
    else if (age < 30) groups['25-29']++
    else if (age < 35) groups['30-34']++
    else if (age < 40) groups['35-39']++
    else if (age < 45) groups['40-44']++
    else if (age < 50) groups['45-49']++
    else groups['50+']++
  }
  return groups
})

const ageMax = computed(() => Math.max(...Object.values(ageGroups.value), 1))

const generations = computed(() => {
  const gen: Record<string, number> = {
    'Gen Z (1997-2012)': 0,
    'Millennials (1981-1996)': 0,
    'Gen X (1965-1980)': 0,
    'Boomers (1946-1964)': 0
  }
  for (const s of activeStaff.value) {
    const dob = dobs.value[s.id]
    if (!dob) continue
    const year = new Date(dob).getFullYear()
    if (year >= 1997) gen['Gen Z (1997-2012)']++
    else if (year >= 1981) gen['Millennials (1981-1996)']++
    else if (year >= 1965) gen['Gen X (1965-1980)']++
    else gen['Boomers (1946-1964)']++
  }
  return gen
})

// --- Service Duration ---
function getYearsOfService(joinedDate: string): number {
  const joined = new Date(joinedDate)
  const today = new Date()
  let years = today.getFullYear() - joined.getFullYear()
  const m = today.getMonth() - joined.getMonth()
  if (m < 0 || (m === 0 && today.getDate() < joined.getDate())) years--
  return Math.max(0, years)
}

const serviceBuckets = computed(() => {
  const buckets: Record<string, number> = {
    'New hires (<1 yr)': 0,
    '1-2 years': 0,
    '3-4 years': 0,
    '5-7 years': 0,
    '8+ years': 0
  }
  for (const s of activeStaff.value) {
    if (!s.joined_date) continue
    const yrs = getYearsOfService(s.joined_date)
    if (yrs < 1) buckets['New hires (<1 yr)']++
    else if (yrs <= 2) buckets['1-2 years']++
    else if (yrs <= 4) buckets['3-4 years']++
    else if (yrs <= 7) buckets['5-7 years']++
    else buckets['8+ years']++
  }
  return buckets
})

const serviceMax = computed(() => Math.max(...Object.values(serviceBuckets.value), 1))

// --- Department Distribution ---
const departmentStats = computed(() => {
  const map: Record<string, number> = {}
  for (const s of activeStaff.value) {
    const dept = s.department_id
    if (!dept) continue
    map[dept] = (map[dept] || 0) + 1
  }
  return departments.value
    .map(d => ({ name: d.name, count: map[d.id] || 0 }))
    .filter(d => d.count > 0)
    .sort((a, b) => b.count - a.count)
})

const deptMax = computed(() => Math.max(...departmentStats.value.map(d => d.count), 1))

// --- Department Gender Split ---
const deptGenderStats = computed(() => {
  const map: Record<string, { male: number; female: number }> = {}
  for (const s of activeStaff.value) {
    if (!s.department_id) continue
    if (!map[s.department_id]) map[s.department_id] = { male: 0, female: 0 }
    if (s.gender === 'male') map[s.department_id].male++
    else if (s.gender === 'female') map[s.department_id].female++
  }
  return departments.value
    .map(d => ({
      name: d.name,
      male: map[d.id]?.male ?? 0,
      female: map[d.id]?.female ?? 0,
      total: (map[d.id]?.male ?? 0) + (map[d.id]?.female ?? 0)
    }))
    .filter(d => d.total > 0)
    .sort((a, b) => b.total - a.total)
})

// --- Average Age ---
const averageAge = computed(() => {
  let sum = 0, count = 0
  for (const s of activeStaff.value) {
    const dob = dobs.value[s.id]
    if (!dob) continue
    sum += getAge(dob)
    count++
  }
  return count > 0 ? Math.round(sum / count) : 0
})

// --- Average Service ---
const averageService = computed(() => {
  let sum = 0, count = 0
  for (const s of activeStaff.value) {
    if (!s.joined_date) continue
    sum += getYearsOfService(s.joined_date)
    count++
  }
  return count > 0 ? (sum / count).toFixed(1) : '0'
})

// --- Turnover ---
const turnoverRate = computed(() => {
  const total = staff.value.length
  if (total === 0) return '0'
  return ((exitedStaff.value.length / total) * 100).toFixed(1)
})

// --- Upcoming Birthdays (next 7 days) ---
const upcomingBirthdays = computed(() => {
  const today = new Date()
  const results: { name: string; date: string; daysAway: number }[] = []
  for (const s of activeStaff.value) {
    const dob = dobs.value[s.id]
    if (!dob) continue
    const birth = new Date(dob)
    const thisYear = new Date(today.getFullYear(), birth.getMonth(), birth.getDate())
    if (thisYear < today) thisYear.setFullYear(today.getFullYear() + 1)
    const diff = Math.ceil((thisYear.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))
    if (diff <= 7) results.push({ name: s.full_name, date: thisYear.toLocaleDateString('en-NG', { month: 'short', day: 'numeric' }), daysAway: diff })
  }
  return results.sort((a, b) => a.daysAway - b.daysAway)
})

// --- Upcoming Anniversaries (next 7 days) ---
const upcomingAnniversaries = computed(() => {
  const today = new Date()
  const results: { name: string; years: number; date: string; daysAway: number }[] = []
  for (const s of activeStaff.value) {
    if (!s.joined_date) continue
    const joined = new Date(s.joined_date)
    const thisYear = new Date(today.getFullYear(), joined.getMonth(), joined.getDate())
    if (thisYear < today) thisYear.setFullYear(today.getFullYear() + 1)
    const diff = Math.ceil((thisYear.getTime() - today.getTime()) / (1000 * 60 * 60 * 24))
    const years = thisYear.getFullYear() - joined.getFullYear()
    if (diff <= 7 && years > 0) results.push({ name: s.full_name, years, date: thisYear.toLocaleDateString('en-NG', { month: 'short', day: 'numeric' }), daysAway: diff })
  }
  return results.sort((a, b) => a.daysAway - b.daysAway)
})
</script>

<template>
  <div class="max-w-7xl">
    <div class="mb-8">
      <h1 class="section-title">Staff Analytics</h1>
      <p class="section-subtitle">Workforce composition, demographics and service insights.</p>
    </div>

    <div v-if="loading" class="text-center py-16 text-slate-400">Loading analytics...</div>

    <div v-else>
      <!-- KPI Summary Cards -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 sm:gap-4 mb-8">
        <div class="card p-3 sm:p-5">
          <div class="text-xl sm:text-3xl font-bold text-slate-900">{{ activeStaff.length }}</div>
          <div class="text-xs sm:text-sm text-slate-500 mt-0.5 sm:mt-1">Active staff</div>
        </div>
        <div class="card p-3 sm:p-5">
          <div class="text-xl sm:text-3xl font-bold text-slate-900">{{ averageAge || '—' }}</div>
          <div class="text-xs sm:text-sm text-slate-500 mt-0.5 sm:mt-1">Average age</div>
        </div>
        <div class="card p-3 sm:p-5">
          <div class="text-xl sm:text-3xl font-bold text-slate-900">{{ averageService }}</div>
          <div class="text-xs sm:text-sm text-slate-500 mt-0.5 sm:mt-1">Avg. service</div>
        </div>
        <div class="card p-3 sm:p-5">
          <div class="text-xl sm:text-3xl font-bold text-slate-900">{{ turnoverRate }}%</div>
          <div class="text-xs sm:text-sm text-slate-500 mt-0.5 sm:mt-1">Turnover rate</div>
        </div>
      </div>

      <!-- Grid of charts -->
      <div class="grid lg:grid-cols-2 gap-6 mb-8">
        <!-- Gender Ratio -->
        <div class="card p-6">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Gender Distribution</h2>
          <div class="flex items-center gap-6">
            <!-- Donut-like visual -->
            <div class="relative w-32 h-32 flex-shrink-0">
              <svg viewBox="0 0 36 36" class="w-32 h-32 -rotate-90">
                <circle cx="18" cy="18" r="15.9" fill="none" stroke="#e2e8f0" stroke-width="3" />
                <circle
                  cx="18" cy="18" r="15.9" fill="none"
                  stroke="#2563eb" stroke-width="3"
                  :stroke-dasharray="`${genderPercent.male} ${100 - genderPercent.male}`"
                  stroke-dashoffset="0"
                />
                <circle
                  cx="18" cy="18" r="15.9" fill="none"
                  stroke="#ec4899" stroke-width="3"
                  :stroke-dasharray="`${genderPercent.female} ${100 - genderPercent.female}`"
                  :stroke-dashoffset="`${-(genderPercent.male)}`"
                />
              </svg>
              <div class="absolute inset-0 flex flex-col items-center justify-center">
                <span class="text-lg font-bold text-slate-900">{{ genderStats.total }}</span>
                <span class="text-[10px] text-slate-400">staff</span>
              </div>
            </div>
            <div class="flex flex-col gap-3">
              <div class="flex items-center gap-2">
                <span class="w-3 h-3 rounded-full bg-blue-600"></span>
                <span class="text-sm text-slate-700">Male: <strong>{{ genderStats.male }}</strong> ({{ genderPercent.male }}%)</span>
              </div>
              <div class="flex items-center gap-2">
                <span class="w-3 h-3 rounded-full bg-pink-500"></span>
                <span class="text-sm text-slate-700">Female: <strong>{{ genderStats.female }}</strong> ({{ genderPercent.female }}%)</span>
              </div>
              <div v-if="genderStats.unset" class="flex items-center gap-2">
                <span class="w-3 h-3 rounded-full bg-slate-200"></span>
                <span class="text-sm text-slate-400">Not set: {{ genderStats.unset }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- Generations -->
        <div class="card p-6">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Generational Breakdown</h2>
          <div class="space-y-3">
            <div v-for="(count, label) in generations" :key="label" class="flex items-center gap-3">
              <span class="text-xs text-slate-500 w-36 shrink-0">{{ label }}</span>
              <div class="flex-1 bg-slate-100 rounded-full h-5 overflow-hidden">
                <div
                  class="h-full rounded-full bg-sycamore-500 transition-all duration-500"
                  :style="{ width: `${(count / (activeStaff.length || 1)) * 100}%` }"
                ></div>
              </div>
              <span class="text-sm font-semibold text-slate-700 w-8 text-right">{{ count }}</span>
            </div>
          </div>
        </div>

        <!-- Age Groups -->
        <div class="card p-6">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Age Distribution</h2>
          <div class="space-y-2">
            <div v-for="(count, label) in ageGroups" :key="label" class="flex items-center gap-3">
              <span class="text-xs text-slate-500 w-14 shrink-0">{{ label }}</span>
              <div class="flex-1 bg-slate-100 rounded-full h-5 overflow-hidden">
                <div
                  class="h-full rounded-full bg-teal-500 transition-all duration-500"
                  :style="{ width: `${(count / ageMax) * 100}%` }"
                ></div>
              </div>
              <span class="text-sm font-semibold text-slate-700 w-8 text-right">{{ count }}</span>
            </div>
          </div>
        </div>

        <!-- Service Duration -->
        <div class="card p-6">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Service Duration</h2>
          <div class="space-y-2">
            <div v-for="(count, label) in serviceBuckets" :key="label" class="flex items-center gap-3">
              <span class="text-xs text-slate-500 w-28 shrink-0">{{ label }}</span>
              <div class="flex-1 bg-slate-100 rounded-full h-5 overflow-hidden">
                <div
                  class="h-full rounded-full bg-amber-500 transition-all duration-500"
                  :style="{ width: `${(count / serviceMax) * 100}%` }"
                ></div>
              </div>
              <span class="text-sm font-semibold text-slate-700 w-8 text-right">{{ count }}</span>
            </div>
          </div>
        </div>

        <!-- Department Distribution -->
        <div class="card p-6 lg:col-span-2">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Department Distribution</h2>
          <div class="grid sm:grid-cols-2 gap-x-8 gap-y-2">
            <div v-for="dept in departmentStats" :key="dept.name" class="flex items-center gap-3">
              <span class="text-xs text-slate-500 w-32 shrink-0 truncate" :title="dept.name">{{ dept.name }}</span>
              <div class="flex-1 bg-slate-100 rounded-full h-4 overflow-hidden">
                <div
                  class="h-full rounded-full bg-sycamore-600 transition-all duration-500"
                  :style="{ width: `${(dept.count / deptMax) * 100}%` }"
                ></div>
              </div>
              <span class="text-xs font-semibold text-slate-700 w-6 text-right">{{ dept.count }}</span>
            </div>
          </div>
        </div>

        <!-- Department Gender Split -->
        <div class="card p-6 lg:col-span-2">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Department Gender Split</h2>
          <div class="flex items-center gap-4 mb-4">
            <div class="flex items-center gap-1.5">
              <span class="w-3 h-3 rounded-full bg-blue-600"></span>
              <span class="text-xs text-slate-500">Male</span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="w-3 h-3 rounded-full bg-pink-500"></span>
              <span class="text-xs text-slate-500">Female</span>
            </div>
          </div>
          <div class="space-y-3">
            <div v-for="dept in deptGenderStats" :key="dept.name" class="flex items-center gap-3">
              <span class="text-xs text-slate-500 w-32 shrink-0 truncate" :title="dept.name">{{ dept.name }}</span>
              <div class="flex-1 bg-slate-100 rounded-full h-5 overflow-hidden flex">
                <div
                  class="h-full bg-blue-600 transition-all duration-500"
                  :style="{ width: `${(dept.male / dept.total) * 100}%` }"
                ></div>
                <div
                  class="h-full bg-pink-500 transition-all duration-500"
                  :style="{ width: `${(dept.female / dept.total) * 100}%` }"
                ></div>
              </div>
              <span class="text-xs text-slate-500 w-16 text-right shrink-0">{{ dept.male }}M / {{ dept.female }}F</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Upcoming Events -->
      <div class="grid lg:grid-cols-2 gap-6">
        <!-- Upcoming Birthdays -->
        <div class="card p-6">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Upcoming Birthdays (7 days)</h2>
          <div v-if="upcomingBirthdays.length === 0" class="text-sm text-slate-400">No birthdays in the next 7 days.</div>
          <div v-else class="space-y-2">
            <div v-for="b in upcomingBirthdays" :key="b.name" class="flex items-center justify-between py-2 border-b border-slate-50 last:border-0">
              <span class="text-sm text-slate-700 font-medium">{{ b.name }}</span>
              <span class="text-xs px-2 py-1 rounded-full" :class="b.daysAway === 0 ? 'bg-sycamore-50 text-sycamore-700 font-semibold' : 'bg-slate-100 text-slate-500'">
                {{ b.daysAway === 0 ? 'Today' : `${b.date}` }}
              </span>
            </div>
          </div>
        </div>

        <!-- Upcoming Anniversaries -->
        <div class="card p-6">
          <h2 class="text-base font-semibold text-slate-900 mb-4">Upcoming Work Anniversaries (7 days)</h2>
          <div v-if="upcomingAnniversaries.length === 0" class="text-sm text-slate-400">No anniversaries in the next 7 days.</div>
          <div v-else class="space-y-2">
            <div v-for="a in upcomingAnniversaries" :key="a.name" class="flex items-center justify-between py-2 border-b border-slate-50 last:border-0">
              <div>
                <span class="text-sm text-slate-700 font-medium">{{ a.name }}</span>
                <span class="text-xs text-slate-400 ml-2">{{ a.years }} {{ a.years === 1 ? 'year' : 'years' }}</span>
              </div>
              <span class="text-xs px-2 py-1 rounded-full" :class="a.daysAway === 0 ? 'bg-sycamore-50 text-sycamore-700 font-semibold' : 'bg-slate-100 text-slate-500'">
                {{ a.daysAway === 0 ? 'Today' : `${a.date}` }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
