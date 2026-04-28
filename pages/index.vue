<script setup lang="ts">
const { fetchCompanyInfo, fetchDepartments, fetchLocations, fetchStaff, fetchAnnouncements, fetchHolidaysEvents } = useCompanyData()

const companyInfo = ref<any[]>([])
const departments = ref<any[]>([])
const locations = ref<any[]>([])
const staff = ref<any[]>([])
const announcements = ref<any[]>([])
const events = ref<any[]>([])
const loading = ref(true)

onMounted(async () => {
  try {
    const [c, d, l, s, a, e] = await Promise.all([
      fetchCompanyInfo(), fetchDepartments(), fetchLocations(), fetchStaff(), fetchAnnouncements(), fetchHolidaysEvents()
    ])
    companyInfo.value = c
    departments.value = d
    locations.value = l
    staff.value = s
    announcements.value = a
    events.value = e
  } finally {
    loading.value = false
  }
})

const infoMap = computed(() => {
  const m: Record<string, string> = {}
  for (const i of companyInfo.value) m[i.info_key] = i.info_value
  return m
})

const upcomingEvents = computed(() => {
  const today = new Date().toISOString().slice(0, 10)
  return events.value.filter(e => e.event_date >= today).slice(0, 5)
})

const stats = computed(() => [
  { label: 'Departments', value: departments.value.length, icon: 'building' },
  { label: 'Locations', value: locations.value.length, icon: 'map' },
  { label: 'Staff Members', value: staff.value.length, icon: 'users' },
  { label: 'Upcoming Events', value: upcomingEvents.value.length, icon: 'calendar' }
])

function parseEventDate(d: string): Date {
  const parts = (d || '').slice(0, 10).split('-').map(Number)
  if (parts.length === 3 && parts.every(n => !Number.isNaN(n))) {
    return new Date(parts[0], parts[1] - 1, parts[2])
  }
  return new Date(d)
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}
</script>

<template>
  <div class="max-w-7xl mx-auto space-y-8">
    <div class="bg-gradient-to-br from-sycamore-600 to-sycamore-800 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden">
      <div class="relative z-10">
        <div class="badge bg-white/15 text-white border-white/20 mb-4">
          <SidebarIcon name="dot" />
          <span class="ml-1">Welcome to Sycamore</span>
        </div>
        <h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">{{ infoMap.tagline || 'Nurturing Growth, Building Futures' }}</h1>
        <p class="text-sycamore-50 max-w-2xl">{{ infoMap.about || 'Your central hub for everything you need to know about working at Sycamore.' }}</p>
      </div>
      <div class="absolute -right-16 -bottom-16 w-80 h-80 rounded-full bg-white/5" />
      <div class="absolute -right-8 -top-8 w-48 h-48 rounded-full bg-white/5" />
    </div>

    <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
      <div v-for="s in stats" :key="s.label" class="card p-5">
        <div class="flex items-start justify-between">
          <div>
            <div class="text-sm text-slate-500">{{ s.label }}</div>
            <div class="text-3xl font-bold text-slate-900 mt-1">{{ s.value }}</div>
          </div>
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">
            <SidebarIcon :name="s.icon" />
          </div>
        </div>
      </div>
    </div>

    <div class="grid lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 card p-6">
        <div class="flex items-center justify-between mb-5">
          <div>
            <h2 class="text-lg font-bold text-slate-900">Announcements</h2>
            <p class="text-sm text-slate-500">Latest company-wide updates</p>
          </div>
          <SidebarIcon name="info" />
        </div>
        <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
        <div v-else-if="announcements.length === 0" class="text-sm text-slate-400">No announcements.</div>
        <div v-else class="space-y-4">
          <article v-for="a in announcements" :key="a.id" class="flex gap-4 p-4 rounded-lg bg-slate-50 border border-slate-100">
            <div class="flex-shrink-0">
              <span :class="[
                'badge',
                a.priority === 'high' ? 'badge-rose' : a.priority === 'medium' ? 'badge-amber' : 'badge-slate'
              ]">{{ a.priority }}</span>
            </div>
            <div class="min-w-0">
              <h3 class="font-semibold text-slate-900">{{ a.title }}</h3>
              <p class="text-sm text-slate-600 mt-1">{{ a.content }}</p>
              <div class="text-xs text-slate-400 mt-2">{{ formatDate(a.created_at) }}</div>
            </div>
          </article>
        </div>
      </div>

      <div class="card p-6">
        <div class="flex items-center justify-between mb-5">
          <div>
            <h2 class="text-lg font-bold text-slate-900">Upcoming Events</h2>
            <p class="text-sm text-slate-500">Don't miss these</p>
          </div>
          <SidebarIcon name="calendar" />
        </div>
        <div v-if="upcomingEvents.length === 0" class="text-sm text-slate-400">No upcoming events.</div>
        <ul v-else class="space-y-3">
          <li v-for="e in upcomingEvents" :key="e.id" class="flex items-start gap-3 p-3 rounded-lg hover:bg-slate-50">
            <div class="flex-shrink-0 w-12 text-center">
              <div class="text-xs font-medium text-sycamore-600 uppercase">{{ parseEventDate(e.event_date).toLocaleString('en-GB', { month: 'short' }) }}</div>
              <div class="text-xl font-bold text-slate-900">{{ parseEventDate(e.event_date).getDate() }}</div>
            </div>
            <div class="min-w-0">
              <div class="font-medium text-slate-900 text-sm">{{ e.title }}</div>
              <div class="text-xs text-slate-500 truncate">{{ e.description }}</div>
              <span class="badge badge-green mt-1.5">{{ e.event_type }}</span>
            </div>
          </li>
        </ul>
      </div>
    </div>

    <div class="card p-6">
      <h2 class="text-lg font-bold text-slate-900 mb-5">Quick Links</h2>
      <div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">
        <NuxtLink to="/staff" class="group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"><SidebarIcon name="users" /></div>
          <div class="flex-1 text-sm font-medium text-slate-800">Find a colleague</div>
          <SidebarIcon name="arrow-right" />
        </NuxtLink>
        <NuxtLink to="/policies" class="group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"><SidebarIcon name="book" /></div>
          <div class="flex-1 text-sm font-medium text-slate-800">Read policies</div>
          <SidebarIcon name="arrow-right" />
        </NuxtLink>
        <NuxtLink to="/benefits" class="group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"><SidebarIcon name="gift" /></div>
          <div class="flex-1 text-sm font-medium text-slate-800">Your benefits</div>
          <SidebarIcon name="arrow-right" />
        </NuxtLink>
        <NuxtLink to="/contacts" class="group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"><SidebarIcon name="phone" /></div>
          <div class="flex-1 text-sm font-medium text-slate-800">Key contacts</div>
          <SidebarIcon name="arrow-right" />
        </NuxtLink>
      </div>
    </div>
  </div>
</template>
