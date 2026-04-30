<script setup lang="ts">
interface NavItem { to: string; label: string; icon: string }
interface NavGroup { id: string; label: string; icon: string; items: NavItem[] }

import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const raffleVisible = ref(false)

async function loadRaffleVisibility() {
  const { data } = await supabase
    .from('raffle_settings')
    .select('visible_on_sidebar')
    .eq('id', 1)
    .maybeSingle()
  raffleVisible.value = Boolean((data as any)?.visible_on_sidebar)
}
loadRaffleVisibility()

const standalone = computed<NavItem[]>(() => {
  const items: NavItem[] = [
    { to: '/', label: 'Home', icon: 'home' },
    { to: '/feed', label: 'Feed', icon: 'chat' }
  ]
  if (raffleVisible.value) {
    items.push({ to: '/raffle', label: "Workers' Day Raffle", icon: 'sparkle' })
  }
  return items
})

const groups: NavGroup[] = [
  {
    id: 'company',
    label: 'Company',
    icon: 'building',
    items: [
      { to: '/leadership', label: 'Leadership', icon: 'star' },
      { to: '/departments', label: 'Departments', icon: 'building' },
      { to: '/locations', label: 'Locations', icon: 'map' },
      { to: '/staff', label: 'Staff Directory', icon: 'users' }
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
      { to: '/branding', label: 'Branding', icon: 'palette' }
    ]
  },
  {
    id: 'comms',
    label: 'Communication',
    icon: 'chat',
    items: [
      { to: '/communication', label: 'Communication', icon: 'chat' },
      { to: '/contacts', label: 'Key Contacts', icon: 'phone' },
      { to: '/calendar', label: 'Calendar', icon: 'calendar' }
    ]
  },
  {
    id: 'productivity',
    label: 'Productivity',
    icon: 'sparkle',
    items: [
      { to: '/tools', label: 'Tools', icon: 'gift' },
      { to: '/onboarding', label: 'Onboarding', icon: 'check' }
    ]
  }
]

const route = useRoute()

function groupContainsActive(group: NavGroup) {
  return group.items.some(it => it.to === '/' ? route.path === '/' : route.path.startsWith(it.to))
}

const activeGroupId = computed(() => groups.find(groupContainsActive)?.id ?? groups[0].id)

const openId = ref<string>(activeGroupId.value)
watch(activeGroupId, (val) => { openId.value = val })

function toggle(id: string) {
  openId.value = openId.value === id ? '' : id
}
</script>

<template>
  <nav class="flex flex-col gap-1">
    <NuxtLink
      v-for="item in standalone"
      :key="item.to"
      :to="item.to"
      class="nav-link"
      active-class="nav-link-active"
      exact-active-class="nav-link-active"
    >
      <SidebarIcon :name="item.icon" />
      <span>{{ item.label }}</span>
    </NuxtLink>
    <div v-for="group in groups" :key="group.id" class="mb-1">
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
          <span>{{ item.label }}</span>
        </NuxtLink>
      </div>
    </div>
  </nav>
</template>
