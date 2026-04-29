<script setup lang="ts">
import type { CommentRow } from '~/composables/useComments'
import type { PostMention } from '~/composables/useFeed'

interface AuthorMeta {
  user_id: string
  name: string
  staff_id: string | null
  initials: string
  avatar: string | null
}

const props = defineProps<{
  targetType: 'post' | 'announcement'
  targetId: string
  initialCount?: number
  currentUserId?: string | null
  isAdmin?: boolean
}>()

const { fetchComments, fetchMentionsForComments, addComment, updateComment, deleteComment } = useComments()
const { fetchProfilesByUserIds } = useProfile()
const supabase = useSupabase()
const toast = useToast()

const expanded = ref(false)
const loading = ref(false)
const loaded = ref(false)
const comments = ref<CommentRow[]>([])
const authors = ref<Record<string, AuthorMeta>>({})
const mentionsByComment = ref<Record<string, PostMention[]>>({})

function mentionsFor(commentId: string): PostMention[] {
  const list = mentionsByComment.value[commentId] ?? []
  return list.map(m => ({ post_id: commentId, user_id: m.user_id, staff_id: m.staff_id, full_name: m.full_name }))
}
const draft = ref('')
const submitting = ref(false)
const editingId = ref<string | null>(null)
const editingText = ref('')
const count = ref(props.initialCount ?? 0)

