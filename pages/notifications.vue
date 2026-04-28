<script setup lang="ts">
definePageMeta({ middleware: ['auth'] })

const { user, ready } = useAuth()
const { items, unreadCount, loaded, load, subscribe, unsubscribe, markRead, markAllRead, dismiss } = useNotifications()

watch(() => ready.value && !!user.value, async (ok) => {
  if (ok && user.value) {
    await load(user.value.id, 100)
    subscribe(user.value.id)
  }
}, { immediate: true })

onBeforeUnmount(() => { unsubscribe() })

async function activate(id: string, link: string) {
  await markRead(id)
  if (link) await navigateTo(link)
}

function relativeTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins} min ago`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs} hr ago`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days} days ago`
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}
</script>

<template>
  <div class="max-w-3xl mx-auto space-y-6">
    <div class="flex items-end justify-between gap-4 flex-wrap">
      <div>
        <h1 class="section-title">Notifications</h1>
        <p class="section-subtitle">Updates, reactions, and announcements directed at you.</p>
      </div>
      <button
        type="button"
        class="text-xs font-medium text-sycamore-700 hover:underline disabled:opacity-40"
        :disabled="unreadCount === 0"
        @click="user && markAllRead(user.id)"
      >Mark all read</button>
    </div>

    <div class="card divide-y divide-slate-100">
      <div v-if="!loaded" class="p-8 text-center text-sm text-slate-400">Loading...</div>
      <div v-else-if="items.length === 0" class="p-12 text-center">
        <div class="text-sm text-slate-500">You have no notifications.</div>
        <div class="text-xs text-slate-400 mt-1">When colleagues post or react to your work you will see it here.</div>
      </div>
      <div
        v-for="n in items"
        v-else
        :key="n.id"
        class="group flex gap-3 p-4 hover:bg-slate-50 cursor-pointer"
        :class="!n.read_at ? 'bg-sycamore-50/40' : ''"
        @click="activate(n.id, n.link)"
      >
        <div class="flex-shrink-0 mt-1.5">
          <span class="inline-block w-2 h-2 rounded-full" :class="!n.read_at ? 'bg-sycamore-500' : 'bg-slate-200'" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="text-sm font-medium text-slate-900">{{ n.title }}</div>
          <div v-if="n.body" class="text-xs text-slate-600 mt-0.5">{{ n.body }}</div>
          <div class="text-[11px] text-slate-400 mt-1">{{ relativeTime(n.created_at) }}</div>
        </div>
        <button
          type="button"
          class="text-slate-300 hover:text-slate-600 opacity-0 group-hover:opacity-100"
          aria-label="Dismiss"
          @click.stop="dismiss(n.id)"
        >
          <SidebarIcon name="close" />
        </button>
      </div>
    </div>
  </div>
</template>
