import { useSupabase } from '~/utils/supabase'

export interface UserProfile {
  user_id: string
  bio: string
  theme: string
  linkedin_url: string
  twitter_url: string
  github_url: string
  website_url: string
  instagram_url: string
  created_at?: string
  updated_at?: string
}

export interface ProfileTheme {
  key: string
  label: string
  gradient: string
  accent: string
}

export const PROFILE_THEMES: ProfileTheme[] = [
  { key: 'sycamore', label: 'Sycamore', gradient: 'from-sycamore-600 to-sycamore-800', accent: 'bg-sycamore-600' },
  { key: 'sunset', label: 'Sunset', gradient: 'from-orange-500 to-rose-600', accent: 'bg-orange-500' },
  { key: 'forest', label: 'Forest', gradient: 'from-emerald-600 to-teal-700', accent: 'bg-emerald-600' },
  { key: 'midnight', label: 'Midnight', gradient: 'from-slate-800 to-slate-950', accent: 'bg-slate-800' },
  { key: 'rose', label: 'Rose', gradient: 'from-rose-500 to-pink-600', accent: 'bg-rose-500' },
  { key: 'ocean', label: 'Ocean', gradient: 'from-cyan-600 to-blue-700', accent: 'bg-cyan-600' },
  { key: 'amber', label: 'Amber', gradient: 'from-amber-500 to-orange-600', accent: 'bg-amber-500' }
]

export function getThemeGradient(key: string | null | undefined): string {
  return (PROFILE_THEMES.find(t => t.key === key) ?? PROFILE_THEMES[0]).gradient
}

const EMPTY_PROFILE = (userId: string): UserProfile => ({
  user_id: userId,
  bio: '',
  theme: 'sycamore',
  linkedin_url: '',
  twitter_url: '',
  github_url: '',
  website_url: '',
  instagram_url: ''
})

export function useProfile() {
  const supabase = useSupabase()

  async function fetchProfile(userId: string): Promise<UserProfile | null> {
    const { data, error } = await supabase
      .from('user_profiles')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) throw error
    return (data as UserProfile) ?? null
  }

  async function ensureOwnProfile(userId: string): Promise<UserProfile> {
    const existing = await fetchProfile(userId)
    if (existing) return existing
    const empty = EMPTY_PROFILE(userId)
    const { data, error } = await supabase
      .from('user_profiles')
      .insert(empty)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return (data as UserProfile) ?? empty
  }

  async function saveOwnProfile(profile: UserProfile): Promise<UserProfile> {
    const payload = { ...profile, updated_at: new Date().toISOString() }
    const { data, error } = await supabase
      .from('user_profiles')
      .upsert(payload, { onConflict: 'user_id' })
      .select('*')
      .maybeSingle()
    if (error) throw error
    return (data as UserProfile) ?? profile
  }

  async function fetchStaffByAuthUser(userId: string) {
    const { data } = await supabase
      .from('staff_members')
      .select('id, full_name, email, role, phone, joined_date, department_id, location_id, auth_user_id, bio')
      .eq('auth_user_id', userId)
      .maybeSingle()
    return data
  }

  async function fetchStaffById(staffId: string) {
    const { data } = await supabase
      .from('staff_members')
      .select('id, full_name, email, role, phone, joined_date, department_id, location_id, auth_user_id, bio')
      .eq('id', staffId)
      .maybeSingle()
    return data
  }

  return { fetchProfile, ensureOwnProfile, saveOwnProfile, fetchStaffByAuthUser, fetchStaffById }
}
