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

export interface PostRow {
  id: string
  author_id: string
  content: string
  is_published: boolean
  created_at: string
  updated_at: string
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

  async function createPost(authorId: string, content: string): Promise<PostRow> {
    const trimmed = content.trim()
    if (!trimmed) throw new Error('Post is empty')
    if (trimmed.length > 4000) throw new Error('Post is too long (max 4000 characters)')
    const { data, error } = await supabase
      .from('posts')
      .insert({ author_id: authorId, content: trimmed, is_published: true })
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

  return { fetchPosts, createPost, deletePost, fetchReactions, toggleReaction, fetchMentionsForPosts }
}
