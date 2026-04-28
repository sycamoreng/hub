import type { RealtimeChannel } from '@supabase/supabase-js'
import { useSupabase } from '~/utils/supabase'

export type NotificationType = 'post_new' | 'announcement_new' | 'reaction_received'

export interface NotificationRow {
  id: string
  recipient_id: string
  actor_id: string | null
  type: NotificationType
  title: string
  body: string
  link: string
  read_at: string | null
  created_at: string
}

export function useNotifications() {
  const supabase = useSupabase()
  const items = useState<NotificationRow[]>('notifications.items', () => [])
  const loaded = useState<boolean>('notifications.loaded', () => false)
  const loading = useState<boolean>('notifications.loading', () => false)
  const channel = useState<RealtimeChannel | null>('notifications.channel', () => null)

  const unreadCount = computed(() => items.value.filter(n => !n.read_at).length)

  async function load(userId: string, limit = 30) {
    if (loading.value) return
    loading.value = true
    try {
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('recipient_id', userId)
        .order('created_at', { ascending: false })
        .limit(limit)
      if (error) throw error
      items.value = (data ?? []) as NotificationRow[]
      loaded.value = true
    } finally {
      loading.value = false
    }
  }

  function subscribe(userId: string) {
    if (channel.value) return
    const ch = supabase
      .channel(`notifications:${userId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `recipient_id=eq.${userId}` },
        payload => {
          const row = payload.new as NotificationRow
          if (!items.value.some(n => n.id === row.id)) {
            items.value = [row, ...items.value].slice(0, 50)
          }
        }
      )
      .subscribe()
    channel.value = ch
  }

  async function unsubscribe() {
    if (channel.value) {
      await supabase.removeChannel(channel.value)
      channel.value = null
    }
  }

  async function markRead(id: string) {
    const target = items.value.find(n => n.id === id)
    if (!target || target.read_at) return
    const now = new Date().toISOString()
    items.value = items.value.map(n => (n.id === id ? { ...n, read_at: now } : n))
    const { error } = await supabase.from('notifications').update({ read_at: now }).eq('id', id)
    if (error) {
      items.value = items.value.map(n => (n.id === id ? { ...n, read_at: null } : n))
    }
  }

  async function markAllRead(userId: string) {
    const ids = items.value.filter(n => !n.read_at).map(n => n.id)
    if (ids.length === 0) return
    const now = new Date().toISOString()
    items.value = items.value.map(n => (n.read_at ? n : { ...n, read_at: now }))
    const { error } = await supabase
      .from('notifications')
      .update({ read_at: now })
      .eq('recipient_id', userId)
      .is('read_at', null)
    if (error) await load(userId)
  }

  async function dismiss(id: string) {
    const prev = items.value
    items.value = items.value.filter(n => n.id !== id)
    const { error } = await supabase.from('notifications').delete().eq('id', id)
    if (error) items.value = prev
  }

  return {
    items: readonly(items),
    unreadCount,
    loaded: readonly(loaded),
    loading: readonly(loading),
    load,
    subscribe,
    unsubscribe,
    markRead,
    markAllRead,
    dismiss
  }
}
