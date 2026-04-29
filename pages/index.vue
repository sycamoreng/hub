<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import { findTemplate } from '~/composables/useFeed'

const { fetchCompanyInfo, fetchDepartments, fetchLocations, fetchStaff, fetchAnnouncements, fetchHolidaysEvents } = useCompanyData()
const { fetchPosts, fetchMentionsForPosts, fetchMentionsForAnnouncements } = useFeed()
const { fetchProfilesByUserIds } = useProfile()
const { user, isAdmin } = useAuth()

const supabase = useSupabase()

const quickTools = ref<any[]>([])
const userDepartment = ref<string | null>(null)

const companyInfo = ref<any[]>([])
const departments = ref<any[]>([])
const locations = ref<any[]>([])
const staff = ref<any[]>([])
const announcements = ref<any[]>([])
const events = ref<any[]>([])
const recentPosts = ref<any[]>([])
const postAuthors = ref<Record<string, { name: string; staff_id: string | null; avatar: string | null }>>({})
const postMentions = ref<Record<string, any[]>>({})
const announcementMentions = ref<Record<string, any[]>>({})
const loading = ref(true)

onMounted(async () => {
  try {
    const [c, d, l, s, a, e, p, qt, userDept] = await Promise.all([
      fetchCompanyInfo(), fetchDepartments(), fetchLocations(), fetchStaff(),
      fetchAnnouncements(), fetchHolidaysEvents(), fetchPosts(6),
      supabase.from('quick_tools').select('*').eq('is_active', true).order('sort_order').order('name'),
      user.value
        ? supabase.from('staff_members').select('departments(name)').eq('auth_user_id', user.value.id).maybeSingle()
        : Promise.resolve({ data: null })
    ])
    quickTools.value = qt.data ?? []
    userDepartment.value = (userDept.data as any)?.departments?.name ?? null
    companyInfo.value = c
    departments.value = d
    locations.value = l
    staff.value = s
    announcements.value = a
    events.value = e
    recentPosts.value = p

    const [pm, am] = await Promise.all([
      fetchMentionsForPosts(p.map(x => x.id)),
      fetchMentionsForAnnouncements(a.map((x: any) => x.id))
    ])
    postMentions.value = pm
    announcementMentions.value = am

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

function snippet(text: string, len = 220) {
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
  return events.value.filter(e => e.event_date >= today).slice(0, 6)
})

const headlineAnnouncement = computed(() => announcements.value[0] ?? null)
const moreAnnouncements = computed(() => announcements.value.slice(1, 4))

const stats = computed(() => [
  { label: 'Departments', value: departments.value.length, icon: 'building', to: '/departments' },
  { label: 'Locations', value: locations.value.length, icon: 'map', to: '/locations' },
  { label: 'Staff', value: staff.value.length, icon: 'users', to: '/staff' },
  { label: 'Upcoming events', value: upcomingEvents.value.length, icon: 'calendar', to: '/calendar' }
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

function postTpl(t: string | undefined | null) {
  return findTemplate(t)
}

const visibleQuickTools = computed(() => {
  const dept = userDepartment.value
  const admin = isAdmin.value
  return quickTools.value.filter(t => {
    const allowed: string[] = t.allowed_departments ?? []
    if (!allowed || allowed.length === 0) return true
    if (admin) return true
    return dept ? allowed.includes(dept) : false
  })
})
</script>

<template>
  <div class="max-w-7xl mx-auto space-y-10">
    <section class="relative overflow-hidden rounded-3xl min-h-[460px] sm:min-h-[520px] flex items-end">
      <img
        src="/home-hero.webp"
        alt="Sycamore colleagues collaborating"
        class="absolute inset-0 w-full h-full object-cover"
      />
      <div class="absolute inset-0 bg-gradient-to-tr from-slate-900/85 via-slate-900/55 to-slate-900/10" />
      <div class="absolute inset-0 bg-gradient-to-b from-transparent via-transparent to-slate-900/40" />
      <div class="relative z-10 p-8 sm:p-12 lg:p-16 text-white max-w-3xl">
        <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-white/10 ring-1 ring-white/20 backdrop-blur text-[11px] font-semibold uppercase tracking-[0.2em]">
          <span class="w-1.5 h-1.5 rounded-full bg-leaf-300" />
          Welcome to Sycamore
        </div>
        <h1 class="mt-5 text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight leading-[1.05]">
          {{ infoMap.tagline || 'Nurturing Growth, Building Futures' }}
        </h1>
        <p class="mt-5 text-base sm:text-lg text-white/80 max-w-2xl leading-relaxed">
          {{ infoMap.about || 'Your central hub for everything happening across the team. Catch up on news, celebrate colleagues, and keep building.' }}
        </p>
        <div class="mt-7 flex flex-wrap gap-3">
          <NuxtLink to="/feed" class="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-white text-slate-900 font-semibold text-sm hover:bg-slate-100 transition-colors">
            Open the feed <SidebarIcon name="arrow-right" />
          </NuxtLink>
          <NuxtLink to="/staff" class="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-white/10 ring-1 ring-white/30 text-white font-semibold text-sm hover:bg-white/20 transition-colors backdrop-blur">
            Meet the team <SidebarIcon name="users" />
          </NuxtLink>
        </div>
      </div>
    </section>

    <section class="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
      <NuxtLink
        v-for="s in stats"
        :key="s.label"
        :to="s.to"
        class="card p-5 group hover:border-sycamore-300 hover:shadow-md transition-all"
      >
        <div class="flex items-start justify-between">
          <div>
            <div class="text-xs font-medium text-slate-500 uppercase tracking-wide">{{ s.label }}</div>
            <div class="text-3xl font-bold text-slate-900 mt-1">{{ s.value }}</div>
          </div>
          <div class="w-10 h-10 rounded-xl bg-sycamore-50 text-sycamore-600 flex items-center justify-center group-hover:bg-sycamore-600 group-hover:text-white transition-colors">
            <SidebarIcon :name="s.icon" />
          </div>
        </div>
        <div class="mt-4 inline-flex items-center gap-1 text-xs text-sycamore-700 font-medium opacity-0 group-hover:opacity-100 transition-opacity">
          Explore <SidebarIcon name="arrow-right" />
        </div>
      </NuxtLink>
    </section>

    <section v-if="headlineAnnouncement" class="grid lg:grid-cols-3 gap-6">
      <article class="lg:col-span-2 card overflow-hidden flex flex-col">
        <div class="relative">
          <img
            v-if="headlineAnnouncement.image_url"
            :src="headlineAnnouncement.image_url"
            :alt="headlineAnnouncement.title"
            class="w-full h-72 object-cover"
          />
          <div v-else class="w-full h-72 bg-gradient-to-br from-sycamore-600 via-sycamore-700 to-leaf-700" />
          <div class="absolute inset-0 bg-gradient-to-t from-slate-900/80 via-slate-900/20 to-transparent" />
          <div class="absolute top-4 left-4">
            <span :class="[
              'badge',
              headlineAnnouncement.priority === 'high' ? 'badge-rose' : headlineAnnouncement.priority === 'medium' ? 'badge-amber' : 'badge-slate'
            ]">{{ headlineAnnouncement.priority }} priority</span>
          </div>
          <div class="absolute bottom-0 left-0 right-0 p-6 text-white">
            <div class="text-[11px] uppercase tracking-[0.2em] font-semibold text-white/70">Announcement</div>
            <h2 class="text-2xl sm:text-3xl font-bold mt-1 leading-tight">{{ headlineAnnouncement.title }}</h2>
          </div>
        </div>
        <div class="p-6 flex-1">
          <PostBody class="block text-sm text-slate-700 leading-relaxed" :content="snippet(headlineAnnouncement.content, 360)" :mentions="announcementMentions[headlineAnnouncement.id]" />
          <div class="text-xs text-slate-400 mt-3">{{ formatDate(headlineAnnouncement.created_at) }}</div>
        </div>
      </article>

      <div class="space-y-4">
        <div class="card p-5">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-3">More announcements</h3>
          <div v-if="moreAnnouncements.length === 0" class="text-sm text-slate-400">All caught up.</div>
          <ul v-else class="space-y-3">
            <li v-for="a in moreAnnouncements" :key="a.id" class="flex gap-3">
              <img
                v-if="a.image_url"
                :src="a.image_url"
                :alt="a.title"
                class="w-14 h-14 rounded-lg object-cover flex-shrink-0 border border-slate-200"
              />
              <div v-else class="w-14 h-14 rounded-lg flex-shrink-0 bg-gradient-to-br from-sycamore-100 to-leaf-100 flex items-center justify-center text-sycamore-700">
                <SidebarIcon name="info" />
              </div>
              <div class="min-w-0">
                <div class="font-semibold text-sm text-slate-900 truncate">{{ a.title }}</div>
                <p class="text-xs text-slate-500 line-clamp-2">{{ a.content }}</p>
                <div class="text-[11px] text-slate-400 mt-0.5">{{ formatDate(a.created_at) }}</div>
              </div>
            </li>
          </ul>
        </div>

        <div class="card p-5">
          <div class="flex items-center justify-between mb-3">
            <h3 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Coming up</h3>
            <NuxtLink to="/calendar" class="text-xs text-sycamore-700 font-medium hover:underline">View all</NuxtLink>
          </div>
          <div v-if="upcomingEvents.length === 0" class="text-sm text-slate-400">No upcoming events.</div>
          <ul v-else class="space-y-3">
            <li v-for="e in upcomingEvents.slice(0, 4)" :key="e.id" class="flex items-start gap-3">
              <div class="flex-shrink-0 w-12 h-12 rounded-lg bg-sycamore-50 border border-sycamore-100 text-center flex flex-col justify-center">
                <div class="text-[10px] font-semibold text-sycamore-600 uppercase">{{ parseEventDate(e.event_date).toLocaleString('en-GB', { month: 'short' }) }}</div>
                <div class="text-base font-bold text-slate-900 leading-none">{{ parseEventDate(e.event_date).getDate() }}</div>
              </div>
              <div class="min-w-0">
                <div class="font-medium text-sm text-slate-900 truncate">{{ e.title }}</div>
                <span class="badge badge-green mt-1">{{ e.event_type }}</span>
              </div>
            </li>
          </ul>
        </div>
      </div>
    </section>

    <section>
      <div class="flex items-end justify-between mb-5">
        <div>
          <h2 class="text-2xl font-bold text-slate-900 tracking-tight">From the team</h2>
          <p class="text-sm text-slate-500">Latest moments shared by your colleagues.</p>
        </div>
        <NuxtLink to="/feed" class="inline-flex items-center gap-1 text-sm text-sycamore-700 font-medium hover:underline">
          Open feed <SidebarIcon name="arrow-right" />
        </NuxtLink>
      </div>
      <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
      <div v-else-if="recentPosts.length === 0" class="card p-8 text-center text-sm text-slate-400">No posts yet. Be the first to share something on the feed.</div>
      <div v-else class="grid sm:grid-cols-2 gap-4">
        <article
          v-for="p in recentPosts"
          :key="p.id"
          class="card overflow-hidden flex flex-col"
        >
          <div
            v-if="postTpl(p.post_kind)"
            class="px-4 py-3 bg-gradient-to-r flex items-center gap-2 text-white"
            :class="postTpl(p.post_kind)!.accent"
          >
            <span class="text-xl">{{ postTpl(p.post_kind)!.emoji }}</span>
            <span class="text-[11px] font-semibold uppercase tracking-wide">{{ postTpl(p.post_kind)!.label }}</span>
          </div>
          <img
            v-if="p.image_url"
            :src="p.image_url"
            alt=""
            class="w-full h-44 object-cover"
          />
          <div class="p-4 flex gap-3 flex-1">
            <NuxtLink
              v-if="postAuthors[p.author_id]?.staff_id"
              :to="`/profile/${postAuthors[p.author_id]?.staff_id}`"
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
            </NuxtLink>
            <div v-else class="flex-shrink-0">
              <div class="w-10 h-10 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-sm font-semibold">
                {{ postInitials(postAuthors[p.author_id]?.name || '?') }}
              </div>
            </div>
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
              <PostBody class="block text-sm text-slate-700 mt-1" :content="snippet(p.content)" :mentions="postMentions[p.id]" />
            </div>
          </div>
        </article>
      </div>
    </section>

    <section v-if="visibleQuickTools.length">
      <div class="flex items-end justify-between mb-5">
        <div>
          <h2 class="text-2xl font-bold text-slate-900 tracking-tight">Quick access</h2>
          <p class="text-sm text-slate-500">Jump straight into the tools you use every day.</p>
        </div>
      </div>
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3 sm:gap-4">
        <a
          v-for="t in visibleQuickTools"
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
            <SidebarIcon v-else name="arrow-right" />
          </div>
          <div>
            <div class="font-semibold text-sm text-slate-900">{{ t.name }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5 inline-flex items-center gap-1">
              Open <SidebarIcon name="arrow-right" />
            </div>
          </div>
        </a>
      </div>
    </section>

    <section>
      <h2 class="text-2xl font-bold text-slate-900 tracking-tight mb-5">Explore Sycamore</h2>
      <div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <NuxtLink to="/staff" class="card p-5 group hover:border-sycamore-300 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-sycamore-600 group-hover:text-white flex items-center justify-center transition-colors mb-4"><SidebarIcon name="users" /></div>
          <div class="font-semibold text-slate-900">Find a colleague</div>
          <p class="text-xs text-slate-500 mt-1">Browse the staff directory.</p>
        </NuxtLink>
        <NuxtLink to="/policies" class="card p-5 group hover:border-sycamore-300 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-sycamore-600 group-hover:text-white flex items-center justify-center transition-colors mb-4"><SidebarIcon name="book" /></div>
          <div class="font-semibold text-slate-900">Read policies</div>
          <p class="text-xs text-slate-500 mt-1">Stay aligned with how we work.</p>
        </NuxtLink>
        <NuxtLink to="/benefits" class="card p-5 group hover:border-sycamore-300 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-sycamore-600 group-hover:text-white flex items-center justify-center transition-colors mb-4"><SidebarIcon name="gift" /></div>
          <div class="font-semibold text-slate-900">Your benefits</div>
          <p class="text-xs text-slate-500 mt-1">Perks, leave and wellbeing.</p>
        </NuxtLink>
        <NuxtLink to="/onboarding" class="card p-5 group hover:border-sycamore-300 transition-colors">
          <div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-sycamore-600 group-hover:text-white flex items-center justify-center transition-colors mb-4"><SidebarIcon name="star" /></div>
          <div class="font-semibold text-slate-900">Learning path</div>
          <p class="text-xs text-slate-500 mt-1">Onboarding and training.</p>
        </NuxtLink>
      </div>
    </section>
  </div>
</template>
