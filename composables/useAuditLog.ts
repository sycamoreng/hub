import { useSupabase } from '~/utils/supabase'

interface AuditEntry {
  action: string
  target_type: string
  target_id?: string
  target_label?: string
  details?: Record<string, unknown>
}

export function useAuditLog() {
  const supabase = useSupabase()
  const { profile } = useAuth()

  async function log(entry: AuditEntry) {
    const email = profile.value?.email
    if (!email) return
    try {
      await supabase.from('admin_audit_log').insert({
        admin_email: email.toLowerCase(),
        action: entry.action,
        target_type: entry.target_type,
        target_id: entry.target_id ?? null,
        target_label: entry.target_label ?? null,
        details: entry.details ?? null,
      })
      await supabase
        .from('admin_users')
        .update({ last_active_at: new Date().toISOString() })
        .eq('email', email.toLowerCase())
    } catch {
      // non-fatal
    }
  }

  async function touchActive() {
    const email = profile.value?.email
    if (!email) return
    try {
      await supabase
        .from('admin_users')
        .update({ last_active_at: new Date().toISOString() })
        .eq('email', email.toLowerCase())
    } catch {
      // non-fatal
    }
  }

  return { log, touchActive }
}
