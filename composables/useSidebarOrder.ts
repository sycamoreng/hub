import { useSupabase } from '~/utils/supabase'

export const SIDEBAR_GROUP_IDS = ['company', 'productivity', 'work', 'people', 'comms'] as const
export type SidebarGroupId = typeof SIDEBAR_GROUP_IDS[number]

export function useSidebarOrder() {
  const supabase = useSupabase()
  const order = useState<string[]>('sidebar.order', () => [...SIDEBAR_GROUP_IDS])
  const loaded = useState<boolean>('sidebar.order.loaded', () => false)

  async function load(force = false) {
    if (loaded.value && !force) return
    const { data } = await supabase
      .from('sidebar_order')
      .select('groups')
      .eq('id', 1)
      .maybeSingle()
    const stored = (data as any)?.groups
    if (Array.isArray(stored) && stored.length) {
      const merged: string[] = []
      const seen = new Set<string>()
      for (const id of stored) {
        if (typeof id === 'string' && (SIDEBAR_GROUP_IDS as readonly string[]).includes(id) && !seen.has(id)) {
          merged.push(id)
          seen.add(id)
        }
      }
      for (const id of SIDEBAR_GROUP_IDS) {
        if (!seen.has(id)) merged.push(id)
      }
      order.value = merged
    }
    loaded.value = true
  }

  async function save(next: string[]) {
    const { error } = await supabase
      .from('sidebar_order')
      .upsert(
        { id: 1, groups: next, updated_at: new Date().toISOString() },
        { onConflict: 'id' }
      )
    if (error) throw error
    order.value = next
  }

  return { order, loaded, load, save }
}
