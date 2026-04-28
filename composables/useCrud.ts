import { useSupabase } from '~/utils/supabase'

export function useCrud(table: string) {
  const supabase = useSupabase()
  const items = ref<any[]>([])
  const loading = ref(false)
  const error = ref<string | null>(null)

  async function load(orderBy: { column: string, ascending?: boolean }[] = [{ column: 'created_at', ascending: false }]) {
    loading.value = true
    error.value = null
    try {
      let q: any = supabase.from(table).select('*')
      for (const o of orderBy) q = q.order(o.column, { ascending: o.ascending ?? true })
      const { data, error: e } = await q
      if (e) throw e
      items.value = data ?? []
    } catch (e: any) {
      error.value = e.message ?? 'Failed to load'
    } finally {
      loading.value = false
    }
  }

  async function create(payload: Record<string, any>) {
    const { data, error: e } = await supabase.from(table).insert(payload).select().maybeSingle()
    if (e) throw e
    if (data) items.value.unshift(data)
    return data
  }

  async function update(id: string, payload: Record<string, any>) {
    const { data, error: e } = await supabase.from(table).update(payload).eq('id', id).select().maybeSingle()
    if (e) throw e
    if (data) {
      const idx = items.value.findIndex((i: any) => i.id === id)
      if (idx >= 0) items.value[idx] = data
    }
    return data
  }

  async function remove(id: string) {
    const { error: e } = await supabase.from(table).delete().eq('id', id)
    if (e) throw e
    items.value = items.value.filter((i: any) => i.id !== id)
  }

  return { items, loading, error, load, create, update, remove }
}
