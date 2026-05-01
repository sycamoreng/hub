<script setup lang="ts">
interface NavItem { to: string; label: string; icon: string; section?: string; superAdminOnly?: boolean }
interface NavGroup { id: string; label: string; icon: string; items: NavItem[] }

const { canManageSection, isSuperAdmin } = useAuth()

const standalone: NavItem[] = [
  { to: '/admin', label: 'Overview', icon: 'home' }
]

const groups: NavGroup[] = [
  {
    id: 'people',
    label: 'People',
    icon: 'users',
    items: [
      { to: '/admin/staff', label: 'Staff', icon: 'users', section: 'staff' },
      { to: '/admin/leadership', label: 'Leadership', icon: 'star', section: 'leadership' },
      { to: '/admin/departments', label: 'Departments', icon: 'building', section: 'departments' },
      { to: '/admin/onboarding', label: 'Onboarding', icon: 'check', section: 'onboarding' }
    ]
  },
  {
    id: 'work',
    label: 'Products & Tech',
    icon: 'gift',
    items: [
      { to: '/admin/products', label: 'Products', icon: 'gift', section: 'products' },
      { to: '/admin/technology', label: 'Technology', icon: 'palette', section: 'technology' },
      { to: '/admin/chatbot', label: 'Chatbot', icon: 'chat', section: 'chatbot' }
    ]
  },
  {
    id: 'comms',
    label: 'Communication',
    icon: 'chat',
    items: [
      { to: '/admin/announcements', label: 'Announcements', icon: 'info', section: 'announcements' },
      { to: '/admin/events', label: 'Events & Holidays', icon: 'calendar', section: 'events' },
      { to: '/admin/communication', label: 'Communication', icon: 'chat', section: 'communication' },
      { to: '/admin/contacts', label: 'Key Contacts', icon: 'phone', section: 'contacts' },
      { to: '/admin/quick-tools', label: 'Quick Tools', icon: 'arrow-right', section: 'quick-tools' },
      { to: '/admin/email', label: 'Email Settings', icon: 'info', section: 'email' },
      { to: '/admin/email-templates', label: 'Email Templates', icon: 'book', section: 'email-templates' },
      { to: '/admin/broadcast', label: 'Broadcast', icon: 'mail', section: 'broadcast' },
      { to: '/admin/raffle', label: "Workers' Day Raffle", icon: 'sparkle' }
    ]
  },
  {
    id: 'company',
    label: 'Company',
    icon: 'building',
    items: [
      { to: '/admin/policies', label: 'Policies', icon: 'book', section: 'policies' },
      { to: '/admin/benefits', label: 'Benefits', icon: 'gift', section: 'benefits' },
      { to: '/admin/branding', label: 'Branding', icon: 'palette', section: 'branding' },
      { to: '/admin/locations', label: 'Locations', icon: 'map', section: 'locations' },
      { to: '/admin/company', label: 'Company Info', icon: 'star', section: 'company' }
    ]
  },
  {
    id: 'access',
    label: 'Access control',
    icon: 'star',
    items: [
      { to: '/admin/admins', label: 'Admin Access', icon: 'users', superAdminOnly: true },
      { to: '/admin/page-access', label: 'Page Access', icon: 'check', superAdminOnly: true },
      { to: '/admin/sidebar-order', label: 'Sidebar Order', icon: 'arrow-right', superAdminOnly: true },
      { to: '/admin/google-sync', label: 'Google Sync', icon: 'sparkle', superAdminOnly: true }
    ]
  }
]

function itemVisible(item: NavItem) {
  if (item.superAdminOnly) return isSuperAdmin.value
  if (!item.section) return true
  return canManageSection(item.section)
}

const visibleGroups = computed(() =>
  groups
    .map(g => ({ ...g, items: g.items.filter(itemVisible) }))
    .filter(g => g.items.length > 0)
)

const route = useRoute()

function groupContainsActive(group: { items: NavItem[] }) {
  return group.items.some(it => it.to === '/admin' ? route.path === '/admin' : route.path.startsWith(it.to))
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
      v-for="item in standalone"
      :key="item.to"
      :to="item.to"
      class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-slate-300 hover:bg-slate-800 hover:text-white transition-colors"
      active-class="bg-sycamore-600 text-white hover:bg-sycamore-600"
      exact
    >
      <SidebarIcon :name="item.icon" />
      <span>{{ item.label }}</span>
    </NuxtLink>
    <div v-for="group in visibleGroups" :key="group.id" class="mb-1">
      <button
        type="button"
        @click="toggle(group.id)"
        class="w-full flex items-center justify-between gap-2 px-3 py-2 rounded-lg text-xs font-semibold uppercase tracking-wide text-slate-400 hover:bg-slate-800 transition-colors"
        :class="{ 'text-white': groupContainsActive(group) }"
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
      <div v-show="openId === group.id" class="mt-1 ml-2 pl-3 border-l border-slate-800 flex flex-col gap-1">
        <NuxtLink
          v-for="item in group.items"
          :key="item.to"
          :to="item.to"
          class="flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-slate-300 hover:bg-slate-800 hover:text-white transition-colors"
          active-class="bg-sycamore-600 text-white hover:bg-sycamore-600"
          :exact="item.to === '/admin'"
        >
          <SidebarIcon :name="item.icon" />
          <span>{{ item.label }}</span>
        </NuxtLink>
      </div>
    </div>
  </nav>
</template>
