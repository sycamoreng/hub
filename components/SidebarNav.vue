<script setup lang="ts">
interface NavItem { to: string; label: string; icon: string }
interface NavGroup { id: string; label: string; icon: string; items: NavItem[] }

import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const raffleVisible = ref(false)
const { isAdmin } = useAuth()
const { load: loadLocks, isLocked } = usePageLocks()
const { order: sidebarOrder, load: loadOrder } = useSidebarOrder()

async function loadRaffleVisibility() {
  const { data } = await supabase
    .from('raffle_settings')
    .select('visible_on_sidebar')
    .eq('id', 1)
    .maybeSingle()
  raffleVisible.value = Boolean((data as any)?.visible_on_sidebar)
}
loadRaffleVisibility()
loadLocks()
loadOrder()

const standalone = computed<NavItem[]>(() => {
  return [
    { to: '/', label: 'Home', icon: 'home' },
    { to: '/feed', label: 'Feed', icon: 'chat' },
    { to: '/attendance', label: 'Clock in', icon: 'clock' }
  ]
})

const rewardsGroup = computed<NavGroup>(() => {
  const items: NavItem[] = [
    { to: '/recognition', label: 'Recognition', icon: 'star' },
    { to: '/guess-who', label: 'Guess Who', icon: 'sparkle' },
    { to: '/wordle', label: 'Daily Wordle', icon: 'sparkle' },
    { to: '/typing', label: 'Typing Sprint', icon: 'sparkle' },
    { to: '/dino', label: 'Sycamore Run', icon: 'sparkle' },
    { to: '/codebreaker', label: 'Code Breaker', icon: 'sparkle' },
    { to: '/crossword', label: 'Mini Crossword', icon: 'sparkle' }
  ]
  if (raffleVisible.value) {
    items.push({ to: '/raffle', label: "Workers' Day Raffle", icon: 'gift' })
  }
  return {
    id: 'rewards',
    label: 'Rewards & Play',
    icon: 'star',
    items
  }
})

const baseGroups = computed<NavGroup[]>(() => [
  rewardsGroup.value,
  {
    id: 'company',
    label: 'Company',
    icon: 'building',
    items: [
      { to: '/leadership', label: 'Leadership', icon: 'star' },
      { to: '/organogram', label: 'Organogram', icon: 'users' },
      { to: '/my-team', label: 'My Team', icon: 'users' },
      { to: '/departments', label: 'Departments', icon: 'building' },
      { to: '/locations', label: 'Locations', icon: 'map' },
      { to: '/staff', label: 'Staff Directory', icon: 'users' },
      { to: '/celebrations', label: 'Celebrations', icon: 'sparkle' },
      { to: '/ask-leadership', label: 'Ask Leadership', icon: 'chat' }
    ]
  },
  {
    id: 'productivity',
    label: 'Productivity',
    icon: 'sparkle',
    items: [
      { to: '/tools', label: 'Tools', icon: 'gift' },
      { to: '/onboarding', label: 'Learning', icon: 'check' },
      { to: '/requests', label: 'Service Requests', icon: 'check' }
    ]
  },
  {
    id: 'work',
    label: 'Products & Tech',
    icon: 'gift',
    items: [
      { to: '/products', label: 'Products', icon: 'gift' },
      { to: '/technology', label: 'Technology', icon: 'palette' }
    ]
  },
  {
    id: 'people',
    label: 'People & Culture',
    icon: 'users',
    items: [
      { to: '/policies', label: 'Policies', icon: 'book' },
      { to: '/benefits', label: 'Benefits & Perks', icon: 'gift' },
      { to: '/hmo', label: 'My HMO', icon: 'gift' },
      { to: '/branding', label: 'Branding', icon: 'palette' },
      { to: '/payroll', label: 'My Payroll', icon: 'card' },
      { to: '/finance', label: 'Advance & Loans', icon: 'card' },
      { to: '/leave', label: 'Leave', icon: 'calendar' },
      { to: '/performance', label: 'Performance', icon: 'check' },
      { to: '/exit', label: 'Exit', icon: 'arrow-right' }
    ]
  },
  {
    id: 'social',
    label: 'Social & Fun',
    icon: 'sparkle',
    items: [
      { to: '/forums', label: 'Forums', icon: 'chat' },
      { to: '/photos', label: 'Photo Wall', icon: 'palette' },
      { to: '/playlist', label: 'Playlist of the Week', icon: 'sparkle' }
    ]
  },
  {
    id: 'comms',
    label: 'Communication',
    icon: 'chat',
    items: [
      { to: '/communication', label: 'Communication', icon: 'chat' },
      { to: '/contacts', label: 'Key Contacts', icon: 'phone' },
      { to: '/calendar', label: 'Calendar', icon: 'calendar' },
      { to: '/appointments', label: 'Appointments', icon: 'calendar' }
    ]
  }
])

