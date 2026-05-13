import { useSupabase } from '~/utils/supabase'

export interface ShortcutDef {
  key: string
  label: string
  description: string
  icon: string
  to: string
  accent: string
}

export const SHORTCUT_CATALOG: ShortcutDef[] = [
  { key: 'appointments', label: 'Appointments',  description: 'Book a visitor',        icon: 'calendar',    to: '/appointments', accent: 'from-sycamore-500 to-sycamore-700' },
  { key: 'finance',      label: 'Advance & Loans', description: 'Finance requests',     icon: 'card',        to: '/finance',      accent: 'from-emerald-500 to-teal-600' },
  { key: 'leave',        label: 'Leave',          description: 'Book time off',         icon: 'calendar',    to: '/leave',        accent: 'from-amber-500 to-orange-500' },
  { key: 'attendance',   label: 'Clock in',       description: 'Start your shift',      icon: 'clock',       to: '/attendance',   accent: 'from-sky-500 to-blue-600' },
  { key: 'payroll',      label: 'My Payroll',     description: 'Payslips & summary',    icon: 'card',        to: '/payroll',      accent: 'from-rose-500 to-pink-600' },
  { key: 'tools',        label: 'Tools',          description: 'Company apps',          icon: 'gift',        to: '/tools',        accent: 'from-slate-600 to-slate-800' },
  { key: 'recognition',  label: 'Recognition',    description: 'Give kudos',            icon: 'star',        to: '/recognition',  accent: 'from-yellow-500 to-amber-600' },
  { key: 'performance',  label: 'Performance',    description: 'Reviews & goals',       icon: 'check',       to: '/performance',  accent: 'from-leaf-500 to-leaf-700' },
  { key: 'onboarding',   label: 'Learning',       description: 'Training & onboarding', icon: 'check',       to: '/onboarding',   accent: 'from-teal-500 to-cyan-600' },
  { key: 'feed',         label: 'Feed',           description: 'Team updates',          icon: 'chat',        to: '/feed',         accent: 'from-sycamore-600 to-leaf-600' },
  { key: 'staff',        label: 'Staff',          description: 'Directory',             icon: 'users',       to: '/staff',        accent: 'from-slate-500 to-slate-700' },
  { key: 'calendar',     label: 'Calendar',       description: 'Company events',        icon: 'calendar',    to: '/calendar',     accent: 'from-blue-500 to-indigo-500' },
  { key: 'contacts',     label: 'Contacts',       description: 'Key numbers',           icon: 'phone',       to: '/contacts',     accent: 'from-fuchsia-500 to-pink-600' },
  { key: 'policies',     label: 'Policies',       description: 'How we work',           icon: 'book',        to: '/policies',     accent: 'from-slate-600 to-zinc-700' },
  { key: 'benefits',     label: 'Benefits',       description: 'Perks & wellbeing',     icon: 'gift',        to: '/benefits',     accent: 'from-rose-400 to-rose-600' },
  { key: 'wordle',       label: 'Wordle',         description: 'Play for points',       icon: 'sparkle',     to: '/wordle',       accent: 'from-emerald-500 to-teal-600' }
]

export const DEFAULT_SHORTCUTS = ['appointments', 'finance', 'leave', 'attendance', 'payroll', 'tools']

export function getShortcutDef(key: string): ShortcutDef | undefined {
  return SHORTCUT_CATALOG.find(s => s.key === key)
}

export function useShortcuts() {
  const supabase = useSupabase()

  async function loadPins(userId: string): Promise<string[]> {
    const { data } = await supabase
      .from('user_shortcut_pins')
      .select('pins')
      .eq('user_id', userId)
      .maybeSingle()
    const row = data as { pins: string[] } | null
    if (!row) return [...DEFAULT_SHORTCUTS]
    return (row.pins ?? []).filter(k => SHORTCUT_CATALOG.some(s => s.key === k))
  }

  async function savePins(userId: string, pins: string[]): Promise<void> {
    const clean = pins.filter(k => SHORTCUT_CATALOG.some(s => s.key === k))
    const { error } = await supabase
      .from('user_shortcut_pins')
      .upsert({ user_id: userId, pins: clean, updated_at: new Date().toISOString() }, { onConflict: 'user_id' })
    if (error) throw error
  }

  return { loadPins, savePins }
}
