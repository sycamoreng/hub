<script setup lang="ts">
import type { ForumThread, ForumReply } from '~/composables/useForums'

const route = useRoute()
const router = useRouter()
const { user, isAdmin } = useAuth()
const { fetchThread, fetchReplies, createReply, voteThread, voteReply, toggleResolved, acceptReply, deleteThread, deleteReply } = useForums()
const toast = useToast()

const threadId = route.params.id as string
const loading = ref(true)
const thread = ref<ForumThread | null>(null)
const replies = ref<ForumReply[]>([])
const replyBody = ref('')
const submittingReply = ref(false)

async function load() {
  loading.value = true
  const [t, r] = await Promise.all([
    fetchThread(threadId),
    fetchReplies(threadId)
  ])
  thread.value = t
  replies.value = r
  loading.value = false
}

const isAuthor = computed(() => thread.value && user.value && thread.value.author_id === user.value.id)

async function submitReply() {
  if (!replyBody.value.trim()) return
  submittingReply.value = true
  try {
    await createReply(threadId, replyBody.value.trim())
    replyBody.value = ''
    await load()
  } catch (e: any) {
    toast.error(e.message || 'Failed to post reply')
  }
  submittingReply.value = false
}

async function handleVoteThread(vote: 1 | -1) {
  if (!thread.value) return
  await voteThread(threadId, vote)
  const newVote = thread.value.user_vote === vote ? 0 : vote
  thread.value.vote_score = (thread.value.vote_score || 0) - (thread.value.user_vote || 0) + newVote
  thread.value.user_vote = newVote
}

async function handleVoteReply(replyId: string, vote: 1 | -1) {
  await voteReply(replyId, vote)
  const r = replies.value.find(r => r.id === replyId)
  if (r) {
    const newVote = r.user_vote === vote ? 0 : vote
    r.vote_score = (r.vote_score || 0) - (r.user_vote || 0) + newVote
    r.user_vote = newVote
  }
}

async function handleToggleResolved() {
  if (!thread.value) return
  await toggleResolved(threadId, !thread.value.is_resolved)
  thread.value.is_resolved = !thread.value.is_resolved
}

async function handleAcceptReply(replyId: string) {
  const r = replies.value.find(r => r.id === replyId)
  if (!r) return
  await acceptReply(replyId, !r.is_accepted)
  r.is_accepted = !r.is_accepted
}

async function handleDeleteThread() {
  if (!confirm('Delete this thread and all replies?')) return
  await deleteThread(threadId)
  router.push('/forums')
  toast.success('Thread deleted')
}

async function handleDeleteReply(replyId: string) {
  if (!confirm('Delete this reply?')) return
  await deleteReply(replyId)
  replies.value = replies.value.filter(r => r.id !== replyId)
}

function timeDisplay(d: string) {
  const date = new Date(d)
  const now = new Date()
  const isToday = date.toDateString() === now.toDateString()
  const time = date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true })
  if (isToday) return time
  return `${date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })} at ${time}`
}

await load()
</script>

