import { createClient, type SupabaseClient } from '@supabase/supabase-js'

let client: SupabaseClient | null = null

export function useSupabase(): SupabaseClient {
  if (client) return client
  const config = useRuntimeConfig()
  const url = config.public.supabaseUrl as string | undefined
  const key = config.public.supabaseAnonKey as string | undefined
  if (!url || !key) {
    throw new Error(
      'Supabase environment is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in the project .env file.'
    )
  }
  client = createClient(url, key)
  return client
}
