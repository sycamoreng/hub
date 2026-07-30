<script setup lang="ts">
import type { ForumCategory, ForumThread } from '~/composables/useForums'

const { fetchCategories, fetchThreads, fetchMyChannels, joinChannel, leaveChannel, createThread, voteThread } = useForums()
const { user, isAdmin } = useAuth()
const toast = useToast()
const router = useRouter()

const loading = ref(true)
const categories = ref<ForumCategory[]>([])
const threads = ref<ForumThread[]>([])
const myChannelIds = ref<string[]>([])
const activeChannel = ref<string | null>(null)
const showComposer = ref(false)
const newTitle = ref('')
const newBody = ref('')
const posting = ref(false)
const showChannels = ref(false)
const showBrowse = ref(false)
const joiningId = ref<string | null>(null)

const joinedCategories = computed(() =>
  categories.value.filter(c => myChannelIds.value.includes(c.id))
)

const browseCategories = computed(() =>
  categories.value.filter(c => !myChannelIds.value.includes(c.id))
)

const activeChannelData = computed(() =>
  categories.value.find(c => c.slug === activeChannel.value) || null
)

const channelName = computed(() => activeChannelData.value?.name || '')
const channelIcon = computed(() => activeChannelData.value?.icon || '#')
const channelDescription = computed(() => activeChannelData.value?.description || '')

async function load() {
  loading.value = true
  const [cats, channels] = await Promise.all([
    fetchCategories(),
    fetchMyChannels()
  ])
  categories.value = cats
  myChannelIds.value = channels

  if (!activeChannel.value && channels.length > 0) {
    const firstJoined = cats.find(c => channels.includes(c.id))
    if (firstJoined) activeChannel.value = firstJoined.slug
  }

  if (activeChannel.value) {
    threads.value = await fetchThreads(activeChannel.value)
  } else {
    threads.value = []
  }
  loading.value = false
}

function selectChannel(slug: string) {
  activeChannel.value = slug
  showChannels.value = false
  showBrowse.value = false
  loadThreads()
}

async function loadThreads() {
  if (!activeChannel.value) { threads.value = []; return }
  loading.value = true
  threads.value = await fetchThreads(activeChannel.value)
  loading.value = false
}

async function handleJoin(cat: ForumCategory) {
  joiningId.value = cat.id
  await joinChannel(cat.id)
  myChannelIds.value = [...myChannelIds.value, cat.id]
  toast.success(`Joined #${cat.name.toLowerCase().replace(/\s+/g, '-')}`)
  joiningId.value = null
  selectChannel(cat.slug)
}

async function handleLeave(cat: ForumCategory) {
  if (activeChannel.value === cat.slug) {
    const remaining = joinedCategories.value.filter(c => c.id !== cat.id)
    activeChannel.value = remaining.length > 0 ? remaining[0].slug : null
  }
  await leaveChannel(cat.id)
  myChannelIds.value = myChannelIds.value.filter(id => id !== cat.id)
  toast.success(`Left #${cat.name.toLowerCase().replace(/\s+/g, '-')}`)
  await loadThreads()
}

async function submitThread() {
  if (!newTitle.value.trim()) { toast.error('Message needs a title'); return }
  const categoryId = activeChannelData.value?.id
  if (!categoryId) { toast.error('Join a channel first'); return }
  posting.value = true
  try {
    const result = await createThread(categoryId, newTitle.value.trim(), newBody.value.trim())
    if (result?.id) {
      newTitle.value = ''
      newBody.value = ''
      showComposer.value = false
      toast.success('Posted!')
      await loadThreads()
    }
  } catch (e: any) {
    toast.error(e.message || 'Failed to post')
  }
  posting.value = false
}

async function handleVote(threadId: string, vote: 1 | -1) {
  await voteThread(threadId, vote)
  const t = threads.value.find(t => t.id === threadId)
  if (t) {
    const newVote = t.user_vote === vote ? 0 : vote
    t.vote_score = (t.vote_score || 0) - (t.user_vote || 0) + newVote
    t.user_vote = newVote
  }
}

