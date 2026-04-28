<script setup lang="ts">
import {
  summarizeReactions,
  type PostKind,
  type PostMention,
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
  image_url?: string
  summary?: string
}

interface AuthorMeta {
  user_id: string
  name: string
  staff_id: string | null
  initials: string
  avatar: string | null
}

const supabase = useSupabase()
const { user, ready, isAuthenticated } = useAuth()
const { fetchPosts, createPost, deletePost, fetchReactions, toggleReaction, fetchMentionsForPosts, fetchMentionsForAnnouncements } = useFeed()
const { fetchProfilesByUserIds } = useProfile()
const toast = useToast()

const loading = ref(true)
const error = ref<string | null>(null)
const posts = ref<PostRow[]>([])
const announcements = ref<AnnouncementRow[]>([])
const reactions = ref<ReactionRow[]>([])
const authors = ref<Record<string, AuthorMeta>>({})
const mentionsByPost = ref<Record<string, PostMention[]>>({})
const mentionsByAnnouncement = ref<Record<string, PostMention[]>>({})
const composer = ref('')
const composerImage = ref('')
const composerKind = ref<PostKind>('standard')
const composerTemplateData = ref<Record<string, any>>({})
const templatePickerOpen = ref(false)
const submitting = ref(false)

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]?.toUpperCase() ?? '').join('') || '?'
}

