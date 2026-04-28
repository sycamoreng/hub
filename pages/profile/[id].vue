<script setup lang="ts">
import { getThemeGradient, type UserProfile } from '~/composables/useProfile'

const route = useRoute()
const staffId = computed(() => String(route.params.id))

const { fetchStaffById, fetchProfile } = useProfile()
const { user } = useAuth()

const loading = ref(true)
const staff = ref<any | null>(null)
const profile = ref<UserProfile | null>(null)
const departmentName = ref<string>('')
const locationName = ref<string>('')

async function load() {
  loading.value = true
  staff.value = await fetchStaffById(staffId.value)
  if (staff.value?.auth_user_id) {
    profile.value = await fetchProfile(staff.value.auth_user_id)
  } else {
    profile.value = null
  }
  if (staff.value?.department_id || staff.value?.location_id) {
    const supabase = useSupabase()
    const [dep, loc] = await Promise.all([
      staff.value.department_id
        ? supabase.from('departments').select('name').eq('id', staff.value.department_id).maybeSingle()
        : Promise.resolve({ data: null }),
      staff.value.location_id
        ? supabase.from('locations').select('name, city, country').eq('id', staff.value.location_id).maybeSingle()
        : Promise.resolve({ data: null })
    ])
    departmentName.value = (dep.data as any)?.name ?? ''
    const l = loc.data as any
    locationName.value = l ? [l.name, l.city, l.country].filter(Boolean).join(', ') : ''
  }
  loading.value = false
}

watch(staffId, load, { immediate: true })

const theme = computed(() => profile.value?.theme || 'sycamore')
const gradient = computed(() => getThemeGradient(theme.value))

const socials = computed(() => {
  const p = profile.value
  if (!p) return []
  return [
    { key: 'linkedin', label: 'LinkedIn', url: p.linkedin_url },
    { key: 'twitter', label: 'X / Twitter', url: p.twitter_url },
    { key: 'github', label: 'GitHub', url: p.github_url },
    { key: 'website', label: 'Website', url: p.website_url },
    { key: 'instagram', label: 'Instagram', url: p.instagram_url }
  ].filter(s => !!s.url)
})

const isOwn = computed(() => !!user.value && user.value.id === staff.value?.auth_user_id)

const initials = computed(() => {
  const name = staff.value?.full_name || ''
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((s: string) => s[0]?.toUpperCase() ?? '')
    .join('') || '?'
})
</script>

<template>
  <div class="max-w-4xl mx-auto space-y-6">
    <NuxtLink to="/staff" class="text-xs text-slate-500 hover:text-sycamore-700 inline-flex items-center gap-1">
      &larr; Back to staff
    </NuxtLink>

    <div v-if="loading" class="text-sm text-slate-400">Loading profile...</div>

    <div v-else-if="!staff" class="card p-8 text-center">
      <h2 class="text-lg font-semibold text-slate-900">Profile not found</h2>
      <p class="text-sm text-slate-500 mt-1">This staff record does not exist or is no longer active.</p>
    </div>

    <template v-else>
      <div :class="['rounded-2xl p-6 sm:p-8 text-white relative overflow-hidden bg-gradient-to-br', gradient]">
        <div class="flex items-center gap-4 relative z-10">
          <div class="w-20 h-20 rounded-full bg-white/20 flex items-center justify-center text-2xl font-semibold">
            {{ initials }}
          </div>
          <div class="min-w-0">
            <div class="text-2xl sm:text-3xl font-bold tracking-tight">{{ staff.full_name }}</div>
            <div class="text-sm text-white/85 mt-0.5">{{ staff.role || 'Sycamore' }}</div>
            <div class="text-xs text-white/70 mt-0.5 flex flex-wrap gap-x-3 gap-y-1">
              <span v-if="departmentName">{{ departmentName }}</span>
              <span v-if="locationName">{{ locationName }}</span>
            </div>
          </div>
        </div>
        <div class="absolute -right-16 -bottom-16 w-72 h-72 rounded-full bg-white/5" />
        <div v-if="isOwn" class="relative z-10 mt-4">
          <NuxtLink to="/profile" class="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg bg-white/15 hover:bg-white/25 text-xs font-medium">
            <SidebarIcon name="edit" /> Edit my profile
          </NuxtLink>
        </div>
      </div>

      <div class="grid lg:grid-cols-3 gap-6">
        <div class="lg:col-span-2 card p-6 space-y-4">
          <h3 class="text-sm font-semibold text-slate-900">About</h3>
          <p v-if="profile?.bio" class="text-sm text-slate-700 whitespace-pre-line leading-relaxed">{{ profile.bio }}</p>
          <p v-else-if="staff.bio" class="text-sm text-slate-700 whitespace-pre-line leading-relaxed">{{ staff.bio }}</p>
          <p v-else class="text-sm text-slate-400 italic">No bio yet.</p>
        </div>

        <div class="card p-6 space-y-4">
          <h3 class="text-sm font-semibold text-slate-900">Get in touch</h3>
          <div class="space-y-2 text-sm">
            <div v-if="staff.email" class="flex items-center gap-2 text-slate-700">
              <SidebarIcon name="mail" />
              <a :href="`mailto:${staff.email}`" class="hover:text-sycamore-700 truncate">{{ staff.email }}</a>
            </div>
            <div v-if="staff.phone" class="flex items-center gap-2 text-slate-700">
              <SidebarIcon name="phone" />
              <span>{{ staff.phone }}</span>
            </div>
          </div>

          <div v-if="socials.length" class="pt-4 border-t border-slate-100">
            <h4 class="text-xs font-semibold text-slate-500 uppercase mb-2">Socials</h4>
            <ul class="space-y-1.5">
              <li v-for="s in socials" :key="s.key">
                <a :href="s.url" target="_blank" rel="noopener noreferrer" class="text-sm text-sycamore-700 hover:underline truncate inline-block max-w-full">
                  {{ s.label }}
                </a>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
