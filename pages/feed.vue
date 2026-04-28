<script setup lang="ts">
import {
  summarizeReactions,
  type PostRow,
  type ReactionKey,
  type ReactionRow,
  type ReactionTargetType
} from '~/composables/useFeed'

interface AnnouncementRow {
  id: string
  title: string
  content: string
  priority: string
  is_active: boolean
  created_at: string
}

interface AuthorMeta {
  user_id: string
  name: string
  staff_id: string | null
  initials: string
}

const supabase = useSupabase()
const { user, ready, isAuthenticated } = useAuth()
const { fetchPosts, createPost, deletePost, fetchReactions, toggleReaction } = useFeed()

const loading = ref(true)
const error = ref<string | null>(null)
const posts = ref<PostRow[]>([])
const announcements = ref<AnnouncementRow[]>([])
const reactions = ref<ReactionRow[]>([])
const authors = ref<Record<string, AuthorMeta>>({})

const composer = ref('')
const submitting = ref(false)

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]?.toUpperCase() ?? '').join('') || '?'
}

async function loadAuthors(authorIds: string[]) {
  const ids = Array.from(new Set(authorIds)).filter(id => !authors.value[id])
  if (ids.length === 0) return
  const { data } = await supabase
    .from('staff_members')
    .select('id, full_name, auth_user_id')
    .in('auth_user_id', ids)
  const byUid: Record<string, AuthorMeta> = { ...authors.value }
  for (const id of ids) {
    const m = (data ?? []).find((r: any) => r.auth_user_id === id)
    if (m) {
      byUid[id] = { user_id: id, name: m.full_name, staff_id: m.id, initials: initials(m.full_name) }
    } else {
      byUid[id] = { user_id: id, name: 'Sycamore staff', staff_id: null, initials: '?' }
    }
  }
  authors.value = byUid
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const [p, a] = await Promise.all([
      fetchPosts(50),
      supabase
        .from('announcements')
        .select('*')
        .eq('is_active', true)
        .order('created_at', { ascending: false })
    ])
    posts.value = p
    announcements.value = (a.data ?? []) as AnnouncementRow[]
    const rxs = await fetchReactions([
      { type: 'post', ids: posts.value.map(x => x.id) },
      { type: 'announcement', ids: announcements.value.map(x => x.id) }
    ])
    reactions.value = rxs
    await loadAuthors(posts.value.map(p => p.author_id))
  } catch (e: any) {
    error.value = e.message ?? 'Failed to load feed'
  } finally {
    loading.value = false
  }
}

watch(ready, () => { if (ready.value) load() }, { immediate: true })

const reactionsByTarget = computed(() => {
  const map: Record<string, ReactionRow[]> = {}
  for (const r of reactions.value) {
    const k = `${r.target_type}:${r.target_id}`
    if (!map[k]) map[k] = []
    map[k].push(r)
  }
  return map
})

function summary(targetType: ReactionTargetType, targetId: string) {
  return summarizeReactions(
    reactionsByTarget.value[`${targetType}:${targetId}`] ?? [],
    user.value?.id ?? null
  )
}

async function handleToggle(payload: { targetType: ReactionTargetType; targetId: string; emoji: ReactionKey; on: boolean }) {
  if (!user.value) return
  const uid = user.value.id
  const idx = reactions.value.findIndex(
    r => r.target_type === payload.targetType && r.target_id === payload.targetId && r.user_id === uid && r.emoji === payload.emoji
  )
  if (payload.on && idx >= 0) {
    reactions.value.splice(idx, 1)
  } else if (!payload.on && idx === -1) {
    reactions.value.push({
      id: `temp-${Date.now()}`,
      target_type: payload.targetType,
      target_id: payload.targetId,
      user_id: uid,
      emoji: payload.emoji,
      created_at: new Date().toISOString()
    })
  }
  try {
    await toggleReaction(payload.targetType, payload.targetId, uid, payload.emoji, payload.on)
  } catch (e: any) {
    error.value = e.message ?? 'Could not update reaction'
    await load()
  }
}

async function submitPost() {
  if (!user.value || !composer.value.trim()) return
  submitting.value = true
  try {
    const created = await createPost(user.value.id, composer.value)
    posts.value = [created, ...posts.value]
    composer.value = ''
    await loadAuthors([created.author_id])
  } catch (e: any) {
    error.value = e.message ?? 'Could not publish post'
  } finally {
    submitting.value = false
  }
}