<template>
  <div class="flex flex-col h-[calc(100vh-64px)] sm:h-[calc(100vh-72px)] -mx-4 sm:-mx-6 -my-6 sm:-my-6 overflow-hidden bg-white">
    <!-- Header -->
    <header class="flex items-center gap-3 px-4 sm:px-5 py-3 border-b border-slate-200 shrink-0">
      <NuxtLink to="/forums" class="p-1.5 rounded-lg hover:bg-slate-100 text-slate-500 transition-colors">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" /></svg>
      </NuxtLink>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <h1 class="font-bold text-slate-900 text-sm truncate">Thread</h1>
          <span v-if="thread?.is_resolved" class="inline-flex items-center gap-0.5 px-2 py-0.5 rounded-full text-[10px] font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
            <svg class="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
            Resolved
          </span>
          <span v-if="thread?.is_locked" class="text-[10px] text-slate-500 font-medium bg-slate-100 px-2 py-0.5 rounded-full">Locked</span>
        </div>
        <p v-if="thread" class="text-[11px] text-slate-500 truncate">{{ thread.category_icon }} {{ thread.category_name }} &middot; {{ replies.length }} replies</p>
      </div>
      <div v-if="thread && (isAuthor || isAdmin)" class="flex items-center gap-1">
        <button @click="handleToggleResolved" class="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-emerald-600 transition-colors" :title="thread.is_resolved ? 'Unmark resolved' : 'Mark as resolved'">
          <svg class="w-4.5 h-4.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
        </button>
        <button @click="handleDeleteThread" class="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-red-600 transition-colors" title="Delete thread">
          <svg class="w-4.5 h-4.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
        </button>
      </div>
    </header>

    <!-- Messages scroll area -->
    <div class="flex-1 overflow-y-auto px-4 sm:px-5 py-4 space-y-0">
      <!-- Loading -->
      <div v-if="loading" class="space-y-4 py-4">
        <div v-for="i in 4" :key="i" class="flex gap-3 animate-pulse">
          <div class="w-9 h-9 rounded-lg bg-slate-200 shrink-0"></div>
          <div class="flex-1">
            <div class="h-3 bg-slate-200 rounded w-24 mb-2"></div>
            <div class="h-4 bg-slate-100 rounded w-3/4"></div>
          </div>
        </div>
      </div>

      <template v-else-if="thread">
        <!-- Original post -->
        <div class="flex gap-3 py-3 border-b border-slate-100 mb-2">
          <div
            class="w-10 h-10 rounded-lg flex items-center justify-center text-sm font-bold shrink-0 bg-gradient-to-br from-sycamore-100 to-sycamore-200 text-sycamore-700"
          >
            <img v-if="thread.author_avatar" :src="thread.author_avatar" class="w-10 h-10 rounded-lg object-cover" />
            <span v-else>{{ thread.author_name?.charAt(0) || '?' }}</span>
          </div>
          <div class="flex-1 min-w-0">
            <div class="flex items-baseline gap-2 mb-1">
              <span class="text-[13px] font-bold text-slate-900">{{ thread.author_name }}</span>
              <span class="text-[11px] text-slate-400">{{ timeDisplay(thread.created_at) }}</span>
            </div>
            <h2 class="text-[15px] font-bold text-slate-900 mb-1">{{ thread.title }}</h2>
            <p v-if="thread.body" class="text-sm text-slate-700 leading-relaxed whitespace-pre-wrap">{{ thread.body }}</p>
            <div class="flex items-center gap-2 mt-2">
              <button
                @click="handleVoteThread(1)"
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] border transition-colors"
                :class="thread.user_vote === 1 ? 'bg-sycamore-50 border-sycamore-200 text-sycamore-700' : 'bg-slate-50 border-slate-200 text-slate-500 hover:border-slate-300'"
              >
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 15l7-7 7 7" /></svg>
                {{ thread.vote_score || 0 }}
              </button>
              <button
                @click="handleVoteThread(-1)"
                class="inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] border transition-colors"
                :class="thread.user_vote === -1 ? 'bg-red-50 border-red-200 text-red-600' : 'bg-slate-50 border-slate-200 text-slate-500 hover:border-slate-300'"
              >
                <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" /></svg>
              </button>
              <span class="text-[11px] text-slate-400">{{ thread.views }} views</span>
            </div>
          </div>
        </div>

        <!-- Replies -->
        <div v-if="replies.length > 0" class="space-y-0">
          <div class="text-[11px] font-medium text-slate-500 py-2">{{ replies.length }} {{ replies.length === 1 ? 'reply' : 'replies' }}</div>
          <div
            v-for="reply in replies"
            :key="reply.id"
            class="flex gap-3 py-2.5 group"
            :class="reply.is_accepted ? 'bg-emerald-50/50 -mx-3 px-3 rounded-lg border border-emerald-100' : ''"
          >
            <div
              class="w-8 h-8 rounded-lg flex items-center justify-center text-xs font-bold shrink-0"
              :class="reply.author_avatar ? '' : 'bg-slate-100 text-slate-500'"
            >
              <img v-if="reply.author_avatar" :src="reply.author_avatar" class="w-8 h-8 rounded-lg object-cover" />
              <span v-else>{{ reply.author_name?.charAt(0) || '?' }}</span>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-baseline gap-2 mb-0.5">
                <span class="text-[12px] font-bold text-slate-900">{{ reply.author_name }}</span>
                <span class="text-[10px] text-slate-400">{{ timeDisplay(reply.created_at) }}</span>
                <span v-if="reply.is_accepted" class="text-[10px] font-semibold text-emerald-700 bg-emerald-100 px-1.5 py-0.5 rounded ml-1">Accepted</span>
              </div>
              <p class="text-[13px] text-slate-700 leading-relaxed whitespace-pre-wrap">{{ reply.body }}</p>
              <div class="flex items-center gap-2 mt-1.5 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  @click="handleVoteReply(reply.id, 1)"
                  class="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded text-[10px] border transition-colors"
                  :class="reply.user_vote === 1 ? 'bg-sycamore-50 border-sycamore-200 text-sycamore-700' : 'bg-slate-50 border-slate-200 text-slate-400 hover:text-slate-600'"
                >
                  <svg class="w-2.5 h-2.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M5 15l7-7 7 7" /></svg>
                  <span v-if="(reply.vote_score || 0) !== 0">{{ reply.vote_score }}</span>
                </button>
                <button
                  v-if="isAuthor || isAdmin"
                  @click="handleAcceptReply(reply.id)"
                  class="text-[10px] px-1.5 py-0.5 rounded transition-colors"
                  :class="reply.is_accepted ? 'text-emerald-600' : 'text-slate-400 hover:text-emerald-600'"
                >{{ reply.is_accepted ? 'Accepted' : 'Accept' }}</button>
                <button
                  v-if="(user && reply.author_id === user.id) || isAdmin"
                  @click="handleDeleteReply(reply.id)"
                  class="text-[10px] text-slate-400 hover:text-red-600 px-1.5 py-0.5 rounded transition-colors"
                >Delete</button>
              </div>
            </div>
          </div>
        </div>
      </template>

      <div v-else class="flex flex-col items-center justify-center py-16">
        <p class="text-slate-500 text-sm">Thread not found.</p>
        <NuxtLink to="/forums" class="text-sycamore-600 text-sm mt-2">Back to Forums</NuxtLink>
      </div>
    </div>

    <!-- Reply Composer -->
    <div v-if="thread && !thread.is_locked" class="shrink-0 border-t border-slate-200 px-4 sm:px-5 py-3">
      <div class="flex items-end gap-2">
        <textarea
          v-model="replyBody"
          class="flex-1 px-4 py-2.5 rounded-lg border border-slate-200 text-sm text-slate-800 placeholder:text-slate-400 focus:outline-none focus:border-sycamore-400 focus:ring-2 focus:ring-sycamore-100 resize-none min-h-[40px] max-h-[120px]"
          placeholder="Reply..."
          rows="1"
          @keydown.enter.meta.exact="submitReply"
          @keydown.enter.ctrl.exact="submitReply"
        ></textarea>
        <button
          @click="submitReply"
          :disabled="submittingReply || !replyBody.trim()"
          class="p-2.5 rounded-lg transition-colors shrink-0"
          :class="replyBody.trim() ? 'bg-sycamore-600 text-white hover:bg-sycamore-700' : 'bg-slate-100 text-slate-400'"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" /></svg>
        </button>
      </div>
      <p class="text-[10px] text-slate-400 mt-1.5 hidden sm:block">Cmd+Enter to send</p>
    </div>
    <div v-else-if="thread?.is_locked" class="shrink-0 border-t border-slate-200 px-4 py-3 text-center">
      <p class="text-xs text-slate-500">This thread is locked</p>
    </div>
  </div>
</template>
