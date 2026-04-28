import { useSupabase } from '~/utils/supabase'

export interface MentionSuggestion {
  id: string
  full_name: string
  auth_user_id: string | null
}

export function useMentions() {
  const supabase = useSupabase()
  const suggestions = useState<MentionSuggestion[]>('mentions.suggestions', () => [])
  const loaded = useState<boolean>('mentions.loaded', () => false)

  async function loadSuggestions(force = false) {
    if (loaded.value && !force) return suggestions.value
    const { data } = await supabase
      .from('staff_members')
      .select('id, full_name, auth_user_id')
      .eq('is_active', true)
      .not('auth_user_id', 'is', null)
      .order('full_name')
    suggestions.value = (data ?? []) as MentionSuggestion[]
    loaded.value = true
    return suggestions.value
  }

  return { suggestions, loadSuggestions }
}
