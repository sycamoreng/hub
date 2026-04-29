<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()

const settings = ref<any>(null)
const loading = ref(true)
const saving = ref(false)
const testTo = ref('')
const testing = ref(false)
const running = ref(false)

const queueStats = ref({ pending: 0, sent: 0, failed: 0 })
const recentLogs = ref<any[]>([])

async function load() {
  loading.value = true
  try {
    const [{ data: s }, logs, counts] = await Promise.all([
      supabase.from('email_settings').select('*').order('created_at', { ascending: true }).limit(1).maybeSingle(),
      supabase.from('email_log').select('*').order('created_at', { ascending: false }).limit(20),
      supabase.from('email_queue').select('status')
    ])
    settings.value = s ?? {
      from_name: 'Sycamore Info Hub',
      from_email: 'hub@sycamore.ng',
      reply_to: '',
      brand_color: '#0f6e42',
      default_enabled: true,
      footer_html: '',
      app_base_url: '',
      function_base_url: '',
      service_token: ''
    }
    recentLogs.value = logs.data ?? []
    const rows = counts.data ?? []
    queueStats.value = {
      pending: rows.filter((r: any) => r.status === 'pending' || r.status === 'sending').length,
      sent: rows.filter((r: any) => r.status === 'sent').length,
      failed: rows.filter((r: any) => r.status === 'failed').length
    }
  } finally {
    loading.value = false
  }
}

await load()