async function removePost(id: string) {
  if (!confirm('Delete this post? This cannot be undone.')) return
  try {
    await deletePost(id)
    posts.value = posts.value.filter(p => p.id !== id)
  } catch (e: any) {
    error.value = e.message ?? 'Could not delete post'
  }
}

function formatTime(iso: string) {
  const d = new Date(iso)
  return d.toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })
}

definePageMeta({ title: 'Feed' })
</script>

<template>
  <div class="max-w-3xl mx-auto space-y-6">
    <header>
      <h1 class="section-title">Company Feed</h1>
      <p class="section-subtitle">Announcements from the company and posts from your colleagues.</p>
    </header>

    <ClientOnly>
      <div v-if="isAuthenticated" class="card p-5">
        <textarea
          v-model="composer"
          rows="3"
          maxlength="4000"
          class="input"
          placeholder="Share something with the team..."
        />
        <div class="flex items-center justify-between mt-3">
          <div class="text-xs text-slate-400">{{ composer.length }} / 4000</div>
          <button
            type="button"
            class="btn-primary"
            :disabled="submitting || !composer.trim()"
            @click="submitPost"
          >
            {{ submitting ? 'Posting...' : 'Post' }}
          </button>
        </div>
      </div>
      <div v-else class="card p-5 text-center text-sm text-slate-500">
        <NuxtLink to="/login" class="text-sycamore-700 font-medium hover:underline">Sign in</NuxtLink>
        to post and react.
      </div>
    </ClientOnly>

    <p v-if="error" class="text-xs text-rose-600">{{ error }}</p>

    <div v-if="loading" class="text-sm text-slate-400">Loading feed...</div>

    <template v-else>
      <section v-if="announcements.length" class="space-y-3">
        <h2 class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Announcements</h2>
        <article v-for="a in announcements" :key="a.id" class="card p-5">
          <div class="flex items-start gap-3">
            <span :class="[
              'badge mt-1',
              a.priority === 'high' ? 'badge-rose' : a.priority === 'medium' ? 'badge-amber' : 'badge-slate'
            ]">{{ a.priority }}</span>
            <div class="min-w-0 flex-1">
              <h3 class="font-semibold text-slate-900">{{ a.title }}</h3>
              <p class="text-sm text-slate-700 whitespace-pre-line mt-1">{{ a.content }}</p>
              <div class="text-xs text-slate-400 mt-2">{{ formatTime(a.created_at) }}</div>
              <ReactionBar
                :target-type="'announcement'"
                :target-id="a.id"
                :summary="summary('announcement', a.id)"
                :disabled="!isAuthenticated"
                @toggle="handleToggle"
              />
            </div>
          </div>
        </article>
      </section>

      <section class="space-y-3">
        <h2 class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Posts</h2>
        <p v-if="posts.length === 0" class="text-sm text-slate-400">No posts yet. Be the first to share something.</p>
        <article v-for="p in posts" :key="p.id" class="card p-5">
          <div class="flex items-start gap-3">
            <div class="w-10 h-10 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-sm font-semibold flex-shrink-0">
              {{ authors[p.author_id]?.initials || '?' }}
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <NuxtLink
                    v-if="authors[p.author_id]?.staff_id"
                    :to="`/profile/${authors[p.author_id]?.staff_id}`"
                    class="font-semibold text-slate-900 text-sm hover:text-sycamore-700 truncate"
                  >
                    {{ authors[p.author_id]?.name }}
                  </NuxtLink>
                  <span v-else class="font-semibold text-slate-900 text-sm truncate">
                    {{ authors[p.author_id]?.name || 'Sycamore staff' }}
                  </span>
                  <div class="text-xs text-slate-400">{{ formatTime(p.created_at) }}</div>
                </div>
                <button
                  v-if="user && p.author_id === user.id"
                  type="button"
                  class="text-slate-400 hover:text-rose-600 text-xs inline-flex items-center gap-1"
                  @click="removePost(p.id)"
                >
                  <SidebarIcon name="trash" /> Delete
                </button>
              </div>
              <p class="text-sm text-slate-700 whitespace-pre-line mt-2">{{ p.content }}</p>
              <ReactionBar
                :target-type="'post'"
                :target-id="p.id"
                :summary="summary('post', p.id)"
                :disabled="!isAuthenticated"
                @toggle="handleToggle"
              />
            </div>
          </div>
        </article>
      </section>
    </template>
  </div>
</template>
