import { createClient } from '@supabase/supabase-js';
import { c as useRuntimeConfig } from './server.mjs';

let client = null;
function useSupabase() {
  if (client) return client;
  const config = useRuntimeConfig();
  const url = config.public.supabaseUrl;
  const key = config.public.supabaseAnonKey;
  if (!url || !key) {
    throw new Error(
      "Supabase environment is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in the project .env file."
    );
  }
  client = createClient(url, key);
  return client;
}

export { useSupabase as u };
//# sourceMappingURL=supabase-DXLNwiqO.mjs.map
