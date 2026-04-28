import { useSupabase } from '~/utils/supabase'

export type ReactionKey = string
export type ReactionTargetType = 'announcement' | 'post'

export interface ReactionRow {
  id: string
  target_type: ReactionTargetType
  target_id: string
  user_id: string
  emoji: ReactionKey
  created_at: string
}

export type PostKind = 'standard' | 'birthday' | 'anniversary' | 'mood' | 'milestone' | 'kudos' | 'welcome' | 'congrats'

export interface PostRow {
  id: string
  author_id: string
  content: string
  is_published: boolean
  created_at: string
  updated_at: string
  image_url?: string
  post_kind?: PostKind
  template_data?: Record<string, any>
}

export interface PostTemplateMeta {
  kind: PostKind
  label: string
  emoji: string
  promptTitle: string
  fieldHint?: string
  defaultText: (data: Record<string, any>) => string
  badge: string
  accent: string
  fields?: { key: string; label: string; placeholder?: string; type?: 'text' | 'number' | 'date' }[]
}

export const POST_TEMPLATES: PostTemplateMeta[] = [
  {
    kind: 'birthday',
    label: 'Birthday',
    emoji: '\u{1F382}',
    promptTitle: 'Celebrate a birthday',
    badge: 'Birthday',
    accent: 'from-rose-500 to-amber-500',
    fields: [{ key: 'name', label: 'Whose birthday?', placeholder: 'e.g. Tomi (or yourself)' }],
    defaultText: d => `It\u2019s ${d.name || 'someone\u2019s'} birthday today! Wishing you an amazing year ahead. \u{1F382}\u{1F389}`
  },
  {
    kind: 'anniversary',
    label: 'Work anniversary',
    emoji: '\u{1F38A}',
    promptTitle: 'Celebrate a work anniversary',
    badge: 'Anniversary',
    accent: 'from-sycamore-500 to-leaf-600',
    fields: [
      { key: 'name', label: 'Who?', placeholder: 'e.g. Tomi' },
      { key: 'years', label: 'Years at Sycamore', type: 'number', placeholder: '5' }
    ],
    defaultText: d => `Today marks ${d.years || 'an awesome'} year${(Number(d.years) === 1 ? '' : 's')} of ${d.name || 'someone'} at Sycamore. Thank you for everything!`
  },
  {
    kind: 'mood',
    label: 'Mood / vibe',
    emoji: '\u{1F60A}',
    promptTitle: 'Share how you\u2019re feeling',
    badge: 'Mood',
    accent: 'from-amber-400 to-rose-400',
    fields: [{ key: 'mood', label: 'Mood emoji', placeholder: 'e.g. \u{1F60A} excited' }],
    defaultText: d => `${d.mood || 'Feeling great'} \u2014 ${'.'}`
  },
  {
    kind: 'milestone',
    label: 'Milestone',
    emoji: '\u{1F3C6}',
    promptTitle: 'Share a milestone',
    badge: 'Milestone',
    accent: 'from-leaf-500 to-sycamore-700',
    defaultText: () => `Just hit a big milestone \u{1F3C6}`
  },
  {
    kind: 'kudos',
    label: 'Kudos',
    emoji: '\u{1F44F}',
    promptTitle: 'Give a shout-out',
    badge: 'Kudos',
    accent: 'from-sycamore-400 to-amber-400',
    fields: [{ key: 'name', label: 'To whom?', placeholder: '@colleague' }],
    defaultText: d => `Massive shout-out to ${d.name || 'someone special'} \u2014 thank you for going above and beyond.`
  },
  {
    kind: 'welcome',
    label: 'Welcome',
    emoji: '\u{1F44B}',
    promptTitle: 'Welcome a new hire',
    badge: 'Welcome',
    accent: 'from-sycamore-500 to-leaf-500',
    fields: [
      { key: 'name', label: 'Who joined?', placeholder: 'e.g. Tomi' },
      { key: 'role', label: 'Role', placeholder: 'e.g. Senior Engineer' }
    ],
    defaultText: d => `Please join me in welcoming ${d.name || 'our newest teammate'}${d.role ? ` as our new ${d.role}` : ''} to Sycamore! \u{1F44B}`
  },
  {
    kind: 'congrats',
    label: 'Congrats',
    emoji: '\u{1F389}',
    promptTitle: 'Send congratulations',
    badge: 'Congrats',
    accent: 'from-rose-500 to-sycamore-600',
    fields: [{ key: 'name', label: 'Who?', placeholder: 'e.g. Tomi' }],
    defaultText: d => `Huge congrats to ${d.name || 'you'}! Well-deserved \u{1F389}`
  }
]

