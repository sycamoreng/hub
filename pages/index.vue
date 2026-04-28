<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const { fetchCompanyInfo, fetchDepartments, fetchLocations, fetchStaff, fetchAnnouncements, fetchHolidaysEvents } = useCompanyData()
const { fetchPosts } = useFeed()
const { fetchProfilesByUserIds } = useProfile()

const supabase = useSupabase()

const companyInfo = ref<any[]>([])
const departments = ref<any[]>([])
const locations = ref<any[]>([])
const staff = ref<any[]>([])
const announcements = ref<any[]>([])
const events = ref<any[]>([])
const recentPosts = ref<any[]>([])
const postAuthors = ref<Record<string, { name: string; staff_id: string | null; avatar: string | null }>>({})
const loading = ref(true)

onMounted(async () => {
  try {
    const [c, d, l, s, a, e, p] = await Promise.all([
      fetchCompanyInfo(), fetchDepartments(), fetchLocations(), fetchStaff(),
      fetchAnnouncements(), fetchHolidaysEvents(), fetchPosts(5)
    ])
    companyInfo.value = c
    departments.value = d
    locations.value = l
    staff.value = s
    announcements.value = a
    events.value = e
    recentPosts.value = p

    const uids = p.map(x => x.author_id)
    if (uids.length) {
      const [{ data: staffRows }, profiles] = await Promise.all([
        supabase.from('staff_members').select('id, full_name, auth_user_id').in('auth_user_id', uids),
        fetchProfilesByUserIds(uids)
      ])
      const map: typeof postAuthors.value = {}
      for (const uid of uids) {
        const sm = (staffRows ?? []).find((r: any) => r.auth_user_id === uid)
        map[uid] = {
          name: sm?.full_name || 'Sycamore staff',
          staff_id: sm?.id ?? null,
          avatar: profiles[uid]?.avatar_url || null
        }
      }
      postAuthors.value = map
    }
  } finally {
    loading.value = false
  }
})

function postInitials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]?.toUpperCase() ?? '').join('') || '?'
}

function snippet(text: string, len = 160) {
  const t = (text || '').trim()
  return t.length > len ? `${t.slice(0, len)}...` : t
}

function relativeTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d ago`
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}

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
      <div class="flex items-center justify-between mb-5">
        <div>
          <h2 class="text-lg font-bold text-slate-900">Recent from the team</h2>
          <p class="text-sm text-slate-500">Latest posts from your colleagues</p>
        </div>
        <NuxtLink to="/feed" class="text-xs text-sycamore-700 font-medium hover:underline inline-flex items-center gap-1">
          View feed <SidebarIcon name="arrow-right" />
        </NuxtLink>
      </div>
      <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
      <div v-else-if="recentPosts.length === 0" class="text-sm text-slate-400">No posts yet. Be the first to share something on the feed.</div>
      <ul v-else class="space-y-3">
        <li v-for="p in recentPosts" :key="p.id" class="flex gap-3 p-3 rounded-lg hover:bg-slate-50">
          <component
            :is="postAuthors[p.author_id]?.staff_id ? resolveComponent('NuxtLink') : 'div'"
            :to="postAuthors[p.author_id]?.staff_id ? `/profile/${postAuthors[p.author_id]?.staff_id}` : undefined"
            class="flex-shrink-0"
          >
            <img
              v-if="postAuthors[p.author_id]?.avatar"
              :src="postAuthors[p.author_id]?.avatar!"
              :alt="postAuthors[p.author_id]?.name"
              referrerpolicy="no-referrer"
              class="w-10 h-10 rounded-full object-cover border border-slate-200"
            />
            <div v-else class="w-10 h-10 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-sm font-semibold">
              {{ postInitials(postAuthors[p.author_id]?.name || '?') }}
            </div>
          </component>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2 text-sm">
              <NuxtLink
                v-if="postAuthors[p.author_id]?.staff_id"
                :to="`/profile/${postAuthors[p.author_id]?.staff_id}`"
                class="font-semibold text-slate-900 hover:text-sycamore-700 truncate"
              >{{ postAuthors[p.author_id]?.name }}</NuxtLink>
              <span v-else class="font-semibold text-slate-900 truncate">{{ postAuthors[p.author_id]?.name || 'Sycamore staff' }}</span>
              <span class="text-xs text-slate-400">{{ relativeTime(p.created_at) }}</span>
            </div>
            <p class="text-sm text-slate-600 mt-0.5">{{ snippet(p.content) }}</p>
          </div>
        </li>
      </ul>
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
