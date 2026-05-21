<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import type { UserProfile } from '~/composables/useProfile'

const supabase = useSupabase()
const { fetchProfilesByUserIds } = useProfile()
const loading = ref(true)

interface CelebrationPerson {
  id: string
  full_name: string
  role: string
  auth_user_id: string | null
  department_name: string
  month: number
  day: number
  days_until: number
  type: 'birthday' | 'anniversary'
  years?: number
}

const birthdays = ref<CelebrationPerson[]>([])
const anniversaries = ref<CelebrationPerson[]>([])
const profilesByUid = ref<Record<string, UserProfile>>({})
const celebrationPosts = ref<any[]>([])
const tab = ref<'upcoming' | 'feed'>('upcoming')

async function load() {
  loading.value = true
  try {
    const { data, error } = await supabase.rpc('get_upcoming_celebrations')
    if (error) throw error

    const bd = (data?.birthdays || []).map((r: any) => ({
      id: r.id,
      full_name: r.full_name,
      role: r.role || '',
      auth_user_id: r.auth_user_id,
      department_name: r.department_name || '',
      month: r.birth_month,
      day: r.birth_day,
      days_until: r.days_until,
      type: 'birthday' as const
    }))

    const ann = (data?.anniversaries || []).map((r: any) => ({
      id: r.id,
      full_name: r.full_name,
      role: r.role || '',
      auth_user_id: r.auth_user_id,
      department_name: r.department_name || '',
      month: r.anniversary_month,
      day: r.anniversary_day,
      days_until: r.days_until,
      type: 'anniversary' as const,
      years: r.years
    }))

    birthdays.value = bd
    anniversaries.value = ann

    // Fetch profiles for avatars
    const uids = [...bd, ...ann]
      .map((p: CelebrationPerson) => p.auth_user_id)
      .filter(Boolean) as string[]
    if (uids.length) {
      profilesByUid.value = await fetchProfilesByUserIds(uids)
    }

    // Fetch recent celebration posts
    const { data: posts } = await supabase
      .from('posts')
      .select('*')
      .in('post_kind', ['birthday', 'anniversary'])
      .eq('is_published', true)
      .order('created_at', { ascending: false })
      .limit(20)
    celebrationPosts.value = posts || []
  } finally {
    loading.value = false
  }
}

function formatMonthDay(month: number, day: number): string {
  const date = new Date(2000, month - 1, day)
  return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}

function avatar(person: CelebrationPerson): string | null {
  if (!person.auth_user_id) return null
  return profilesByUid.value[person.auth_user_id]?.avatar_url || null
}

function initials(name: string): string {
  return name.split(' ').map(n => n[0]).join('').slice(0, 2).toUpperCase()
}

onMounted(load)
</script>

