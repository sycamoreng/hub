<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const counts = ref<Record<string, number>>({})
const loading = ref(true)

const tables = [
  { table: 'onboarding_steps', label: 'Onboarding', to: '/admin/onboarding', icon: 'check' },
  { table: 'products', label: 'Products', to: '/admin/products', icon: 'gift' },
  { table: 'tech_stack', label: 'Technology', to: '/admin/technology', icon: 'palette' },
  { table: 'announcements', label: 'Announcements', to: '/admin/announcements', icon: 'info' },
  { table: 'holidays_events', label: 'Events & Holidays', to: '/admin/events', icon: 'calendar' },
  { table: 'policies', label: 'Policies', to: '/admin/policies', icon: 'book' },
  { table: 'staff_members', label: 'Staff', to: '/admin/staff', icon: 'users' },
  { table: 'leadership', label: 'Leadership', to: '/admin/leadership', icon: 'star' },
  { table: 'departments', label: 'Departments', to: '/admin/departments', icon: 'building' },
  { table: 'locations', label: 'Locations', to: '/admin/locations', icon: 'map' },
  { table: 'key_contacts', label: 'Key Contacts', to: '/admin/contacts', icon: 'phone' },
  { table: 'communication_tools', label: 'Communication', to: '/admin/communication', icon: 'chat' },
  { table: 'branding_guidelines', label: 'Branding', to: '/admin/branding', icon: 'palette' },
  { table: 'benefits_perks', label: 'Benefits', to: '/admin/benefits', icon: 'gift' },
  { table: 'company_info', label: 'Company Info', to: '/admin/company', icon: 'star' }
]

onMounted(async () => {
  try {
    const results = await Promise.all(
      tables.map(t => supabase.from(t.table).select('*', { count: 'exact', head: true }))
    )
    const map: Record<string, number> = {}
    results.forEach((r, i) => { map[tables[i].table] = r.count ?? 0 })
    counts.value = map
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="max-w-6xl">
    <div class="mb-8">
      <h1 class="section-title">Admin Overview</h1>
      <p class="section-subtitle">Manage all Sycamore content from here.</p>
    </div>

    <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <NuxtLink
        v-for="t in tables"
        :key="t.table"
        :to="t.to"
        class="card card-hover p-6 group"
      >
        <div class="flex items-center justify-between mb-4">
          <div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">
            <SidebarIcon :name="t.icon" />
          </div>
          <span class="text-2xl font-bold text-slate-900">{{ counts[t.table] ?? '...' }}</span>
        </div>
        <div class="font-semibold text-slate-900">{{ t.label }}</div>
        <div class="text-sm text-sycamore-700 mt-1 inline-flex items-center gap-1">
          Manage <SidebarIcon name="arrow-right" />
        </div>
      </NuxtLink>
    </div>
  </div>
</template>
