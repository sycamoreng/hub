import { useSupabase } from '~/utils/supabase'

export interface ForumCategory {
  id: string
  name: string
  description: string
  slug: string
  icon: string
  color: string
  sort_order: number
  is_active: boolean
  thread_count?: number
  latest_thread?: { title: string; created_at: string; author_name: string } | null
}

export interface ForumThread {
  id: string
  category_id: string
  author_id: string
  title: string
  body: string
  is_pinned: boolean
  is_locked: boolean
  is_resolved: boolean
  views: number
  last_reply_at: string
  reply_count: number
  created_at: string
  updated_at: string
  author_name?: string
  author_avatar?: string | null
  vote_score?: number
  user_vote?: number
  category_name?: string
  category_icon?: string
}

export interface ForumReply {
  id: string
  thread_id: string
  author_id: string
  body: string
  is_accepted: boolean
  parent_reply_id: string | null
  created_at: string
  updated_at: string
  author_name?: string
  author_avatar?: string | null
  vote_score?: number
  user_vote?: number
}

export function useForums() {
  const supabase = useSupabase()

  async function fetchCategories(): Promise<ForumCategory[]> {
    const { data } = await supabase
      .from('forum_categories')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
    if (!data) return []

    const { data: threads } = await supabase
      .from('forum_threads')
      .select('id, category_id, title, created_at, author_id')
      .order('created_at', { ascending: false })

    const countByCategory = new Map<string, number>()
    const latestByCategory = new Map<string, any>()
    for (const t of threads ?? []) {
      countByCategory.set(t.category_id, (countByCategory.get(t.category_id) || 0) + 1)
      if (!latestByCategory.has(t.category_id)) {
        latestByCategory.set(t.category_id, t)
      }
    }

    const authorIds = [...new Set((threads ?? []).map(t => t.author_id))]
    const { data: profiles } = authorIds.length > 0
      ? await supabase.from('user_profiles').select('user_id, display_name').in('user_id', authorIds)
      : { data: [] }
    const nameMap = new Map<string, string>()
    for (const p of profiles ?? []) nameMap.set(p.user_id, p.display_name)

    return data.map(cat => ({
      ...cat,
      thread_count: countByCategory.get(cat.id) || 0,
      latest_thread: latestByCategory.has(cat.id)
        ? {
            title: latestByCategory.get(cat.id).title,
            created_at: latestByCategory.get(cat.id).created_at,
            author_name: nameMap.get(latestByCategory.get(cat.id).author_id) || 'Team Member'
          }
        : null
    }))
  }

  async function fetchThreads(categorySlug?: string, search?: string): Promise<ForumThread[]> {
    let query = supabase
      .from('forum_threads')
      .select('*')
      .order('is_pinned', { ascending: false })
      .order('last_reply_at', { ascending: false })
      .limit(50)

    if (categorySlug) {
      const { data: cat } = await supabase
        .from('forum_categories')
        .select('id')
        .eq('slug', categorySlug)
        .maybeSingle()
      if (cat) query = query.eq('category_id', cat.id)
    }

    if (search) {
      query = query.ilike('title', `%${search}%`)
    }

    const { data: threads } = await query
    if (!threads || threads.length === 0) return []

    const authorIds = [...new Set(threads.map(t => t.author_id))]
    const threadIds = threads.map(t => t.id)

    const [profilesRes, votesRes, categoriesRes] = await Promise.all([
      supabase.from('user_profiles').select('user_id, display_name, avatar_url').in('user_id', authorIds),
      supabase.from('forum_thread_votes').select('thread_id, user_id, vote').in('thread_id', threadIds),
      supabase.from('forum_categories').select('id, name, icon')
    ])

    const nameMap = new Map<string, { name: string; avatar: string | null }>()
    for (const p of profilesRes.data ?? []) nameMap.set(p.user_id, { name: p.display_name, avatar: p.avatar_url })

    const catMap = new Map<string, { name: string; icon: string }>()
    for (const c of categoriesRes.data ?? []) catMap.set(c.id, { name: c.name, icon: c.icon })

    const votesByThread = new Map<string, { score: number; userVote: number }>()
    const { user } = useAuth()
    for (const v of votesRes.data ?? []) {
      const current = votesByThread.get(v.thread_id) || { score: 0, userVote: 0 }
      current.score += v.vote
      if (user.value && v.user_id === user.value.id) current.userVote = v.vote
      votesByThread.set(v.thread_id, current)
    }

    return threads.map(t => {
      const profile = nameMap.get(t.author_id)
      const cat = catMap.get(t.category_id)
      const votes = votesByThread.get(t.id)
      return {
        ...t,
        author_name: profile?.name || 'Team Member',
        author_avatar: profile?.avatar || null,
        vote_score: votes?.score || 0,
        user_vote: votes?.userVote || 0,
        category_name: cat?.name || '',
        category_icon: cat?.icon || ''
      }
    })
  }

  async function fetchThread(threadId: string): Promise<ForumThread | null> {
    const { data } = await supabase
      .from('forum_threads')
      .select('*')
      .eq('id', threadId)
      .maybeSingle()
    if (!data) return null

    // Increment views
    await supabase
      .from('forum_threads')
      .update({ views: (data.views || 0) + 1 })
      .eq('id', threadId)

    const { data: profile } = await supabase
      .from('user_profiles')
      .select('display_name, avatar_url')
      .eq('user_id', data.author_id)
      .maybeSingle()

    const { data: votes } = await supabase
      .from('forum_thread_votes')
      .select('user_id, vote')
      .eq('thread_id', threadId)

    const { user } = useAuth()
    let score = 0
    let userVote = 0
    for (const v of votes ?? []) {
      score += v.vote
      if (user.value && v.user_id === user.value.id) userVote = v.vote
    }

    const { data: cat } = await supabase
      .from('forum_categories')
      .select('name, icon')
      .eq('id', data.category_id)
      .maybeSingle()

    return {
      ...data,
      author_name: profile?.display_name || 'Team Member',
      author_avatar: profile?.avatar_url || null,
      vote_score: score,
      user_vote: userVote,
      category_name: cat?.name || '',
      category_icon: cat?.icon || ''
    }
  }

  async function fetchReplies(threadId: string): Promise<ForumReply[]> {
    const { data } = await supabase
      .from('forum_replies')
      .select('*')
      .eq('thread_id', threadId)
      .order('is_accepted', { ascending: false })
      .order('created_at')

    if (!data || data.length === 0) return []

    const authorIds = [...new Set(data.map(r => r.author_id))]
    const replyIds = data.map(r => r.id)

    const [profilesRes, votesRes] = await Promise.all([
      supabase.from('user_profiles').select('user_id, display_name, avatar_url').in('user_id', authorIds),
      supabase.from('forum_reply_votes').select('reply_id, user_id, vote').in('reply_id', replyIds)
    ])

    const nameMap = new Map<string, { name: string; avatar: string | null }>()
    for (const p of profilesRes.data ?? []) nameMap.set(p.user_id, { name: p.display_name, avatar: p.avatar_url })

    const { user } = useAuth()
    const votesByReply = new Map<string, { score: number; userVote: number }>()
    for (const v of votesRes.data ?? []) {
      const current = votesByReply.get(v.reply_id) || { score: 0, userVote: 0 }
      current.score += v.vote
      if (user.value && v.user_id === user.value.id) current.userVote = v.vote
      votesByReply.set(v.reply_id, current)
    }

    return data.map(r => {
      const profile = nameMap.get(r.author_id)
      const votes = votesByReply.get(r.id)
      return {
        ...r,
        author_name: profile?.name || 'Team Member',
        author_avatar: profile?.avatar || null,
        vote_score: votes?.score || 0,
        user_vote: votes?.userVote || 0
      }
    })
  }

  async function createThread(categoryId: string, title: string, body: string) {
    const { user } = useAuth()
    if (!user.value) throw new Error('Not authenticated')
    const { data, error } = await supabase
      .from('forum_threads')
      .insert({ category_id: categoryId, author_id: user.value.id, title, body })
      .select('id')
      .maybeSingle()
    if (error) throw error
    return data
  }

  async function createReply(threadId: string, body: string, parentReplyId?: string) {
    const { user } = useAuth()
    if (!user.value) throw new Error('Not authenticated')
    const { data, error } = await supabase
      .from('forum_replies')
      .insert({
        thread_id: threadId,
        author_id: user.value.id,
        body,
        parent_reply_id: parentReplyId || null
      })
      .select('id')
      .maybeSingle()
    if (error) throw error
    return data
  }

  async function voteThread(threadId: string, vote: 1 | -1) {
    const { user } = useAuth()
    if (!user.value) return
    const { data: existing } = await supabase
      .from('forum_thread_votes')
      .select('id, vote')
      .eq('thread_id', threadId)
      .eq('user_id', user.value.id)
      .maybeSingle()

    if (existing) {
      if (existing.vote === vote) {
        await supabase.from('forum_thread_votes').delete().eq('id', existing.id)
      } else {
        await supabase.from('forum_thread_votes').update({ vote }).eq('id', existing.id)
      }
    } else {
      await supabase.from('forum_thread_votes').insert({ thread_id: threadId, user_id: user.value.id, vote })
    }
  }

  async function voteReply(replyId: string, vote: 1 | -1) {
    const { user } = useAuth()
    if (!user.value) return
    const { data: existing } = await supabase
      .from('forum_reply_votes')
      .select('id, vote')
      .eq('reply_id', replyId)
      .eq('user_id', user.value.id)
      .maybeSingle()

    if (existing) {
      if (existing.vote === vote) {
        await supabase.from('forum_reply_votes').delete().eq('id', existing.id)
      } else {
        await supabase.from('forum_reply_votes').update({ vote }).eq('id', existing.id)
      }
    } else {
      await supabase.from('forum_reply_votes').insert({ reply_id: replyId, user_id: user.value.id, vote })
    }
  }

  async function toggleResolved(threadId: string, resolved: boolean) {
    await supabase.from('forum_threads').update({ is_resolved: resolved, updated_at: new Date().toISOString() }).eq('id', threadId)
  }

  async function acceptReply(replyId: string, accepted: boolean) {
    await supabase.from('forum_replies').update({ is_accepted: accepted, updated_at: new Date().toISOString() }).eq('id', replyId)
  }

  async function deleteThread(threadId: string) {
    await supabase.from('forum_threads').delete().eq('id', threadId)
  }

  async function deleteReply(replyId: string) {
    await supabase.from('forum_replies').delete().eq('id', replyId)
  }

  async function fetchMyChannels(): Promise<string[]> {
    const { user } = useAuth()
    if (!user.value) return []
    const { data } = await supabase
      .from('forum_channel_members')
      .select('category_id')
      .eq('user_id', user.value.id)
    return (data ?? []).map(r => r.category_id)
  }

  async function joinChannel(categoryId: string) {
    const { user } = useAuth()
    if (!user.value) return
    await supabase
      .from('forum_channel_members')
      .upsert({ category_id: categoryId, user_id: user.value.id }, { onConflict: 'category_id,user_id' })
  }

  async function leaveChannel(categoryId: string) {
    const { user } = useAuth()
    if (!user.value) return
    await supabase
      .from('forum_channel_members')
      .delete()
      .eq('category_id', categoryId)
      .eq('user_id', user.value.id)
  }

  return {
    fetchCategories,
    fetchThreads,
    fetchThread,
    fetchReplies,
    fetchMyChannels,
    joinChannel,
    leaveChannel,
    createThread,
    createReply,
    voteThread,
    voteReply,
    toggleResolved,
    acceptReply,
    deleteThread,
    deleteReply
  }
}