<template>
  <div class="max-w-5xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Celebrations</h1>
      <p class="section-subtitle">Upcoming birthdays and work anniversaries across the team.</p>
    </div>

    <div class="flex gap-1 bg-slate-100 rounded-lg p-1 mb-6 w-fit">
      <button type="button" @click="tab = 'upcoming'"
        class="text-xs font-semibold px-3 py-1.5 rounded-md"
        :class="tab === 'upcoming' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        Upcoming
      </button>
      <button type="button" @click="tab = 'feed'"
        class="text-xs font-semibold px-3 py-1.5 rounded-md"
        :class="tab === 'feed' ? 'bg-white shadow text-slate-900' : 'text-slate-500 hover:text-slate-700'">
        Celebration Posts
      </button>
    </div>

    <div v-if="loading" class="text-slate-400">Loading celebrations...</div>

    <template v-else-if="tab === 'upcoming'">
      <!-- Birthdays -->
      <section class="mb-8">
        <div class="flex items-center gap-2 mb-4">
          <span class="text-xl">&#127874;</span>
          <h2 class="text-lg font-bold text-slate-900">Birthdays</h2>
          <span class="text-xs text-slate-400 ml-1">Next 30 days</span>
        </div>

        <div v-if="birthdays.length === 0" class="card p-5 text-center text-sm text-slate-400">
          No upcoming birthdays in the next 30 days.
        </div>

        <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <NuxtLink
            v-for="person in birthdays"
            :key="person.id"
            :to="`/profile/${person.id}`"
            class="card card-hover p-4 flex items-center gap-3"
          >
            <div class="flex-shrink-0">
              <img
                v-if="avatar(person)"
                :src="avatar(person)!"
                :alt="person.full_name"
                referrerpolicy="no-referrer"
                class="w-11 h-11 rounded-full object-cover border border-slate-200"
              />
              <div v-else class="w-11 h-11 rounded-full bg-gradient-to-br from-rose-400 to-amber-400 text-white flex items-center justify-center font-bold text-sm">
                {{ initials(person.full_name) }}
              </div>
            </div>
            <div class="min-w-0 flex-1">
              <h3 class="text-sm font-semibold text-slate-900 truncate">{{ person.full_name }}</h3>
              <p class="text-xs text-slate-500 truncate">{{ person.role }}</p>
            </div>
            <div class="text-right flex-shrink-0">
              <div class="text-xs font-semibold text-slate-700">{{ formatMonthDay(person.month, person.day) }}</div>
              <div v-if="person.days_until === 0" class="text-[10px] font-bold text-rose-600 uppercase">Today!</div>
              <div v-else class="text-[10px] text-slate-400">in {{ person.days_until }}d</div>
            </div>
          </NuxtLink>
        </div>
      </section>

      <!-- Anniversaries -->
      <section>
        <div class="flex items-center gap-2 mb-4">
          <span class="text-xl">&#127881;</span>
          <h2 class="text-lg font-bold text-slate-900">Work Anniversaries</h2>
          <span class="text-xs text-slate-400 ml-1">Next 30 days</span>
        </div>

        <div v-if="anniversaries.length === 0" class="card p-5 text-center text-sm text-slate-400">
          No upcoming work anniversaries in the next 30 days.
        </div>

        <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
          <NuxtLink
            v-for="person in anniversaries"
            :key="person.id"
            :to="`/profile/${person.id}`"
            class="card card-hover p-4 flex items-center gap-3"
          >
            <div class="flex-shrink-0">
              <img
                v-if="avatar(person)"
                :src="avatar(person)!"
                :alt="person.full_name"
                referrerpolicy="no-referrer"
                class="w-11 h-11 rounded-full object-cover border border-slate-200"
              />
              <div v-else class="w-11 h-11 rounded-full bg-gradient-to-br from-sycamore-400 to-leaf-500 text-white flex items-center justify-center font-bold text-sm">
                {{ initials(person.full_name) }}
              </div>
            </div>
            <div class="min-w-0 flex-1">
              <h3 class="text-sm font-semibold text-slate-900 truncate">{{ person.full_name }}</h3>
              <p class="text-xs text-slate-500 truncate">{{ person.role }}</p>
              <p class="text-xs text-sycamore-600 font-medium">{{ person.years }} year{{ person.years !== 1 ? 's' : '' }}</p>
            </div>
            <div class="text-right flex-shrink-0">
              <div class="text-xs font-semibold text-slate-700">{{ formatMonthDay(person.month, person.day) }}</div>
              <div v-if="person.days_until === 0" class="text-[10px] font-bold text-sycamore-600 uppercase">Today!</div>
              <div v-else class="text-[10px] text-slate-400">in {{ person.days_until }}d</div>
            </div>
          </NuxtLink>
        </div>
      </section>
    </template>

    <!-- Celebration Posts Feed -->
    <template v-else-if="tab === 'feed'">
      <div v-if="celebrationPosts.length === 0" class="card p-8 text-center">
        <p class="text-sm text-slate-400">No celebration posts yet. They will appear here when birthdays and anniversaries are celebrated.</p>
      </div>
      <div v-else class="space-y-4">
        <div v-for="post in celebrationPosts" :key="post.id" class="card p-5">
          <div class="flex items-start gap-3">
            <div class="w-9 h-9 rounded-full flex items-center justify-center text-lg"
              :class="post.post_kind === 'birthday' ? 'bg-rose-50' : 'bg-sycamore-50'">
              {{ post.post_kind === 'birthday' ? '&#127874;' : '&#127881;' }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="badge" :class="post.post_kind === 'birthday' ? 'badge-rose' : 'badge-green'">
                  {{ post.post_kind === 'birthday' ? 'Birthday' : 'Anniversary' }}
                </span>
                <span class="text-xs text-slate-400">{{ new Date(post.created_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) }}</span>
              </div>
              <p class="text-sm text-slate-700 mt-2 whitespace-pre-line">{{ post.content }}</p>
              <NuxtLink v-if="post.template_data?.staff_id" :to="`/profile/${post.template_data.staff_id}`" class="inline-flex items-center gap-1 text-xs text-sycamore-600 font-medium mt-2 hover:underline">
                View profile &rarr;
              </NuxtLink>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