function timeDisplay(d: string) {
  const date = new Date(d)
  const now = new Date()
  const diff = now.getTime() - date.getTime()
  const isToday = date.toDateString() === now.toDateString()
  const isYesterday = new Date(now.getTime() - 86400000).toDateString() === date.toDateString()

  const time = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })
  if (isToday) return time
  if (isYesterday) return `Yesterday ${time}`
  if (diff < 7 * 86400000) return `${date.toLocaleDateString('en-US', { weekday: 'short' })} ${time}`
  return date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}

function shouldShowDateDivider(index: number): string | null {
  if (index === 0) return formatDate(threads.value[0].created_at)
  const prev = new Date(threads.value[index - 1].created_at).toDateString()
  const curr = new Date(threads.value[index].created_at).toDateString()
  if (prev !== curr) return formatDate(threads.value[index].created_at)
  return null
}

function formatDate(d: string) {
  const date = new Date(d)
  const now = new Date()
  if (date.toDateString() === now.toDateString()) return 'Today'
  if (new Date(now.getTime() - 86400000).toDateString() === date.toDateString()) return 'Yesterday'
  return date.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' })
}

await load()
</script>

<template>
  <div class="flex h-[calc(100vh-64px)] sm:h-[calc(100vh-72px)] -mx-4 sm:-mx-6 -my-6 sm:-my-6 overflow-hidden">
    <!-- Channel Sidebar -->
    <aside class="w-64 border-r border-slate-200 bg-white flex-col overflow-y-auto hidden lg:flex">
      <div class="p-4 border-b border-slate-100 flex items-center justify-between">
        <h2 class="text-sm font-bold text-slate-900">Channels</h2>
        <button
          @click="showBrowse = !showBrowse"
          class="w-6 h-6 rounded-md hover:bg-slate-100 flex items-center justify-center text-slate-400 hover:text-slate-600 transition-colors"
          title="Browse channels"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
        </button>
      </div>
      <nav class="flex-1 p-2 space-y-0.5">
        <template v-if="joinedCategories.length > 0">
          <button
            v-for="cat in joinedCategories"
            :key="cat.id"
            @click="selectChannel(cat.slug)"
            class="w-full flex items-center gap-2.5 px-3 py-2 rounded-lg text-sm transition-colors text-left group"
            :class="activeChannel === cat.slug ? 'bg-sycamore-50 text-sycamore-700 font-semibold' : 'text-slate-600 hover:bg-slate-50'"
          >
            <span class="w-5 text-center">{{ cat.icon }}</span>
            <span class="truncate flex-1">{{ cat.name.toLowerCase().replace(/\s+/g, '-') }}</span>
            <span v-if="cat.thread_count" class="text-[10px] bg-slate-100 text-slate-500 px-1.5 py-0.5 rounded-full">{{ cat.thread_count }}</span>
          </button>
        </template>
        <div v-else class="px-3 py-6 text-center">
          <p class="text-xs text-slate-400 mb-2">You haven't joined any channels yet</p>
          <button @click="showBrowse = true" class="text-xs text-sycamore-600 hover:text-sycamore-700 font-medium">Browse channels</button>
        </div>
      </nav>
    </aside>

    <!-- Browse Channels Panel -->
    <aside v-if="showBrowse" class="w-72 border-r border-slate-200 bg-slate-50 flex-col overflow-y-auto hidden lg:flex">
      <div class="p-4 border-b border-slate-100 flex items-center justify-between">
        <h2 class="text-sm font-bold text-slate-900">Browse channels</h2>
        <button @click="showBrowse = false" class="w-6 h-6 rounded-md hover:bg-slate-200 flex items-center justify-center text-slate-400 hover:text-slate-600">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
        </button>
      </div>
      <div class="p-3 space-y-2">
        <!-- Unjoined channels -->
        <template v-if="browseCategories.length > 0">
          <div
            v-for="cat in browseCategories"
            :key="cat.id"
            class="p-3 bg-white rounded-lg border border-slate-200"
          >
            <div class="flex items-center gap-2 mb-1">
              <span>{{ cat.icon }}</span>
              <span class="text-sm font-semibold text-slate-900">{{ cat.name }}</span>
            </div>
            <p class="text-xs text-slate-500 mb-2 line-clamp-2">{{ cat.description }}</p>
            <button
              @click="handleJoin(cat)"
              :disabled="joiningId === cat.id"
              class="text-xs font-medium text-sycamore-600 hover:text-sycamore-700 transition-colors"
            >
              {{ joiningId === cat.id ? 'Joining...' : 'Join channel' }}
            </button>
          </div>
        </template>
        <p v-else class="text-xs text-slate-400 text-center py-4">You've joined all available channels</p>

        <!-- Already joined -->
        <template v-if="joinedCategories.length > 0">
          <div class="pt-3 border-t border-slate-200 mt-3">
            <p class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide px-1 mb-2">Joined</p>
            <div
              v-for="cat in joinedCategories"
              :key="cat.id"
              class="flex items-center gap-2 px-2 py-1.5 rounded-md"
            >
              <span class="text-sm">{{ cat.icon }}</span>
              <span class="text-xs text-slate-600 flex-1 truncate">{{ cat.name }}</span>
              <button
                @click="handleLeave(cat)"
                class="text-[10px] text-red-500 hover:text-red-600 font-medium"
              >Leave</button>
            </div>
          </div>
        </template>
      </div>
    </aside>

    <!-- Main Chat Area -->
    <div class="flex-1 flex flex-col min-w-0 bg-white">
      <!-- Channel Header -->
      <header class="flex items-center gap-3 px-4 sm:px-5 py-3 border-b border-slate-200 bg-white shrink-0">
        <button @click="showChannels = !showChannels" class="lg:hidden p-1.5 rounded-lg hover:bg-slate-100 text-slate-500">
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" /></svg>
        </button>
        <div v-if="activeChannelData" class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="text-base">{{ channelIcon }}</span>
            <h1 class="font-bold text-slate-900 text-sm sm:text-base truncate">{{ channelName }}</h1>
          </div>
          <p class="text-xs text-slate-500 truncate hidden sm:block">{{ channelDescription }}</p>
        </div>
        <div v-else class="flex-1 min-w-0">
          <h1 class="font-bold text-slate-900 text-sm sm:text-base">Forums</h1>
          <p class="text-xs text-slate-500 hidden sm:block">Join a channel to start chatting</p>
        </div>
        <div class="flex items-center gap-2">
          <span v-if="activeChannelData" class="text-xs text-slate-400 hidden sm:block">{{ threads.length }} thread{{ threads.length !== 1 ? 's' : '' }}</span>
          <button
            v-if="activeChannelData"
            @click="handleLeave(activeChannelData)"
            class="text-xs text-slate-400 hover:text-red-500 transition-colors hidden sm:block"
          >Leave</button>
        </div>
      </header>

      <!-- Mobile Channel Dropdown -->
      <div v-if="showChannels" class="lg:hidden border-b border-slate-200 bg-slate-50 p-3 space-y-1">
        <p class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide px-2 mb-1">Your channels</p>
        <button
          v-for="cat in joinedCategories"
          :key="cat.id"
          @click="selectChannel(cat.slug)"
          class="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm"
          :class="activeChannel === cat.slug ? 'bg-sycamore-50 text-sycamore-700 font-semibold' : 'text-slate-600'"
        >
          <span>{{ cat.icon }}</span>
          <span>{{ cat.name.toLowerCase().replace(/\s+/g, '-') }}</span>
        </button>
        <div class="border-t border-slate-200 pt-2 mt-2">
          <p class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide px-2 mb-1">Browse</p>
          <button
            v-for="cat in browseCategories"
            :key="cat.id"
            @click="handleJoin(cat)"
            class="w-full flex items-center gap-2 px-3 py-2 rounded-lg text-sm text-slate-500"
          >
            <span>{{ cat.icon }}</span>
            <span>{{ cat.name.toLowerCase().replace(/\s+/g, '-') }}</span>
            <span class="ml-auto text-[10px] text-sycamore-600 font-medium">Join</span>
          </button>
        </div>
      </div>

      <!-- Messages -->
      <div class="flex-1 overflow-y-auto px-4 sm:px-5 py-4" ref="messagesContainer">
        <div v-if="loading" class="space-y-4 py-4">
          <div v-for="i in 6" :key="i" class="flex gap-3 animate-pulse">
            <div class="w-9 h-9 rounded-lg bg-slate-200 shrink-0"></div>
            <div class="flex-1">
              <div class="h-3.5 bg-slate-200 rounded w-28 mb-2"></div>
              <div class="h-4 bg-slate-100 rounded w-2/3 mb-1"></div>
              <div class="h-3 bg-slate-100 rounded w-1/2"></div>
            </div>
          </div>
        </div>

        <!-- No channel selected / no joined channels -->
        <div v-else-if="!activeChannelData" class="flex flex-col items-center justify-center py-16 text-center">
          <div class="w-16 h-16 rounded-2xl bg-slate-100 flex items-center justify-center text-3xl mb-4">#</div>
          <h3 class="font-semibold text-slate-700 mb-1">Join a channel to get started</h3>
          <p class="text-sm text-slate-500 mb-4 max-w-xs">Channels are spaces for your team to discuss topics. Join the ones that interest you.</p>
          <button @click="showBrowse = true" class="btn-primary text-sm hidden lg:inline-flex">Browse channels</button>
          <button @click="showChannels = true" class="btn-primary text-sm lg:hidden">Browse channels</button>
        </div>

        <div v-else-if="threads.length === 0" class="flex flex-col items-center justify-center py-16 text-center">
          <div class="w-14 h-14 rounded-2xl bg-slate-100 flex items-center justify-center text-2xl mb-4">{{ channelIcon }}</div>
          <h3 class="font-semibold text-slate-700 mb-1">No messages in {{ channelName }}</h3>
          <p class="text-sm text-slate-500 mb-4">Start the conversation by posting a message below.</p>
        </div>

        <div v-else class="space-y-0">
          <template v-for="(thread, idx) in threads" :key="thread.id">
            <!-- Date divider -->
            <div v-if="shouldShowDateDivider(idx)" class="flex items-center gap-3 py-3">
              <div class="flex-1 h-px bg-slate-200"></div>
              <span class="text-[11px] font-medium text-slate-500 bg-white px-2">{{ shouldShowDateDivider(idx) }}</span>
              <div class="flex-1 h-px bg-slate-200"></div>
            </div>

            <!-- Message -->
            <NuxtLink
              :to="`/forums/${thread.id}`"
              class="flex gap-3 px-3 py-2.5 -mx-3 rounded-lg hover:bg-slate-50 transition-colors group"
            >
              <div
                class="w-9 h-9 rounded-lg flex items-center justify-center text-sm font-bold shrink-0"
                :class="thread.author_avatar ? '' : 'bg-gradient-to-br from-sycamore-100 to-sycamore-200 text-sycamore-700'"
              >
                <img v-if="thread.author_avatar" :src="thread.author_avatar" class="w-9 h-9 rounded-lg object-cover" />
                <span v-else>{{ thread.author_name?.charAt(0) || '?' }}</span>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-baseline gap-2 mb-0.5">
                  <span class="text-[13px] font-bold text-slate-900">{{ thread.author_name }}</span>
                  <span class="text-[11px] text-slate-400">{{ timeDisplay(thread.created_at) }}</span>
                </div>
                <div class="flex items-start gap-2">
                  <div class="flex-1 min-w-0">
                    <h3 class="text-[13px] font-semibold text-slate-800 group-hover:text-sycamore-700 transition-colors">{{ thread.title }}</h3>
                    <p v-if="thread.body" class="text-xs text-slate-500 line-clamp-2 mt-0.5 leading-relaxed">{{ thread.body }}</p>
                  </div>
                </div>
                <!-- Reactions row -->
                <div class="flex items-center gap-3 mt-1.5">
                  <button
                    v-if="(thread.vote_score || 0) !== 0 || thread.user_vote"
                    @click.prevent="handleVote(thread.id, 1)"
                    class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] border transition-colors"
                    :class="thread.user_vote === 1 ? 'bg-sycamore-50 border-sycamore-200 text-sycamore-700' : 'bg-slate-50 border-slate-200 text-slate-500 hover:border-slate-300'"
                  >
                    <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 15l7-7 7 7" /></svg>
                    {{ thread.vote_score || 0 }}
                  </button>
                  <span v-if="thread.reply_count" class="inline-flex items-center gap-1 text-[11px] text-sycamore-600 font-medium">
                    <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" /></svg>
                    {{ thread.reply_count }} {{ thread.reply_count === 1 ? 'reply' : 'replies' }}
                  </span>
                  <span v-if="thread.is_resolved" class="inline-flex items-center gap-0.5 text-[10px] font-semibold text-emerald-600">
                    <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
                    Resolved
                  </span>
                  <span v-if="thread.is_pinned" class="text-[10px] text-amber-600 font-medium">Pinned</span>
                </div>
              </div>
            </NuxtLink>
          </template>
        </div>
      </div>

      <!-- Composer -->
      <div v-if="activeChannelData" class="shrink-0 border-t border-slate-200 bg-white px-4 sm:px-5 py-3">
        <div v-if="!showComposer" class="flex items-center gap-2">
          <button
            @click="showComposer = true"
            class="flex-1 flex items-center gap-2 px-4 py-2.5 rounded-lg border border-slate-200 text-sm text-slate-400 hover:border-slate-300 hover:text-slate-500 transition-colors text-left"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" /></svg>
            Post to #{{ activeChannelData.name.toLowerCase().replace(/\s+/g, '-') }}...
          </button>
        </div>
        <div v-else class="rounded-xl border border-slate-200 bg-white shadow-sm overflow-hidden focus-within:border-sycamore-300 focus-within:ring-2 focus-within:ring-sycamore-100 transition-all">
          <input
            v-model="newTitle"
            type="text"
            class="w-full px-4 pt-3 pb-1 text-sm font-semibold text-slate-900 placeholder:text-slate-400 focus:outline-none border-0"
            placeholder="Thread title"
            @keydown.escape="showComposer = false"
          />
          <textarea
            v-model="newBody"
            class="w-full px-4 pt-1 pb-3 text-sm text-slate-700 placeholder:text-slate-400 focus:outline-none resize-none border-0 min-h-[60px]"
            placeholder="Add more detail... (optional)"
            rows="2"
          ></textarea>
          <div class="flex items-center justify-between px-3 py-2 border-t border-slate-100 bg-slate-50/50">
            <div class="flex items-center gap-1 text-xs text-slate-500">
              <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-slate-100 text-slate-600 text-[11px]">
                {{ activeChannelData.icon }} {{ activeChannelData.name }}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <button @click="showComposer = false; newTitle = ''; newBody = ''" class="text-xs text-slate-500 hover:text-slate-700 px-2 py-1">
                Cancel
              </button>
              <button
                @click="submitThread"
                :disabled="posting || !newTitle.trim()"
                class="btn-primary text-xs py-1.5 px-3 min-h-0"
                :class="!newTitle.trim() ? 'opacity-50 cursor-not-allowed' : ''"
              >
                {{ posting ? '...' : 'Post' }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