async function loadAuthors(authorIds: string[]) {
  const ids = Array.from(new Set(authorIds)).filter(id => !authors.value[id])
  if (ids.length === 0) return
  const [{ data }, profiles] = await Promise.all([
    supabase.from('staff_members').select('id, full_name, auth_user_id').in('auth_user_id', ids),
    fetchProfilesByUserIds(ids)
  ])
  const byUid: Record<string, AuthorMeta> = { ...authors.value }
  for (const id of ids) {
    const m = (data ?? []).find((r: any) => r.auth_user_id === id)
    byUid[id] = {
      user_id: id,
      name: m?.full_name || 'Sycamore staff',
      staff_id: m?.id ?? null,
      initials: initials(m?.full_name || '?'),
      avatar: profiles[id]?.avatar_url || null
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
    const [rxs, mentions, annMentions] = await Promise.all([
      fetchReactions([
        { type: 'post', ids: posts.value.map(x => x.id) },
        { type: 'announcement', ids: announcements.value.map(x => x.id) }
      ]),
      fetchMentionsForPosts(posts.value.map(x => x.id)),
      fetchMentionsForAnnouncements(announcements.value.map(x => x.id))
    ])
    reactions.value = rxs
    mentionsByPost.value = mentions
    mentionsByAnnouncement.value = annMentions
    const reactorIds = Array.from(new Set(rxs.map(r => r.user_id)))
    const allAuthorIds = Array.from(new Set([...posts.value.map(p => p.author_id), ...reactorIds]))
    await loadAuthors(allAuthorIds)
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

function reactorsFor(targetType: ReactionTargetType, targetId: string): Record<string, string[]> {
  const map: Record<string, string[]> = {}
  const list = reactionsByTarget.value[`${targetType}:${targetId}`] ?? []
  for (const r of list) {
    const name = authors.value[r.user_id]?.name || 'Sycamore staff'
    ;(map[r.emoji] ||= []).push(name)
  }
  return map
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

function applyTemplate(payload: { kind: PostKind; data: Record<string, any>; text: string }) {
  composerKind.value = payload.kind
  composerTemplateData.value = payload.data
  composer.value = composer.value.trim() ? composer.value : payload.text
}

function clearTemplate() {
  composerKind.value = 'standard'
  composerTemplateData.value = {}
}

const activeTemplate = computed(() => {
  if (composerKind.value === 'standard') return null
  return null
})

async function submitPost() {
  if (!user.value || !composer.value.trim()) return
  submitting.value = true
  try {
    const created = await createPost(user.value.id, composer.value, {
      image_url: composerImage.value.trim() || undefined,
      post_kind: composerKind.value,
      template_data: composerTemplateData.value
    })
    posts.value = [created, ...posts.value]
    composer.value = ''
    composerImage.value = ''
    composerKind.value = 'standard'
    composerTemplateData.value = {}
    await loadAuthors([created.author_id])
    const fresh = await fetchMentionsForPosts([created.id])
    mentionsByPost.value = { ...mentionsByPost.value, ...fresh }
  } catch (e: any) {
    error.value = e.message ?? 'Could not publish post'
  } finally {
    submitting.value = false
  }
}

async function removePost(id: string) {
  const ok = await toast.confirm({ title: 'Delete post', message: 'This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    await deletePost(id)
    posts.value = posts.value.filter(p => p.id !== id)
    toast.success('Post deleted')
  } catch (e: any) {
    toast.error(e.message ?? 'Could not delete post')
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
        <MentionTextarea
          v-model="composer"
          :rows="3"
          :maxlength="4000"
          placeholder="Share something with the team... use @ to mention a colleague"
        />
        <div v-if="composerKind !== 'standard'" class="mt-3 flex items-center gap-2 text-xs">
          <span class="badge badge-green capitalize">{{ composerKind }}</span>
          <span class="text-slate-500">Template applied</span>
          <button type="button" class="ml-auto text-slate-400 hover:text-rose-600 inline-flex items-center gap-1" @click="clearTemplate">
            <SidebarIcon name="close" /> remove
          </button>
        </div>

        <div class="mt-3">
          <label class="block text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1">Image (optional)</label>
          <input v-model="composerImage" class="input" placeholder="https://... paste an image URL to attach" />
        </div>

        <div class="flex items-center justify-between gap-3 mt-3">
          <div class="flex items-center gap-2">
            <button
              type="button"
              class="btn-secondary text-xs inline-flex items-center gap-1"
              @click="templatePickerOpen = true"
            >
              <SidebarIcon name="sparkle" /> Template
            </button>
          </div>
          <div class="text-xs text-slate-400 hidden sm:block">{{ composer.length }} / 4000 &middot; type @ to mention</div>
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
      <PostTemplatePicker :open="templatePickerOpen" @close="templatePickerOpen = false" @apply="applyTemplate" />
    </ClientOnly>

    <p v-if="error" class="text-xs text-rose-600">{{ error }}</p>

    <div v-if="loading" class="text-sm text-slate-400">Loading feed...</div>

    <template v-else>
      <section v-if="announcements.length" class="space-y-4">
        <h2 class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Announcements</h2>
        <article v-for="a in announcements" :key="a.id" class="card overflow-hidden">
          <figure v-if="a.image_url" class="relative">
            <img :src="a.image_url" :alt="a.title" class="w-full h-56 sm:h-72 object-cover" />
            <div class="absolute inset-0 bg-gradient-to-t from-slate-900/70 via-slate-900/10 to-transparent" />
            <span :class="[
              'absolute top-4 left-4 badge',
              a.priority === 'high' ? 'badge-rose' : a.priority === 'medium' ? 'badge-amber' : 'badge-slate'
            ]">{{ a.priority }}</span>
            <div class="absolute bottom-4 left-4 right-4 text-white">
              <h3 class="text-xl sm:text-2xl font-bold tracking-tight drop-shadow">{{ a.title }}</h3>
              <p v-if="a.summary" class="text-sm text-white/90 mt-1 line-clamp-2">{{ a.summary }}</p>
            </div>
          </figure>
          <div class="p-5">
            <div v-if="!a.image_url" class="flex items-center gap-2 mb-2">
              <span :class="[
                'badge',
                a.priority === 'high' ? 'badge-rose' : a.priority === 'medium' ? 'badge-amber' : 'badge-slate'
              ]">{{ a.priority }}</span>
              <h3 class="font-semibold text-slate-900">{{ a.title }}</h3>
            </div>
            <p v-if="a.summary && a.image_url" class="text-sm font-medium text-slate-800 mb-2">{{ a.summary }}</p>
            <PostBody class="block text-sm text-slate-700" :content="a.content" :mentions="mentionsByAnnouncement[a.id]" />
            <div class="text-xs text-slate-400 mt-2">{{ formatTime(a.created_at) }}</div>
            <ReactionBar
              :target-type="'announcement'"
              :target-id="a.id"
              :summary="summary('announcement', a.id)"
              :reactors-by-emoji="reactorsFor('announcement', a.id)"
              :disabled="!isAuthenticated"
              @toggle="handleToggle"
            />
          </div>
        </article>
      </section>

      <section class="space-y-3">
        <h2 class="text-xs font-semibold text-slate-500 uppercase tracking-wide">Posts</h2>
        <p v-if="posts.length === 0" class="text-sm text-slate-400">No posts yet. Be the first to share something.</p>
        <PostCard
          v-for="p in posts"
          :key="p.id"
          :post="p"
          :author-name="authors[p.author_id]?.name"
          :author-avatar="authors[p.author_id]?.avatar"
          :author-staff-id="authors[p.author_id]?.staff_id"
          :author-initials="authors[p.author_id]?.initials"
          :mentions="mentionsByPost[p.id]"
          :formatted-time="formatTime(p.created_at)"
        >
          <template #actions>
            <button
              v-if="user && p.author_id === user.id"
              type="button"
              class="text-slate-400 hover:text-rose-600 text-xs inline-flex items-center gap-1"
              @click="removePost(p.id)"
            >
              <SidebarIcon name="trash" /> Delete
            </button>
          </template>
          <template #footer>
            <ReactionBar
              :target-type="'post'"
              :target-id="p.id"
              :summary="summary('post', p.id)"
              :reactors-by-emoji="reactorsFor('post', p.id)"
              :disabled="!isAuthenticated"
              @toggle="handleToggle"
            />
          </template>
        </PostCard>
      </section>
    </template>
  </div>
</template>
