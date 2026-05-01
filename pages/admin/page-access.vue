<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { isSuperAdmin } = useAuth()
const { load, setLock, isLocked } = usePageLocks()
const toast = useToast()

interface PageEntry { path: string; label: string; group: string }

const pages: PageEntry[] = [
  { path: '/', label: 'Home', group: 'General' },
  { path: '/feed', label: 'Feed', group: 'General' },
  { path: '/raffle', label: "Workers' Day Raffle", group: 'General' },
  { path: '/leadership', label: 'Leadership', group: 'Company' },
  { path: '/departments', label: 'Departments', group: 'Company' },
  { path: '/locations', label: 'Locations', group: 'Company' },
  { path: '/staff', label: 'Staff Directory', group: 'Company' },
  { path: '/products', label: 'Products', group: 'Products & Tech' },
  { path: '/technology', label: 'Technology', group: 'Products & Tech' },
  { path: '/policies', label: 'Policies', group: 'People & Culture' },
  { path: '/benefits', label: 'Benefits & Perks', group: 'People & Culture' },
  { path: '/branding', label: 'Branding', group: 'People & Culture' },
  { path: '/communication', label: 'Communication', group: 'Communication' },
  { path: '/contacts', label: 'Key Contacts', group: 'Communication' },
  { path: '/calendar', label: 'Calendar', group: 'Communication' },
  { path: '/tools', label: 'Tools', group: 'Productivity' },
  { path: '/onboarding', label: 'Learning', group: 'Productivity' }
]

const grouped = computed(() => {
  const map = new Map<string, PageEntry[]>()
  for (const p of pages) {
    if (!map.has(p.group)) map.set(p.group, [])
    map.get(p.group)!.push(p)
  }
  return [...map.entries()].map(([group, items]) => ({ group, items }))
})

const busy = ref<string | null>(null)

async function toggle(entry: PageEntry) {
  if (!isSuperAdmin.value) return
  busy.value = entry.path
  try {
    await setLock(entry.path, !isLocked(entry.path))
    toast.push({ type: 'success', title: isLocked(entry.path) ? 'Page locked' : 'Page unlocked', message: entry.label })
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not update', message: e?.message ?? 'Unexpected error' })
  } finally {
    busy.value = null
  }
}

await load(true)
</script>

<template>
  <div v-if="!isSuperAdmin" class="card p-8 text-center">
    <h1 class="section-title">Restricted</h1>
    <p class="section-subtitle">Only super admins can manage page access.</p>
  </div>
  <div v-else class="space-y-6">
    <header>
      <h1 class="section-title">Page access</h1>
      <p class="section-subtitle">Lock pages that aren't ready for staff. Locked pages are hidden from the sidebar and blocked for non-admins. Admins keep access so you can preview and finish content.</p>
    </header>

    <section v-for="g in grouped" :key="g.group" class="card p-4 sm:p-6 space-y-3">
      <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">{{ g.group }}</h2>
      <ul class="divide-y divide-slate-100">
        <li v-for="item in g.items" :key="item.path" class="flex items-center justify-between gap-4 py-3">
          <div class="min-w-0">
            <div class="text-sm font-medium text-slate-900 truncate">{{ item.label }}</div>
            <div class="text-xs text-slate-500 font-mono">{{ item.path }}</div>
          </div>
          <div class="flex items-center gap-3 shrink-0">
            <span
              class="text-xs font-semibold px-2 py-0.5 rounded-full"
              :class="isLocked(item.path) ? 'bg-amber-50 text-amber-700' : 'bg-emerald-50 text-emerald-700'"
            >
              {{ isLocked(item.path) ? 'Locked' : 'Unlocked' }}
            </span>
            <button
              type="button"
              class="btn-secondary text-xs"
              :disabled="busy === item.path"
              @click="toggle(item)"
            >
              {{ busy === item.path ? 'Saving...' : isLocked(item.path) ? 'Unlock' : 'Lock' }}
            </button>
          </div>
        </li>
      </ul>
    </section>
  </div>
</template>
