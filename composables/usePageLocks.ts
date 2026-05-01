import { useSupabase } from '~/utils/supabase'

export interface PageLock {
  path: string
  locked: boolean
  updated_at?: string
}

export function usePageLocks() {
  const supabase = useSupabase()
  const locks = useState<Record<string, boolean>>('page.locks', () => ({}))
  const loaded = useState<boolean>('page.locks.loaded', () => false)

  async function load(force = false) {
    if (loaded.value && !force) return
    const { data } = await supabase.from('page_locks').select('path, locked')
    const next: Record<string, boolean> = {}
    for (const row of (data as PageLock[] | null) ?? []) {
      next[row.path] = Boolean(row.locked)
    }
    locks.value = next
    loaded.value = true
  }

  async function setLock(path: string, locked: boolean) {
    const { error } = await supabase
      .from('page_locks')
      .upsert({ path, locked, updated_at: new Date().toISOString() }, { onConflict: 'path' })
    if (error) throw error
    locks.value = { ...locks.value, [path]: locked }
  }

  function isLocked(path: string): boolean {
    return Boolean(locks.value[path])
  }

  return { locks, loaded, load, setLock, isLocked }
}