const orderedGroups = computed<NavGroup[]>(() => {
  const byId = new Map(baseGroups.value.map(g => [g.id, g] as const))
  const out: NavGroup[] = []
  const seen = new Set<string>()
  for (const id of sidebarOrder.value) {
    const g = byId.get(id)
    if (g) { out.push(g); seen.add(id) }
  }
  for (const g of baseGroups.value) {
    if (!seen.has(g.id)) out.push(g)
  }
  return out
})

function itemVisible(item: NavItem) {
  if (!isLocked(item.to)) return true
  return isAdmin.value
}

const visibleStandalone = computed(() => standalone.value.filter(itemVisible))
const visibleGroups = computed(() =>
  orderedGroups.value
    .map(g => ({ ...g, items: g.items.filter(itemVisible) }))
    .filter(g => g.items.length > 0)
)

const route = useRoute()

function groupContainsActive(group: { items: NavItem[] }) {
  return group.items.some(it => it.to === '/' ? route.path === '/' : route.path.startsWith(it.to))
}

const activeGroupId = computed(() => visibleGroups.value.find(groupContainsActive)?.id ?? visibleGroups.value[0]?.id ?? '')

const openId = ref<string>(activeGroupId.value)
watch(activeGroupId, (val) => { openId.value = val })

function toggle(id: string) {
  openId.value = openId.value === id ? '' : id
}
</script>

<template>
  <nav class="flex flex-col gap-1">
    <NuxtLink
      v-for="item in visibleStandalone"
      :key="item.to"
      :to="item.to"
      class="nav-link"
      active-class="nav-link-active"
      exact-active-class="nav-link-active"
    >
      <SidebarIcon :name="item.icon" />
      <span class="flex-1">{{ item.label }}</span>
      <span v-if="isLocked(item.to)" class="text-amber-500" title="Locked: hidden from staff">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
          <path fill-rule="evenodd" d="M10 1a4 4 0 0 0-4 4v3H5a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7a2 2 0 0 0-2-2h-1V5a4 4 0 0 0-4-4Zm2 7V5a2 2 0 1 0-4 0v3h4Z" clip-rule="evenodd" />
        </svg>
      </span>
    </NuxtLink>
    <div v-for="group in visibleGroups" :key="group.id" class="mb-1">
      <button
        type="button"
        @click="toggle(group.id)"
        class="w-full flex items-center justify-between gap-2 px-3 py-2 rounded-lg text-xs font-semibold uppercase tracking-wide text-slate-500 hover:bg-slate-50 transition-colors"
        :class="{ 'text-sycamore-700': groupContainsActive(group) }"
      >
        <span class="flex items-center gap-2">
          <SidebarIcon :name="group.icon" />
          {{ group.label }}
        </span>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          class="w-4 h-4 transition-transform"
          :class="openId === group.id ? 'rotate-90' : ''"
        >
          <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 0-1.06L10.94 10 7.21 6.29a.75.75 0 0 1 1.08-1.04l4.25 4.25a.75.75 0 0 1 0 1.04l-4.25 4.25a.75.75 0 0 1-1.08-.02Z" clip-rule="evenodd" />
        </svg>
      </button>
      <div v-show="openId === group.id" class="mt-1 ml-2 pl-3 border-l border-slate-100 flex flex-col gap-1">
        <NuxtLink
          v-for="item in group.items"
          :key="item.to"
          :to="item.to"
          class="nav-link"
          active-class="nav-link-active"
          exact-active-class="nav-link-active"
        >
          <SidebarIcon :name="item.icon" />
          <span class="flex-1">{{ item.label }}</span>
          <span v-if="isLocked(item.to)" class="text-amber-500" title="Locked: hidden from staff">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
              <path fill-rule="evenodd" d="M10 1a4 4 0 0 0-4 4v3H5a2 2 0 0 0-2 2v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7a2 2 0 0 0-2-2h-1V5a4 4 0 0 0-4-4Zm2 7V5a2 2 0 1 0-4 0v3h4Z" clip-rule="evenodd" />
            </svg>
          </span>
        </NuxtLink>
      </div>
    </div>
  </nav>
</template>