async function save() {
  saving.value = true
  try {
    const payload = {
      from_name: settings.value.from_name,
      from_email: settings.value.from_email,
      reply_to: settings.value.reply_to ?? '',
      brand_color: settings.value.brand_color || '#0f6e42',
      default_enabled: !!settings.value.default_enabled,
      footer_html: settings.value.footer_html ?? '',
      app_base_url: settings.value.app_base_url ?? '',
      function_base_url: settings.value.function_base_url ?? '',
      service_token: settings.value.service_token ?? '',
      updated_at: new Date().toISOString()
    }
    if (settings.value.id) {
      await supabase.from('email_settings').update(payload).eq('id', settings.value.id)
    } else {
      const { data } = await supabase.from('email_settings').insert(payload).select().maybeSingle()
      settings.value = data
    }
    toast.success('Saved')
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally {
    saving.value = false
  }
}

async function callFn(path: string, body?: any) {
  const { data: session } = await supabase.auth.getSession()
  const res = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/email/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${session.session?.access_token ?? ''}`,
      'Content-Type': 'application/json'
    },
    body: body ? JSON.stringify(body) : undefined
  })
  const json = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(json.error || `Request failed (${res.status})`)
  return json
}

async function sendTest() {
  if (!testTo.value) { toast.error('Enter a recipient email first'); return }
  testing.value = true
  try {
    await callFn('test_send', { to: testTo.value })
    toast.success('Test email sent')
    await load()
  } catch (e: any) {
    toast.error(e.message)
  } finally {
    testing.value = false
  }
}

async function runQueue() {
  running.value = true
  try {
    const out = await callFn('run_queue')
    toast.success(`Processed ${out.processed ?? 0}: ${out.sent ?? 0} sent, ${out.failed ?? 0} failed.`)
    await load()
  } catch (e: any) {
    toast.error(e.message)
  } finally {
    running.value = false
  }
}
</script>

<template>
  <div class="max-w-4xl space-y-6">
    <header>
      <h1 class="text-2xl font-bold text-slate-900">Email notifications</h1>
      <p class="text-sm text-slate-500 mt-1">Configure how the Hub sends email and send a test. You also control per-announcement emails from the announcement editor.</p>
    </header>

    <div class="grid sm:grid-cols-3 gap-3">
      <div class="card p-4">
        <div class="text-xs font-medium text-slate-500 uppercase">Pending</div>
        <div class="text-2xl font-bold text-slate-900 mt-1">{{ queueStats.pending }}</div>
      </div>
      <div class="card p-4">
        <div class="text-xs font-medium text-slate-500 uppercase">Sent</div>
        <div class="text-2xl font-bold text-sycamore-700 mt-1">{{ queueStats.sent }}</div>
      </div>
      <div class="card p-4">
        <div class="text-xs font-medium text-slate-500 uppercase">Failed</div>
        <div class="text-2xl font-bold text-rose-600 mt-1">{{ queueStats.failed }}</div>
      </div>
    </div>

    <div v-if="loading" class="text-sm text-slate-400">Loading...</div>

    <section v-else class="card p-6 space-y-4">
      <h2 class="text-lg font-semibold text-slate-900">Sender settings</h2>
      <div class="grid sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">From name</label>
          <input v-model="settings.from_name" class="input" placeholder="Sycamore Info Hub" />
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">From email</label>
          <input v-model="settings.from_email" class="input" placeholder="hub@sycamore.ng" />
          <p class="text-xs text-slate-500 mt-1.5">Must be verified in SendGrid or sending will fail.</p>
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">Reply-to</label>
          <input v-model="settings.reply_to" class="input" placeholder="Optional" />
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">Brand color</label>
          <input v-model="settings.brand_color" class="input" placeholder="#0f6e42" />
        </div>
      </div>
      <div>
        <label class="block text-sm font-medium text-slate-700 mb-1.5">Footer HTML</label>
        <textarea v-model="settings.footer_html" rows="4" class="input" placeholder="Appears at the bottom of every email."></textarea>
      </div>

      <div class="pt-4 border-t border-slate-100">
        <h3 class="text-sm font-semibold text-slate-900 mb-3">Scheduling & links</h3>
        <div class="grid sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1.5">App base URL</label>
            <input v-model="settings.app_base_url" class="input" placeholder="https://hub.sycamore.ng" />
            <p class="text-xs text-slate-500 mt-1.5">Used to build "Read on the Hub" and unsubscribe links inside emails.</p>
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1.5">Supabase project URL</label>
            <input v-model="settings.function_base_url" class="input" placeholder="https://xyz.supabase.co" />
            <p class="text-xs text-slate-500 mt-1.5">Where the edge function is deployed. Usually the same as your project URL.</p>
          </div>
          <div class="sm:col-span-2">
            <label class="block text-sm font-medium text-slate-700 mb-1.5">Service role key (for scheduled jobs only)</label>
            <input v-model="settings.service_token" class="input" type="password" placeholder="eyJhbGc..." />
            <p class="text-xs text-slate-500 mt-1.5">Stored in the database so pg_cron can authenticate hourly digest and reminder jobs. Never shown to regular users.</p>
          </div>
        </div>
      </div>
      <label class="flex items-center gap-2">
        <input type="checkbox" v-model="settings.default_enabled" class="w-4 h-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-300" />
        <span class="text-sm text-slate-700">Email sending enabled (master switch)</span>
      </label>
      <div class="flex justify-end">
        <button class="btn-primary" :disabled="saving" @click="save"><span v-if="saving">Saving...</span><span v-else>Save settings</span></button>
      </div>
    </section>

    <section class="card p-6 space-y-4">
      <h2 class="text-lg font-semibold text-slate-900">Test & run</h2>
      <div class="flex flex-wrap gap-3 items-end">
        <div class="flex-1 min-w-[240px]">
          <label class="block text-sm font-medium text-slate-700 mb-1.5">Send a test email to</label>
          <input v-model="testTo" class="input" type="email" placeholder="your.name@sycamore.ng" />
        </div>
        <button class="btn-secondary" :disabled="testing" @click="sendTest"><span v-if="testing">Sending...</span><span v-else>Send test</span></button>
        <button class="btn-primary" :disabled="running" @click="runQueue"><span v-if="running">Running...</span><span v-else>Run queue now</span></button>
      </div>
      <p class="text-xs text-slate-500">The queue runs automatically after each announcement is saved. Use "Run queue now" to retry failed sends.</p>
    </section>

    <section class="card p-6">
      <h2 class="text-lg font-semibold text-slate-900 mb-4">Recent activity</h2>
      <div v-if="recentLogs.length === 0" class="text-sm text-slate-400">Nothing yet.</div>
      <ul v-else class="divide-y divide-slate-100">
        <li v-for="l in recentLogs" :key="l.id" class="py-3 flex items-center justify-between gap-3">
          <div class="min-w-0">
            <div class="text-sm font-medium text-slate-900 truncate">{{ l.subject }}</div>
            <div class="text-xs text-slate-500 truncate">{{ l.to_email }} &middot; {{ l.trigger || 'manual' }}</div>
            <div v-if="l.error" class="text-xs text-rose-600 truncate">{{ l.error }}</div>
          </div>
          <div class="flex-shrink-0 flex items-center gap-3">
            <span class="badge" :class="l.status === 'sent' ? 'badge-green' : l.status === 'failed' ? 'badge-rose' : 'badge-slate'">{{ l.status }}</span>
            <span class="text-xs text-slate-400">{{ new Date(l.created_at).toLocaleString('en-GB') }}</span>
          </div>
        </li>
      </ul>
    </section>
  </div>
</template>
