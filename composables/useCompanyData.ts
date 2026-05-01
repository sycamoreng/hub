import { useSupabase } from '~/utils/supabase'

export function useCompanyData() {
  const supabase = useSupabase()

  async function fetchCompanyInfo() {
    const { data, error } = await supabase
      .from('company_info')
      .select('*')
      .order('display_order', { ascending: true })
    if (error) throw error
    return data ?? []
  }

  async function fetchDepartments() {
    const { data, error } = await supabase
      .from('departments')
      .select('*, staff_members(count)')
      .order('name')
    if (error) throw error
    return (data ?? []).map((d: any) => ({
      ...d,
      staff_count: d.staff_members?.[0]?.count ?? 0
    }))
  }

  async function fetchLocations() {
    const { data, error } = await supabase
      .from('locations')
      .select('*, staff_members(count)')
      .order('is_headquarters', { ascending: false })
      .order('name')
    if (error) throw error
    return (data ?? []).map((l: any) => ({
      ...l,
      staff_count: l.staff_members?.[0]?.count ?? 0
    }))
  }

  async function fetchStaff() {
    const { data, error } = await supabase
      .from('staff_members')
      .select('*, departments(name), locations(name, city)')
      .eq('is_active', true)
      .order('full_name')
    if (error) throw error
    return data ?? []
  }

  async function fetchPolicies() {
    const { data, error } = await supabase
      .from('policies')
      .select('*')
      .eq('is_active', true)
      .order('category')
      .order('title')
    if (error) throw error
    return data ?? []
  }

  async function fetchCommunicationTools() {
    const { data, error } = await supabase
      .from('communication_tools')
      .select('*')
      .order('is_primary', { ascending: false })
      .order('name')
    if (error) throw error
    return data ?? []
  }

  async function fetchBrandingGuidelines() {
    const { data, error } = await supabase
      .from('branding_guidelines')
      .select('*')
      .order('display_order')
    if (error) throw error
    return data ?? []
  }

  async function fetchBenefits() {
    const { data, error } = await supabase
      .from('benefits_perks')
      .select('*')
      .order('display_order')
      .order('title')
    if (error) throw error
    return data ?? []
  }

  async function fetchKeyContacts() {
    const { data, error } = await supabase
      .from('key_contacts')
      .select('*')
      .order('is_emergency', { ascending: false })
      .order('name')
    if (error) throw error
    return data ?? []
  }

  async function fetchAnnouncements() {
    const { data, error } = await supabase
      .from('announcements')
      .select('*')
      .eq('is_active', true)
      .order('created_at', { ascending: false })
    if (error) throw error
    return data ?? []
  }

  async function fetchOnboardingSteps(opts?: { assignedOnly?: boolean }) {
    const { data, error } = await supabase
      .from('onboarding_steps')
      .select('*, onboarding_resources(*)')
      .eq('is_active', true)
      .order('display_order', { ascending: true })
      .order('title', { ascending: true })
    if (error) throw error
    const steps = (data ?? []).map((s: any) => ({
      ...s,
      onboarding_resources: (s.onboarding_resources ?? [])
        .slice()
        .sort((a: any, b: any) => (a.display_order ?? 0) - (b.display_order ?? 0))
    }))

    if (!opts?.assignedOnly) return steps

    const { data: assigned, error: assignedErr } = await supabase.rpc('user_assigned_step_ids')
    if (assignedErr) throw assignedErr
    const dueMap: Record<string, string | null> = {}
    for (const row of (assigned ?? []) as { step_id: string; due_date: string | null }[]) {
      dueMap[row.step_id] = row.due_date ?? null
    }
    return steps
      .filter(s => s.id in dueMap)
      .map(s => ({ ...s, due_date: dueMap[s.id] ?? null }))
  }

  async function fetchProducts() {
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .eq('is_active', true)
      .order('display_order', { ascending: true })
      .order('name', { ascending: true })
    if (error) throw error
    return data ?? []
  }

  async function fetchTechStack() {
    const { data, error } = await supabase
      .from('tech_stack')
      .select('*')
      .eq('is_active', true)
      .order('category', { ascending: true })
      .order('display_order', { ascending: true })
      .order('name', { ascending: true })
    if (error) throw error
    return data ?? []
  }

  async function fetchLeadership() {
    const { data, error } = await supabase
      .from('leadership')
      .select('*')
      .eq('is_active', true)
      .order('display_order', { ascending: true })
      .order('full_name', { ascending: true })
    if (error) throw error
    return data ?? []
  }

  async function fetchHolidaysEvents() {
    const { data, error } = await supabase
      .from('holidays_events')
      .select('*')
      .order('event_date')
    if (error) throw error
    return data ?? []
  }

  return {
    fetchCompanyInfo,
    fetchDepartments,
    fetchLocations,
    fetchStaff,
    fetchPolicies,
    fetchCommunicationTools,
    fetchBrandingGuidelines,
    fetchBenefits,
    fetchKeyContacts,
    fetchAnnouncements,
    fetchHolidaysEvents,
    fetchLeadership,
    fetchOnboardingSteps,
    fetchProducts,
    fetchTechStack
  }
}