export function findTemplate(kind?: string | null): PostTemplateMeta | null {
  if (!kind || kind === 'standard') return null
  return POST_TEMPLATES.find(t => t.kind === kind) ?? null
}

export interface PostMention {
  post_id: string
  user_id: string
  staff_id: string | null
  full_name: string
}

export interface ReactionSummary {
  counts: Record<string, number>
  mine: Set<string>
  order: string[]
}

export interface EmojiGroup {
  label: string
  emojis: string[]
}

export const EMOJI_GROUPS: EmojiGroup[] = [
  {
    label: 'Smileys',
    emojis: ['\u{1F600}', '\u{1F604}', '\u{1F602}', '\u{1F923}', '\u{1F60A}', '\u{1F60D}', '\u{1F970}', '\u{1F60E}', '\u{1F929}', '\u{1F607}', '\u{1F914}', '\u{1F605}', '\u{1F62E}', '\u{1F92F}', '\u{1F62D}', '\u{1F634}']
  },
  {
    label: 'Hearts',
    emojis: ['\u2764\uFE0F', '\u{1F9E1}', '\u{1F49B}', '\u{1F49A}', '\u{1F499}', '\u{1F90D}', '\u{1F496}', '\u{1F495}', '\u{1F494}']
  },
  {
    label: 'Hands',
    emojis: ['\u{1F44D}', '\u{1F44E}', '\u{1F44F}', '\u{1F64C}', '\u{1F64F}', '\u{1F4AA}', '\u{1F91D}', '\u270B', '\u{1F44C}', '\u{1F91E}', '\u{1F918}', '\u{1F44B}']
  },
  {
    label: 'Celebrate',
    emojis: ['\u{1F389}', '\u{1F38A}', '\u{1F973}', '\u{1F37E}', '\u{1F942}', '\u{1F381}', '\u{1F382}', '\u{1F38A}']
  },
  {
    label: 'Work',
    emojis: ['\u{1F525}', '\u2B50', '\u2728', '\u{1F4AF}', '\u2705', '\u274C', '\u26A1', '\u{1F4A1}', '\u{1F680}', '\u{1F3C6}', '\u{1F4C8}', '\u{1F4C9}', '\u{1F6E0}\uFE0F', '\u{1F916}', '\u{1F4B0}', '\u{1F4BC}', '\u{1F441}\uFE0F']
  }
]

export const QUICK_EMOJIS: string[] = [
  '\u{1F44D}', '\u2764\uFE0F', '\u{1F389}', '\u{1F525}', '\u{1F4A1}', '\u{1F44F}', '\u{1F602}', '\u{1F680}'
]

export function summarizeReactions(rows: ReactionRow[], myUserId: string | null): ReactionSummary {
  const counts: Record<string, number> = {}
  const mine = new Set<string>()
  const order: string[] = []
  for (const r of rows) {
    if (counts[r.emoji] === undefined) {
      counts[r.emoji] = 0
      order.push(r.emoji)
    }
    counts[r.emoji] += 1
    if (myUserId && r.user_id === myUserId) mine.add(r.emoji)
  }
  order.sort((a, b) => counts[b] - counts[a])
  return { counts, mine, order }
}

