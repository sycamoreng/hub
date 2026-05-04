import { useSupabase } from '~/utils/supabase'

export interface ExitUnit {
  code: string
  name: string
  icon: string
  sort_order: number
  hod_user_id: string | null
  is_active: boolean
}

export interface ExitCase {
  id: string
  staff_id: string
  exit_type: 'resignation' | 'termination'
  reason: string
  effective_date: string | null
  last_working_day: string | null
  status: 'initiated' | 'in_progress' | 'completed' | 'cancelled'
  initiated_by_user_id: string | null
  initiated_by_kind: 'self' | 'admin'
  notes: string
  created_at: string
  updated_at: string
  completed_at: string | null
}

export interface ExitChecklistItem {
  id: string
  case_id: string
  unit_code: string
  title: string
  detail: string
  assignee_user_id: string | null
  status: 'pending' | 'done' | 'not_applicable'
  notes: string
  sort_order: number
  completed_at: string | null
  completed_by: string | null
}

// staff_members has two FKs to departments (staff_members.department_id and departments.head_staff_id),
// so embeds must disambiguate with the explicit FK name. Centralise here so the same bug can't reappear
// in multiple call sites.
const STAFF_EMBED =
  'staff:staff_members(id, full_name, email, role, auth_user_id, department:departments!staff_members_department_id_fkey(name))'

export function useExit() {
  const supabase = useSupabase()

  async function loadUnits(): Promise<ExitUnit[]> {
    const { data } = await supabase
      .from('exit_units')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
    return (data as ExitUnit[]) ?? []
  }

  async function loadCases(opts: { mine?: boolean; staffId?: string | null } = {}) {
    let q = supabase
      .from('exit_cases')
      .select(`*, ${STAFF_EMBED}`)
      .order('created_at', { ascending: false })
    if (opts.staffId) q = q.eq('staff_id', opts.staffId)
    const { data } = await q
    return data ?? []
  }

  async function loadCase(id: string) {
    const { data } = await supabase
      .from('exit_cases')
      .select(`*, ${STAFF_EMBED}`)
      .eq('id', id)
      .maybeSingle()
    return data
  }

  async function loadItems(caseId: string): Promise<ExitChecklistItem[]> {
    const { data } = await supabase
      .from('exit_checklist_items')
      .select('*')
      .eq('case_id', caseId)
      .order('unit_code')
      .order('sort_order')
    return (data as ExitChecklistItem[]) ?? []
  }

  async function createCase(payload: Partial<ExitCase>): Promise<ExitCase | null> {
    const { data, error } = await supabase
      .from('exit_cases')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as ExitCase | null
  }

  async function updateCase(id: string, payload: Partial<ExitCase>) {
    const { error } = await supabase.from('exit_cases').update(payload).eq('id', id)
    if (error) throw error
  }

  async function updateItem(id: string, payload: Partial<ExitChecklistItem>) {
    const { error } = await supabase.from('exit_checklist_items').update(payload).eq('id', id)
    if (error) throw error
  }

  async function notifyHods(exitCase: ExitCase, staffName: string) {
    const units = await loadUnits()
    const actorId = exitCase.initiated_by_user_id
    const label = exitCase.exit_type === 'resignation' ? 'Resignation' : 'Termination'
    const body = `${label} initiated for ${staffName}. Please review and action your checklist.`
    const inserts = units
      .filter(u => !!u.hod_user_id)
      .map(u => ({
        recipient_id: u.hod_user_id!,
        actor_id: actorId,
        type: 'exit_initiated',
        title: `${label}: ${staffName}`,
        body: `${u.name}: ${body}`,
        link: `/admin/exits?case=${exitCase.id}`
      }))
    if (inserts.length) {
      try {
        await supabase.from('notifications').insert(inserts)
      } catch {
        // non-fatal
      }
    }

    // Fire-and-forget email notifications via edge function.
    try {
      const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/email/notify_exit_initiated`
      await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ case_id: exitCase.id })
      })
    } catch {
      // non-fatal
    }
  }

  return {
    loadUnits,
    loadCases,
    loadCase,
    loadItems,
    createCase,
    updateCase,
    updateItem,
    notifyHods
  }
}
