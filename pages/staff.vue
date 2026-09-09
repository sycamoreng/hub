<script setup lang="ts">
import type { UserProfile } from '~/composables/useProfile'
import { useSupabase } from '~/utils/supabase'

const { fetchStaff, fetchDepartments, fetchLocations } = useCompanyData()
const { fetchProfilesByUserIds } = useProfile()
const { user, profileSyncTick } = useAuth()
const supabase = useSupabase()
const route = useRoute()

const staff = ref<any[]>([])
const exited = ref<any[]>([])
const departments = ref<any[]>([])
const locations = ref<any[]>([])
const profilesByUid = ref<Record<string, UserProfile>>({})
const search = ref('')
const selectedDept = ref('All')
const selectedLocation = ref('All')
const loading = ref(true)
const view = ref<'active' | 'new_hires' | 'exited'>('active')

async function load() {
  loading.value = true
  try {
    const [s, d, locs, ex] = await Promise.all([
      fetchStaff(),
      fetchDepartments(),
      fetchLocations(),
      supabase.from('staff_directory_exited').select('*').order('full_name')
    ])
    staff.value = s
    departments.value = d
    locations.value = locs
    exited.value = (ex.data ?? []) as any[]
    const uids = [
      ...(s as any[]).map(r => r.auth_user_id).filter(Boolean),
      ...(exited.value as any[]).map(r => r.auth_user_id).filter(Boolean)
    ]
    profilesByUid.value = uids.length ? await fetchProfilesByUserIds(uids) : {}
    const locQuery = (route.query.location as string | undefined)
    if (locQuery) {
      selectedLocation.value = locQuery
    }
  } finally { loading.value = false }
}

onMounted(load)
watch([() => user.value?.id, () => profileSyncTick.value], () => load())

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return staff.value.filter(s => {
    const deptOk = selectedDept.value === 'All' || s.departments?.name === selectedDept.value
    if (!deptOk) return false
    const locOk = selectedLocation.value === 'All' || s.locations?.name === selectedLocation.value
    if (!locOk) return false
    if (!q) return true
    return s.full_name.toLowerCase().includes(q) || s.role.toLowerCase().includes(q) || s.email.toLowerCase().includes(q)
  })
})

const newHires = computed(() => {
  const cutoff = new Date()
  cutoff.setDate(cutoff.getDate() - 90)
  const cutoffStr = cutoff.toISOString().split('T')[0]
  return staff.value
    .filter(s => s.joined_date && s.joined_date >= cutoffStr)
    .sort((a, b) => (b.joined_date || '').localeCompare(a.joined_date || ''))
})

const filteredNewHires = computed(() => {
  const q = search.value.trim().toLowerCase()
  return newHires.value.filter(s => {
    const deptOk = selectedDept.value === 'All' || s.departments?.name === selectedDept.value
    if (!deptOk) return false
    const locOk = selectedLocation.value === 'All' || s.locations?.name === selectedLocation.value
    if (!locOk) return false
    if (!q) return true
    return s.full_name.toLowerCase().includes(q) || s.role.toLowerCase().includes(q) || s.email.toLowerCase().includes(q)
  })
})

const filteredExited = computed(() => {
  const q = search.value.trim().toLowerCase()
  return exited.value.filter(s => {
    const deptOk = selectedDept.value === 'All' || s.department_name === selectedDept.value
    if (!deptOk) return false
    const locOk = selectedLocation.value === 'All' || s.location_name === selectedLocation.value
    if (!locOk) return false
    if (!q) return true
    return (s.full_name || '').toLowerCase().includes(q)
      || (s.role || '').toLowerCase().includes(q)
      || (s.email || '').toLowerCase().includes(q)
  })
})

function fmtDate(iso: string | null | undefined) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
}

function initials(name: string) {
  return name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
}