export function useFeed() {
  const supabase = useSupabase()

  async function fetchPosts(limit = 50): Promise<PostRow[]> {
    const { data, error } = await supabase
      .from('posts')
      .select('*')
      .eq('is_published', true)
      .order('created_at', { ascending: false })
      .limit(limit)
    if (error) throw error
    return (data ?? []) as PostRow[]
  }

  async function createPost(
    authorId: string,
    content: string,
    options?: { image_url?: string; post_kind?: PostKind; template_data?: Record<string, any> }
  ): Promise<PostRow> {
    const trimmed = content.trim()
    if (!trimmed) throw new Error('Post is empty')
    if (trimmed.length > 4000) throw new Error('Post is too long (max 4000 characters)')
    const insert: any = { author_id: authorId, content: trimmed, is_published: true }
    if (options?.image_url) insert.image_url = options.image_url
    if (options?.post_kind && options.post_kind !== 'standard') insert.post_kind = options.post_kind
    if (options?.template_data) insert.template_data = options.template_data
    const { data, error } = await supabase
      .from('posts')
      .insert(insert)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PostRow
  }

  async function deletePost(postId: string) {
    const { error } = await supabase.from('posts').delete().eq('id', postId)
    if (error) throw error
  }

  async function fetchReactions(targets: { type: ReactionTargetType; ids: string[] }[]): Promise<ReactionRow[]> {
    const queries = targets
      .filter(t => t.ids.length > 0)
      .map(t =>
        supabase
          .from('reactions')
          .select('*')
          .eq('target_type', t.type)
          .in('target_id', t.ids)
      )
    if (queries.length === 0) return []
    const results = await Promise.all(queries)
    const rows: ReactionRow[] = []
    for (const r of results) {
      if (r.error) throw r.error
      rows.push(...((r.data ?? []) as ReactionRow[]))
    }
    return rows
  }

  async function toggleReaction(
    targetType: ReactionTargetType,
    targetId: string,
    userId: string,
    emoji: ReactionKey,
    currentlyOn: boolean
  ): Promise<void> {
    if (currentlyOn) {
      const { error } = await supabase
        .from('reactions')
        .delete()
        .eq('target_type', targetType)
        .eq('target_id', targetId)
        .eq('user_id', userId)
        .eq('emoji', emoji)
      if (error) throw error
    } else {
      const { error } = await supabase
        .from('reactions')
        .insert({ target_type: targetType, target_id: targetId, user_id: userId, emoji })
      if (error && !`${error.message}`.toLowerCase().includes('duplicate')) throw error
    }
  }

  async function fetchMentionsForPosts(postIds: string[]): Promise<Record<string, PostMention[]>> {
    if (postIds.length === 0) return {}
    const { data, error } = await supabase
      .from('post_mentions')
      .select('post_id, user_id, staff_id, staff_members(full_name)')
      .in('post_id', postIds)
    if (error) throw error
    const map: Record<string, PostMention[]> = {}
    for (const row of (data ?? []) as any[]) {
      const m: PostMention = {
        post_id: row.post_id,
        user_id: row.user_id,
        staff_id: row.staff_id,
        full_name: row.staff_members?.full_name ?? ''
      }
      if (!m.full_name) continue
      ;(map[m.post_id] ||= []).push(m)
    }
    return map
  }

  async function fetchMentionsForAnnouncements(ids: string[]): Promise<Record<string, PostMention[]>> {
    if (ids.length === 0) return {}
    const { data, error } = await supabase
      .from('announcement_mentions')
      .select('announcement_id, user_id, staff_id, staff_members(full_name)')
      .in('announcement_id', ids)
    if (error) throw error
    const map: Record<string, PostMention[]> = {}
    for (const row of (data ?? []) as any[]) {
      const m: PostMention = {
        post_id: row.announcement_id,
        user_id: row.user_id,
        staff_id: row.staff_id,
        full_name: row.staff_members?.full_name ?? ''
      }
      if (!m.full_name) continue
      ;(map[row.announcement_id] ||= []).push(m)
    }
    return map
  }

  return { fetchPosts, createPost, deletePost, fetchReactions, toggleReaction, fetchMentionsForPosts, fetchMentionsForAnnouncements }
}
