<script setup lang="ts">
import type { NotificationRow } from '~/composables/useNotifications'

const { user, ready } = useAuth()
const { items, unreadCount, loaded, load, subscribe, unsubscribe, markRead, markAllRead, dismiss } = useNotifications()

const open = ref(false)
const rootEl = ref<HTMLElement | null>(null)

async function ensureLoaded() {
  if (!user.value) return
  if (!loaded.value) await load(user.value.id)
  subscribe(user.value.id)
}

watch(() => ready.value && !!user.value, async (ok) => {
  if (ok) await ensureLoaded()
  else await unsubscribe()
}, { immediate: true })

onBeforeUnmount(() => { unsubscribe() })

function onDocClick(e: MouseEvent) {
  if (!open.value) return
  if (rootEl.value && !rootEl.value.contains(e.target as Node)) open.value = false
}

onMounted(() => document.addEventListener('click', onDocClick))
onBeforeUnmount(() => document.removeEventListener('click', onDocClick))

async function toggle() {
  open.value = !open.value
  if (open.value) await ensureLoaded()
}

async function activate(n: NotificationRow) {
  await markRead(n.id)
  open.value = false
  if (n.link) await navigateTo(n.link)
}

function relativeTime(iso: string) {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m`
  const hrs = Math.floor(mins / 60)
  if (hrs < 24) return `${hrs}h`
  const days = Math.floor(hrs / 24)
  if (days < 7) return `${days}d`
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}
</script>

<template>
  <div v-if="user" ref="rootEl" class="relative">
    <button
      type="button"
      class="relative w-9 h-9 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-50 flex items-center justify-center"
      :aria-label="`Notifications${unreadCount > 0 ? ` (${unreadCount} unread)` : ''}`"
      @click.stop="toggle"
    >
      <SidebarIcon name="bell" />
      <span
        v-if="unreadCount > 0"
        class="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-rose-500 text-white text-[10px] font-bold flex items-center justify-center"
      >{{ unreadCount > 9 ? '9+' : unreadCount }}</span>
    </button>

    <div
      v-if="open"
      class="absolute right-0 mt-2 w-[360px] max-w-[calc(100vw-2rem)] bg-white border border-slate-200 rounded-xl shadow-xl z-40"
      @click.stop
    >
      <div class="flex items-center justify-between p-3 border-b border-slate-100">
        <div>
          <div class="text-sm font-semibold text-slate-900">Notifications</div>
          <div class="text-[11px] text-slate-500">{{ unreadCount > 0 ? `${unreadCount} unread` : 'All caught up' }}</div>
        </div>
        <button
          type="button"
          class="text-xs text-sycamore-700 hover:underline"
          :disabled="unreadCount === 0"
          :class="unreadCount === 0 ? 'opacity-40 cursor-not-allowed' : ''"
          @click="user && markAllRead(user.id)"
        >Mark all read</button>
      </div>

      <div class="max-h-96 overflow-y-auto">
        <div v-if="!loaded" class="p-6 text-center text-xs text-slate-400">Loading...</div>
        <div v-else-if="items.length === 0" class="p-8 text-center text-xs text-slate-400">
          You have no notifications yet.
        </div>
        <ul v-else class="divide-y divide-slate-100">
          <li
            v-for="n in items.slice(0, 12)"
            :key="n.id"
            class="group flex gap-3 p-3 cursor-pointer hover:bg-slate-50"
            :class="!n.read_at ? 'bg-sycamore-50/40' : ''"
            @click="activate(n)"
          >
            <div class="flex-shrink-0 mt-1">
              <span
                class="inline-block w-2 h-2 rounded-full"
                :class="!n.read_at ? 'bg-sycamore-500' : 'bg-transparent'"
              />
            </div>
            <div class="min-w-0 flex-1">
              <div class="text-sm font-medium text-slate-900 truncate">{{ n.title }}</div>
              <div v-if="n.body" class="text-xs text-slate-500 line-clamp-2 mt-0.5">{{ n.body }}</div>
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
          </li>
        </ul>
      </div>

      <div class="p-2 border-t border-slate-100 text-center">
        <NuxtLink to="/notifications" class="text-xs text-sycamore-700 hover:underline" @click="open = false">
          View all notifications
        </NuxtLink>
      </div>
    </div>
  </div>
</template>
