import type { User } from '@supabase/supabase-js'
import { useSupabase } from '~/utils/supabase'

export type AdminRole = 'super_admin' | 'admin'

export type CrudAction = 'create' | 'read' | 'update' | 'delete'
export type SectionPermissions = Record<CrudAction, boolean>

export interface AdminRecord {
  email: string
  role: AdminRole
  display_name: string
  title: string
  function: string
  sections: string[]
  permissions: Record<string, Partial<SectionPermissions>>
}

export const ALLOWED_EMAIL_DOMAINS = ['sycamore.ng', 'sycamoreglobal.co.uk']

export function isEmailAllowed(email?: string | null): boolean {
  if (!email) return false
  const domain = email.toLowerCase().split('@')[1]
  return ALLOWED_EMAIL_DOMAINS.includes(domain)
}

export function useAuth() {
  const supabase = useSupabase()
  const user = useState<User | null>('auth.user', () => null)
  const adminRecord = useState<AdminRecord | null>('auth.adminRecord', () => null)
  const ready = useState<boolean>('auth.ready', () => false)
  const profileSyncTick = useState<number>('auth.profileSyncTick', () => 0)
  const domainError = useState<string | null>('auth.domainError', () => null)

  async function loadAdminRecord(email: string | undefined) {
    if (!email) {
      adminRecord.value = null
      return
    }
    const { data } = await supabase
      .from('admin_users')
      .select('email, role, display_name, title, function, sections, permissions')
      .eq('email', email.toLowerCase())
      .maybeSingle()
    if (data) {
      adminRecord.value = {
        ...(data as any),
        permissions: ((data as any).permissions ?? {}) as Record<string, Partial<SectionPermissions>>
      }
    } else {
      adminRecord.value = null
    }
  }

  async function enforceAllowedDomain(currentUser: User | null): Promise<boolean> {
    if (!currentUser) return true
    if (isEmailAllowed(currentUser.email)) return true
    const blocked = currentUser.email || 'this account'
    await supabase.auth.signOut()
    user.value = null
    adminRecord.value = null
    domainError.value = `Sign-in restricted: ${blocked} is not on an allowed Sycamore domain. Please use a @${ALLOWED_EMAIL_DOMAINS[0]} or @${ALLOWED_EMAIL_DOMAINS[1]} account.`
    return false
  }

  async function claimStaff() {
    try {
      await supabase.rpc('claim_staff_member')
    } catch {
      /* non-fatal: staff record may not exist yet */
    } finally {
      profileSyncTick.value++
    }
  }

  async function syncAvatar(currentUser: User | null) {
    if (!currentUser) return
    const meta: any = currentUser.user_metadata ?? {}
    const avatar = (meta.avatar_url || meta.picture || '').trim()
    if (!avatar) return
    try {
      const { fetchProfile } = useProfile()
      const existing = await fetchProfile(currentUser.id)
      if (existing && existing.avatar_url === avatar) return
      const next = {
        user_id: currentUser.id,
        bio: existing?.bio ?? '',
        theme: existing?.theme ?? 'sycamore',
        avatar_url: avatar,
        linkedin_url: existing?.linkedin_url ?? '',
        twitter_url: existing?.twitter_url ?? '',
        github_url: existing?.github_url ?? '',
        website_url: existing?.website_url ?? '',
        instagram_url: existing?.instagram_url ?? '',
        updated_at: new Date().toISOString()
      }
      await supabase.from('user_profiles').upsert(next, { onConflict: 'user_id' })
    } catch {
      /* non-fatal */
    } finally {
      profileSyncTick.value++
    }
  }

  async function init() {
    if (ready.value) return
    const { data } = await supabase.auth.getSession()
    user.value = data.session?.user ?? null
    const ok = await enforceAllowedDomain(user.value)
    if (ok) {
      await loadAdminRecord(user.value?.email)
      if (user.value) {
        await claimStaff()
        await syncAvatar(user.value)
      }
    }
    supabase.auth.onAuthStateChange((_event, session) => {
      user.value = session?.user ?? null
      ;(async () => {
        const allowed = await enforceAllowedDomain(user.value)
        if (allowed) {
          domainError.value = null
          await loadAdminRecord(user.value?.email)
          if (user.value) {
            await claimStaff()
            await syncAvatar(user.value)
          }
        }
      })()
    })
    ready.value = true
  }

  async function signInWithGoogle(redirectPath = '/') {
    const redirectTo = typeof window !== 'undefined'
      ? `${window.location.origin}/login?redirect=${encodeURIComponent(redirectPath)}`
      : undefined
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo }
    })
    if (error) throw error
  }

  async function signOut() {
    await supabase.auth.signOut()
    user.value = null
    adminRecord.value = null
  }

  const profile = computed(() => {
    const u = user.value
    if (!u) return null
    const meta: any = u.user_metadata ?? {}
    const name = meta.full_name || meta.name || [meta.given_name, meta.family_name].filter(Boolean).join(' ') || u.email || ''
    const email = u.email || meta.email || ''
    const avatarUrl = meta.avatar_url || meta.picture || ''
    const initials = (name || email)
      .split(/[\s@]+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((s: string) => s[0]?.toUpperCase() ?? '')
      .join('') || '?'
    return { name, email, avatarUrl, initials }
  })

  const isSuperAdmin = computed(() => adminRecord.value?.role === 'super_admin')
  const isAdmin = computed(() => adminRecord.value !== null)

  function canPerform(section: string, action: CrudAction) {
    const rec = adminRecord.value
    if (!rec) return false
    if (rec.role === 'super_admin') return true
    return Boolean(rec.permissions?.[section]?.[action])
  }

  function canManageSection(section: string) {
    return canPerform(section, 'read')
  }

  return {
    user: readonly(user),
    ready: readonly(ready),
    profileSyncTick: readonly(profileSyncTick),
    profile,
    adminRecord: readonly(adminRecord),
    isAuthenticated: computed(() => user.value !== null),
    isAdmin,
    isSuperAdmin,
    canManageSection,
    canPerform,
    init,
    signInWithGoogle,
    signOut,
    domainError: readonly(domainError),
    clearDomainError: () => { domainError.value = null },
    refreshAdmin: () => loadAdminRecord(user.value?.email)
  }
}
