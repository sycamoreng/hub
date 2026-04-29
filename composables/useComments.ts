import { useSupabase } from '~/utils/supabase'

export interface CommentRow {
  id: string
  target_type: 'post' | 'announcement'
  target_id: string
  user_id: string
  parent_id: string | null
  content: string
  is_edited: boolean
  created_at: string
  updated_at: string
}

export function useComments() {
  const supabase = useSupabase()

  async function fetchCountsForTargets(targets: { type: 'post' | 'announcement'; ids: string[] }[]) {
    const counts: Record<string, number> = {}
    for (const t of targets) {
      if (t.ids.length === 0) continue
      const { data, error } = await supabase
        .from('comments')
        .select('target_id')
        .eq('target_type', t.type)
        .in('target_id', t.ids)
      if (error) throw error
      for (const row of data ?? []) {
        const k = `${t.type}:${row.target_id}`
        counts[k] = (counts[k] ?? 0) + 1
      }
    }
    return counts
  }

  async function fetchComments(targetType: 'post' | 'announcement', targetId: string): Promise<CommentRow[]> {
    const { data, error } = await supabase
      .from('comments')
      .select('*')
      .eq('target_type', targetType)
      .eq('target_id', targetId)
      .order('created_at', { ascending: true })
    if (error) throw error
    return (data ?? []) as CommentRow[]
  }

  async function fetchMentionsForComments(commentIds: string[]): Promise<Record<string, { user_id: string; staff_id: string | null; full_name: string }[]>> {
    if (commentIds.length === 0) return {}
    const { data, error } = await supabase
      .from('comment_mentions')
      .select('comment_id, user_id, staff_id, staff_members(full_name)')
      .in('comment_id', commentIds)
    if (error) throw error
    const map: Record<string, { user_id: string; staff_id: string | null; full_name: string }[]> = {}
    for (const row of (data ?? []) as any[]) {
      const m = { user_id: row.user_id, staff_id: row.staff_id, full_name: row.staff_members?.full_name ?? '' }
      if (!m.full_name) continue
      ;(map[row.comment_id] ||= []).push(m)
    }
    return map
  }

  async function addComment(args: {
    targetType: 'post' | 'announcement'
    targetId: string
    userId: string
    content: string
    parentId?: string | null
  }): Promise<CommentRow> {
    const content = args.content.trim()
    if (!content) throw new Error('Comment is empty')
    if (content.length > 2000) throw new Error('Comment is too long (max 2000 characters)')
    const { data, error } = await supabase
      .from('comments')
      .insert({
        target_type: args.targetType,
        target_id: args.targetId,
        user_id: args.userId,
        content,
        parent_id: args.parentId ?? null
      })
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as CommentRow
  }

  async function updateComment(id: string, content: string): Promise<CommentRow> {
    const trimmed = content.trim()
    if (!trimmed) throw new Error('Comment is empty')
    const { data, error } = await supabase
      .from('comments')
      .update({ content: trimmed })
      .eq('id', id)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as CommentRow
  }

  async function deleteComment(id: string): Promise<void> {
    const { error } = await supabase.from('comments').delete().eq('id', id)
    if (error) throw error
  }

  return { fetchCountsForTargets, fetchComments, fetchMentionsForComments, addComment, updateComment, deleteComment }
}