function fmtTime(iso: string) {
  const d = new Date(iso)
  const diffMs = Date.now() - d.getTime()
  const mins = Math.floor(diffMs / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
}

function initials(name: string) {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(s => s[0]?.toUpperCase() ?? '').join('') || '?'
}

async function loadAuthorsFor(userIds: string[]) {
  const ids = Array.from(new Set(userIds)).filter(id => !authors.value[id])
  if (ids.length === 0) return
  const [{ data }, profiles] = await Promise.all([
    supabase.from('staff_members').select('id, full_name, auth_user_id').in('auth_user_id', ids),
    fetchProfilesByUserIds(ids)
  ])
  const next: Record<string, AuthorMeta> = { ...authors.value }
  for (const id of ids) {
    const m = (data ?? []).find((r: any) => r.auth_user_id === id)
    next[id] = {
      user_id: id,
      name: m?.full_name || 'Sycamore staff',
      staff_id: m?.id ?? null,
      initials: initials(m?.full_name || '?'),
      avatar: profiles[id]?.avatar_url || null
    }
  }
  authors.value = next
}

async function ensureLoaded() {
  if (loaded.value) return
  loading.value = true
  try {
    const rows = await fetchComments(props.targetType, props.targetId)
    comments.value = rows
    count.value = rows.length
    const [mentions] = await Promise.all([
      fetchMentionsForComments(rows.map(r => r.id)),
      loadAuthorsFor(rows.map(r => r.user_id))
    ])
    mentionsByComment.value = mentions
    loaded.value = true
  } catch (e: any) {
    toast.error(e.message ?? 'Could not load comments')
  } finally {
    loading.value = false
  }
}

async function toggle() {
  expanded.value = !expanded.value
  if (expanded.value) await ensureLoaded()
}

async function submit() {
  if (!props.currentUserId) { toast.error('Sign in to comment'); return }
  if (!draft.value.trim()) return
  submitting.value = true
  try {
    const created = await addComment({
      targetType: props.targetType,
      targetId: props.targetId,
      userId: props.currentUserId,
      content: draft.value
    })
    comments.value = [...comments.value, created]
    count.value = comments.value.length
    draft.value = ''
    await loadAuthorsFor([created.user_id])
    const fresh = await fetchMentionsForComments([created.id])
    mentionsByComment.value = { ...mentionsByComment.value, ...fresh }
  } catch (e: any) {
    toast.error(e.message ?? 'Could not post comment')
  } finally {
    submitting.value = false
  }
}

function startEdit(c: CommentRow) {
  editingId.value = c.id
  editingText.value = c.content
}

function cancelEdit() {
  editingId.value = null
  editingText.value = ''
}

async function saveEdit() {
  if (!editingId.value) return
  try {
    const updated = await updateComment(editingId.value, editingText.value)
    comments.value = comments.value.map(c => c.id === updated.id ? updated : c)
    const fresh = await fetchMentionsForComments([updated.id])
    mentionsByComment.value = { ...mentionsByComment.value, ...fresh }
    cancelEdit()
  } catch (e: any) {
    toast.error(e.message ?? 'Could not update comment')
  }
}

async function remove(c: CommentRow) {
  const ok = await toast.confirm({ title: 'Delete comment', message: 'This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    await deleteComment(c.id)
    comments.value = comments.value.filter(x => x.id !== c.id)
    count.value = comments.value.length
  } catch (e: any) {
    toast.error(e.message ?? 'Could not delete comment')
  }
}

function canModify(c: CommentRow) {
  return props.currentUserId === c.user_id || !!props.isAdmin
}

function canDelete(c: CommentRow) {
  return canModify(c)
}

watch(() => props.initialCount, v => { if (typeof v === 'number' && !loaded.value) count.value = v })
</script>

<template>
  <div class="mt-3 pt-3 border-t border-slate-100">
    <button
      type="button"
      class="inline-flex items-center gap-1.5 text-xs font-medium text-slate-500 hover:text-slate-900"
      @click="toggle"
    >
      <SidebarIcon name="chat" />
      <span v-if="count === 0">Add a comment</span>
      <span v-else>{{ count }} {{ count === 1 ? 'comment' : 'comments' }}</span>
      <span class="text-slate-300">·</span>
      <span>{{ expanded ? 'hide' : 'show' }}</span>
    </button>

    <div v-if="expanded" class="mt-3 space-y-4">
      <div v-if="loading" class="text-xs text-slate-400">Loading comments...</div>

      <template v-else>
        <ul v-if="comments.length" class="space-y-3">
          <li v-for="c in comments" :key="c.id" class="flex gap-3">
            <NuxtLink
              v-if="authors[c.user_id]?.staff_id"
              :to="`/profile/${authors[c.user_id]?.staff_id}`"
              class="flex-shrink-0"
            >
              <img
                v-if="authors[c.user_id]?.avatar"
                :src="authors[c.user_id]?.avatar || ''"
                :alt="authors[c.user_id]?.name"
                class="w-8 h-8 rounded-full object-cover border border-slate-200"
              />
              <div v-else class="w-8 h-8 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-[11px] font-semibold">
                {{ authors[c.user_id]?.initials || '?' }}
              </div>
            </NuxtLink>
            <div v-else class="flex-shrink-0 w-8 h-8 rounded-full bg-slate-100 text-slate-500 flex items-center justify-center text-[11px] font-semibold">
              {{ authors[c.user_id]?.initials || '?' }}
            </div>
            <div class="flex-1 min-w-0">
              <div class="bg-slate-50 border border-slate-100 rounded-xl px-3.5 py-2.5">
                <div class="flex items-center gap-2 mb-0.5">
                  <NuxtLink
                    v-if="authors[c.user_id]?.staff_id"
                    :to="`/profile/${authors[c.user_id]?.staff_id}`"
                    class="text-sm font-semibold text-slate-900 hover:underline"
                  >
                    {{ authors[c.user_id]?.name || 'Sycamore staff' }}
                  </NuxtLink>
                  <span v-else class="text-sm font-semibold text-slate-900">{{ authors[c.user_id]?.name || 'Sycamore staff' }}</span>
                  <span class="text-[11px] text-slate-400">{{ fmtTime(c.created_at) }}</span>
                  <span v-if="c.is_edited" class="text-[11px] text-slate-400">· edited</span>
                </div>
                <div v-if="editingId === c.id" class="mt-1.5 space-y-2">
                  <MentionTextarea v-model="editingText" :rows="2" :maxlength="2000" placeholder="Edit comment..." />
                  <div class="flex items-center gap-2 justify-end">
                    <button class="btn-ghost text-xs" @click="cancelEdit">Cancel</button>
                    <button class="btn-primary text-xs" :disabled="!editingText.trim()" @click="saveEdit">Save</button>
                  </div>
                </div>
                <PostBody v-else class="block text-sm text-slate-700 leading-relaxed" :content="c.content" :mentions="mentionsFor(c.id)" />
              </div>
              <div v-if="editingId !== c.id && (canModify(c) || canDelete(c))" class="mt-1 flex items-center gap-3 text-[11px] text-slate-400">
                <button v-if="canModify(c)" class="hover:text-slate-900" @click="startEdit(c)">Edit</button>
                <button v-if="canDelete(c)" class="hover:text-rose-600" @click="remove(c)">Delete</button>
              </div>
            </div>
          </li>
        </ul>
        <p v-else class="text-xs text-slate-400">Be the first to comment.</p>

        <div v-if="currentUserId" class="pt-2 border-t border-slate-100">
          <MentionTextarea v-model="draft" :rows="2" :maxlength="2000" placeholder="Write a comment... use @ to mention" />
          <div class="flex justify-between items-center mt-2">
            <span class="text-[11px] text-slate-400">{{ draft.length }} / 2000</span>
            <button class="btn-primary text-xs" :disabled="submitting || !draft.trim()" @click="submit">
              {{ submitting ? 'Posting...' : 'Comment' }}
            </button>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