function avatar(s: any): string | null {
  if (s.auth_user_id && profilesByUid.value[s.auth_user_id]?.avatar_url) {
    return profilesByUid.value[s.auth_user_id]!.avatar_url
  }
  return s.avatar_url || null
}
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="mb-5 sm:mb-8">
      <h1 class="section-title">Staff Directory</h1>
      <p class="section-subtitle">Meet the people who make Sycamore thrive.</p>
    </div>

    <div class="flex gap-1 bg-slate-100 rounded-lg p-1 mb-4 w-full sm:w-fit overflow-x-auto">
      <button type="button" @click="view = 'active'"
        class="text-xs font-semibold px-3 py-2 sm:py-1.5 rounded-md flex-1 sm:flex-none whitespace-nowrap"
        :class="view === 'active' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        Active <span class="ml-1 text-slate-400">{{ staff.length }}</span>
      </button>
      <button type="button" @click="view = 'new_hires'"
        class="text-xs font-semibold px-3 py-2 sm:py-1.5 rounded-md flex-1 sm:flex-none whitespace-nowrap"
        :class="view === 'new_hires' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        New Hires <span class="ml-1 text-slate-400">{{ newHires.length }}</span>
      </button>
      <button type="button" @click="view = 'exited'"
        class="text-xs font-semibold px-3 py-2 sm:py-1.5 rounded-md flex-1 sm:flex-none whitespace-nowrap"
        :class="view === 'exited' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        Exited <span class="ml-1 text-slate-400">{{ exited.length }}</span>
      </button>
    </div>

    <div class="card p-3 sm:p-4 mb-5 sm:mb-6 flex flex-col sm:flex-row gap-3">
      <div class="relative flex-1">
        <input v-model="search" type="text" placeholder="Search by name, role, or email..." class="input pl-10" />
        <div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400"><SidebarIcon name="search" /></div>
      </div>
      <select v-model="selectedDept" class="input sm:w-56">
        <option value="All">All departments</option>
        <option v-for="d in departments" :key="d.id" :value="d.name">{{ d.name }}</option>
      </select>
      <select v-model="selectedLocation" class="input sm:w-56">
        <option value="All">All locations</option>
        <option v-for="l in locations" :key="l.id" :value="l.name">{{ l.name }}</option>
      </select>
    </div>

    <div v-if="loading" class="text-slate-400">Loading staff...</div>

    <template v-else-if="view === 'active'">
    <div v-if="filtered.length === 0" class="text-slate-400">No staff match your filters.</div>

    <!-- Mobile: contact list style -->
    <div class="sm:hidden divide-y divide-slate-100">
      <NuxtLink
        v-for="s in filtered"
        :key="s.id"
        :to="`/profile/${s.id}`"
        class="flex items-center gap-3 py-3 px-1 active:bg-slate-50 transition-colors"
      >
        <div class="relative flex-shrink-0">
          <img
            v-if="avatar(s)"
            :src="avatar(s)!"
            :alt="s.full_name"
            referrerpolicy="no-referrer"
            class="w-12 h-12 rounded-full object-cover border border-slate-200"
          />
          <div v-else class="w-12 h-12 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-base">
            {{ initials(s.full_name) }}
          </div>
          <span
            v-if="s.auth_user_id"
            class="absolute -bottom-0.5 -right-0.5 w-3.5 h-3.5 rounded-full bg-emerald-500 ring-2 ring-white"
          />
        </div>
        <div class="min-w-0 flex-1">
          <h3 class="font-semibold text-[15px] text-slate-900 truncate leading-tight">{{ s.full_name }}</h3>
          <div class="text-[13px] text-slate-500 truncate mt-0.5">{{ s.role }}</div>
          <div class="flex items-center gap-2 mt-1">
            <span v-if="s.departments?.name" class="text-[11px] font-medium text-leaf-700 bg-leaf-50 px-1.5 py-0.5 rounded">{{ s.departments.name }}</span>
            <span v-if="s.locations" class="text-[11px] text-slate-400">{{ s.locations.city }}</span>
          </div>
        </div>
        <div class="text-slate-300 flex-shrink-0">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 .02-1.06L11.168 10 7.23 6.29a.75.75 0 1 1 1.04-1.08l4.5 4.25a.75.75 0 0 1 0 1.08l-4.5 4.25a.75.75 0 0 1-1.06-.02Z" clip-rule="evenodd" /></svg>
        </div>
      </NuxtLink>
    </div>

    <!-- Desktop: grid cards -->
    <div class="hidden sm:grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <NuxtLink v-for="s in filtered" :key="s.id" :to="`/profile/${s.id}`" class="card card-hover p-5 flex gap-4">
        <div class="relative flex-shrink-0">
          <img
            v-if="avatar(s)"
            :src="avatar(s)!"
            :alt="s.full_name"
            referrerpolicy="no-referrer"
            class="w-14 h-14 rounded-full object-cover border border-slate-200"
          />
          <div v-else class="w-14 h-14 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-lg">
            {{ initials(s.full_name) }}
          </div>
          <span
            v-if="s.auth_user_id"
            title="Profile claimed"
            class="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-emerald-500 ring-2 ring-white"
          />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-1.5">
            <h3 class="font-semibold text-slate-900 truncate">{{ s.full_name }}</h3>
          </div>
          <div class="text-sm text-slate-600 truncate">{{ s.role }}</div>
          <div class="text-xs text-slate-500 mt-1">
            <span v-if="s.departments?.name" class="badge badge-green">{{ s.departments.name }}</span>
          </div>
          <div class="text-xs text-slate-500 mt-2 truncate">{{ s.email }}</div>
          <div v-if="s.locations" class="text-xs text-slate-400 mt-0.5">{{ s.locations.city }}</div>
        </div>
      </NuxtLink>
    </div>
    </template>

    <template v-else-if="view === 'new_hires'">
      <div v-if="filteredNewHires.length === 0" class="text-slate-400">No new hires in the last 90 days.</div>

      <!-- Mobile: list style -->
      <div class="sm:hidden divide-y divide-slate-100">
        <NuxtLink
          v-for="s in filteredNewHires"
          :key="s.id"
          :to="`/profile/${s.id}`"
          class="flex items-center gap-3 py-3 px-1 active:bg-slate-50 transition-colors"
        >
          <div class="relative flex-shrink-0">
            <img
              v-if="avatar(s)"
              :src="avatar(s)!"
              :alt="s.full_name"
              referrerpolicy="no-referrer"
              class="w-12 h-12 rounded-full object-cover border border-slate-200"
            />
            <div v-else class="w-12 h-12 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-base">
              {{ initials(s.full_name) }}
            </div>
            <span class="absolute -top-0.5 -right-0.5 w-4 h-4 rounded-full bg-sycamore-500 ring-2 ring-white flex items-center justify-center text-[8px] text-white font-bold">N</span>
          </div>
          <div class="min-w-0 flex-1">
            <h3 class="font-semibold text-[15px] text-slate-900 truncate leading-tight">{{ s.full_name }}</h3>
            <div class="text-[13px] text-slate-500 truncate mt-0.5">{{ s.role }}</div>
            <div class="text-[11px] text-slate-400 mt-1">Joined {{ fmtDate(s.joined_date) }}</div>
          </div>
          <div class="text-slate-300 flex-shrink-0">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 .02-1.06L11.168 10 7.23 6.29a.75.75 0 1 1 1.04-1.08l4.5 4.25a.75.75 0 0 1 0 1.08l-4.5 4.25a.75.75 0 0 1-1.06-.02Z" clip-rule="evenodd" /></svg>
          </div>
        </NuxtLink>
      </div>

      <!-- Desktop: grid -->
      <div class="hidden sm:grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <NuxtLink v-for="s in filteredNewHires" :key="s.id" :to="`/profile/${s.id}`" class="card card-hover p-5 flex gap-4 relative overflow-hidden">
          <div class="absolute top-0 right-0 bg-sycamore-100 text-sycamore-700 text-[10px] font-bold uppercase tracking-wide px-2 py-0.5 rounded-bl-lg">New</div>
          <div class="relative flex-shrink-0">
            <img
              v-if="avatar(s)"
              :src="avatar(s)!"
              :alt="s.full_name"
              referrerpolicy="no-referrer"
              class="w-14 h-14 rounded-full object-cover border border-slate-200"
            />
            <div v-else class="w-14 h-14 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-lg">
              {{ initials(s.full_name) }}
            </div>
          </div>
          <div class="min-w-0 flex-1">
            <h3 class="font-semibold text-slate-900 truncate">{{ s.full_name }}</h3>
            <div class="text-sm text-slate-600 truncate">{{ s.role }}</div>
            <div class="text-xs text-slate-500 mt-1">
              <span v-if="s.departments?.name" class="badge badge-green">{{ s.departments.name }}</span>
            </div>
            <div class="text-xs text-slate-400 mt-2">Joined {{ fmtDate(s.joined_date) }}</div>
          </div>
        </NuxtLink>
      </div>
    </template>

    <template v-else>
      <div v-if="filteredExited.length === 0" class="text-slate-400">No exited staff records.</div>

      <!-- Mobile: list style for exited -->
      <div class="sm:hidden divide-y divide-slate-100">
        <div v-for="s in filteredExited" :key="s.id" class="py-3 px-1">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-full bg-slate-200 text-slate-600 flex items-center justify-center text-xs font-semibold flex-shrink-0">
              {{ s.full_name?.split(' ').map((p: string) => p[0]).slice(0,2).join('').toUpperCase() }}
            </div>
            <div class="min-w-0 flex-1">
              <h3 class="font-semibold text-[15px] text-slate-900 truncate leading-tight">{{ s.full_name }}</h3>
              <div class="text-[13px] text-slate-500 truncate">{{ s.role || '—' }}</div>
            </div>
          </div>
          <div class="ml-13 mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-slate-400">
            <span v-if="s.department_name">{{ s.department_name }}</span>
            <span>Joined {{ fmtDate(s.joined_date) }}</span>
            <span>Exited {{ fmtDate(s.exit_effective_date) }}</span>
          </div>
        </div>
      </div>

      <!-- Desktop: table -->
      <div class="hidden sm:block card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Name</th>
              <th class="text-left px-5 py-2">Role</th>
              <th class="text-left px-5 py-2">Department</th>
              <th class="text-left px-5 py-2">Joined</th>
              <th class="text-left px-5 py-2">Exited</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="s in filteredExited" :key="s.id" class="border-t border-slate-100">
              <td class="px-5 py-3">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-full bg-slate-200 text-slate-600 flex items-center justify-center text-xs font-semibold">
                    {{ s.full_name?.split(' ').map((p: string) => p[0]).slice(0,2).join('').toUpperCase() }}
                  </div>
                  <div>
                    <div class="font-semibold text-slate-900">{{ s.full_name }}</div>
                    <div class="text-xs text-slate-500">{{ s.email }}</div>
                  </div>
                </div>
              </td>
              <td class="px-5 py-3 text-slate-700">{{ s.role || '—' }}</td>
              <td class="px-5 py-3 text-slate-700">{{ s.department_name || '—' }}</td>
              <td class="px-5 py-3 text-slate-500">{{ fmtDate(s.joined_date) }}</td>
              <td class="px-5 py-3 text-slate-500">{{ fmtDate(s.exit_effective_date) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
