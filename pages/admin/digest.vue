<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()

interface SectionConfig {
  key: string
  label: string
  enabled: boolean
  max_items: number
}

interface DigestConfig {
  id: string
  frequency: 'weekly' | 'monthly'
  day_of_week: number
  day_of_month: number
  send_hour_utc: number
  is_active: boolean
  sections: SectionConfig[]
  custom_intro: string
  last_sent_at: string | null
}

interface DigestHistoryEntry {
  id: string
  digest_type: string
  period_start: string
  period_end: string
  stats: Record<string, number>
  recipients_count: number
  sent_at: string
}

const loading = ref(true)
const saving = ref(false)
const sending = ref(false)
const previewing = ref(false)

const weeklyConfig = ref<DigestConfig | null>(null)
const monthlyConfig = ref<DigestConfig | null>(null)
const activeTab = ref<'weekly' | 'monthly'>('weekly')
const history = ref<DigestHistoryEntry[]>([])
const previewHtml = ref('')
const showPreview = ref(false)
const previewStats = ref<Record<string, number>>({})

const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

const currentConfig = computed(() =>
  activeTab.value === 'weekly' ? weeklyConfig.value : monthlyConfig.value
)

async function load() {
  loading.value = true
  const { data: configs } = await supabase
    .from('digest_config')
    .select('*')
    .order('frequency')

  if (configs) {
    for (const c of configs) {
      if (c.frequency === 'weekly') weeklyConfig.value = c as DigestConfig
      else monthlyConfig.value = c as DigestConfig
    }
  }

  const { data: hist } = await supabase
    .from('digest_history')
    .select('*')
    .order('sent_at', { ascending: false })
    .limit(10)

  if (hist) history.value = hist as DigestHistoryEntry[]
  loading.value = false
}

async function saveConfig() {
  const config = currentConfig.value
  if (!config) return
  saving.value = true
  const { error } = await supabase
    .from('digest_config')
    .update({
      day_of_week: config.day_of_week,
      day_of_month: config.day_of_month,
      send_hour_utc: config.send_hour_utc,
      is_active: config.is_active,
      sections: config.sections,
      custom_intro: config.custom_intro,
      updated_at: new Date().toISOString()
    })
    .eq('id', config.id)

  if (error) toast.error('Failed to save settings')
  else {
    toast.success('Digest settings saved')
    auditLog({
      action: 'update_digest_config',
      target_type: 'digest_config',
      target_label: config.frequency,
      details: { is_active: config.is_active }
    })
  }
  saving.value = false
}

async function sendNow() {
  const config = currentConfig.value
  if (!config) return
  const ok = await toast.confirm({
    title: `Send ${config.frequency} digest now?`,
    message: `This will compile the digest and send it to all subscribed staff immediately.`,
    variant: 'danger',
    confirmLabel: 'Send Now'
  })
  if (!ok) return

  sending.value = true
  try {
    const { data: session } = await supabase.auth.getSession()
    const res = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/hub-digest/send`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session.session?.access_token ?? ''}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ type: config.frequency })
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(body.error || 'Failed to send')
    toast.success(`Digest queued to ${body.queued ?? 0} recipients.`)
    auditLog({
      action: 'send_digest',
      target_type: 'digest',
      target_label: config.frequency,
      details: { queued: body.queued, stats: body.stats }
    })
    await load()
  } catch (e: any) {
    toast.error(e.message || 'Failed to send digest')
  }
  sending.value = false
}

async function previewDigest() {
  const config = currentConfig.value
  if (!config) return
  previewing.value = true
  try {
    const { data: session } = await supabase.auth.getSession()
    const res = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/hub-digest/preview`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session.session?.access_token ?? ''}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ type: config.frequency })
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(body.error || 'Failed to preview')
    previewHtml.value = body.html || '<p style="color:#6B7280;">No content for this period.</p>'
    previewStats.value = body.stats || {}
    showPreview.value = true
  } catch (e: any) {
    toast.error(e.message || 'Failed to load preview')
  }
  previewing.value = false
}

function toggleSection(section: SectionConfig) {
  section.enabled = !section.enabled
}

function formatDateTime(d: string | null) {
  if (!d) return 'Never'
  return new Date(d).toLocaleString('en-GB', {
    day: 'numeric', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit'
  })
}

await load()
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">Hub Digest</h1>
        <p class="text-sm text-slate-500 mt-1">Configure the automated digest email that summarises hub activity</p>
      </div>
    </div>

    <div v-if="loading" class="card p-12 text-center text-slate-400">Loading...</div>

    <template v-else>
      <!-- Tab switcher -->
      <div class="flex gap-1 p-1 bg-slate-100 rounded-xl mb-6 max-w-xs">
        <button
          @click="activeTab = 'weekly'"
          class="flex-1 px-4 py-2 rounded-lg text-sm font-medium transition-all"
          :class="activeTab === 'weekly' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        >Weekly</button>
        <button
          @click="activeTab = 'monthly'"
          class="flex-1 px-4 py-2 rounded-lg text-sm font-medium transition-all"
          :class="activeTab === 'monthly' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
        >Monthly</button>
      </div>

      <div v-if="currentConfig" class="space-y-6">
        <!-- Status & Schedule -->
        <div class="card p-5">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-base font-semibold text-slate-900">Schedule</h2>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" v-model="currentConfig.is_active" class="form-checkbox h-4 w-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500">
              <span class="text-sm font-medium" :class="currentConfig.is_active ? 'text-sycamore-700' : 'text-slate-500'">
                {{ currentConfig.is_active ? 'Active' : 'Paused' }}
              </span>
            </label>
          </div>

          <div class="grid sm:grid-cols-2 gap-4">
            <div v-if="activeTab === 'weekly'">
              <label class="block text-xs font-medium text-slate-600 mb-1">Send every</label>
              <select v-model.number="currentConfig.day_of_week" class="input">
                <option v-for="(name, i) in dayNames" :key="i" :value="i">{{ name }}</option>
              </select>
            </div>
            <div v-else>
              <label class="block text-xs font-medium text-slate-600 mb-1">Day of month</label>
              <select v-model.number="currentConfig.day_of_month" class="input">
                <option v-for="d in 28" :key="d" :value="d">{{ d }}{{ d === 1 ? 'st' : d === 2 ? 'nd' : d === 3 ? 'rd' : 'th' }}</option>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Time (UTC)</label>
              <select v-model.number="currentConfig.send_hour_utc" class="input">
                <option v-for="h in 24" :key="h - 1" :value="h - 1">{{ String(h - 1).padStart(2, '0') }}:00 UTC</option>
              </select>
            </div>
          </div>

          <div class="mt-4 flex items-center gap-4 text-xs text-slate-500">
            <span>Last sent: {{ formatDateTime(currentConfig.last_sent_at) }}</span>
          </div>
        </div>

        <!-- Custom Intro -->
        <div class="card p-5">
          <h2 class="text-base font-semibold text-slate-900 mb-3">Custom Introduction</h2>
          <textarea
            v-model="currentConfig.custom_intro"
            class="input min-h-[80px]"
            placeholder="Optional custom intro text for the digest email. Leave blank for the default message."
          ></textarea>
          <p class="text-[11px] text-slate-400 mt-1">This text appears at the top of the digest email before the content sections.</p>
        </div>

        <!-- Sections Configuration -->
        <div class="card p-5">
          <h2 class="text-base font-semibold text-slate-900 mb-3">Content Sections</h2>
          <p class="text-xs text-slate-500 mb-4">Toggle sections on/off and set the maximum number of items shown in each.</p>

          <div class="space-y-2">
            <div
              v-for="section in currentConfig.sections"
              :key="section.key"
              class="flex items-center gap-3 p-3 rounded-lg border transition-colors"
              :class="section.enabled ? 'border-sycamore-200 bg-sycamore-50/50' : 'border-slate-200 bg-slate-50'"
            >
              <button
                @click="toggleSection(section)"
                class="w-9 h-5 rounded-full transition-colors relative shrink-0"
                :class="section.enabled ? 'bg-sycamore-500' : 'bg-slate-300'"
              >
                <span
                  class="absolute top-0.5 w-4 h-4 bg-white rounded-full shadow-sm transition-transform"
                  :class="section.enabled ? 'left-[18px]' : 'left-0.5'"
                ></span>
              </button>
              <div class="flex-1 min-w-0">
                <span class="text-sm font-medium" :class="section.enabled ? 'text-slate-900' : 'text-slate-500'">
                  {{ section.label }}
                </span>
              </div>
              <div class="flex items-center gap-1.5 shrink-0">
                <label class="text-[11px] text-slate-400">Max:</label>
                <select
                  v-model.number="section.max_items"
                  class="border border-slate-200 rounded px-1.5 py-0.5 text-xs bg-white text-slate-700 w-14"
                  :disabled="!section.enabled"
                >
                  <option v-for="n in [3, 5, 7, 10, 15, 20]" :key="n" :value="n">{{ n }}</option>
                </select>
              </div>
            </div>
          </div>
        </div>

        <!-- Action buttons -->
        <div class="flex flex-wrap items-center gap-3">
          <button @click="saveConfig" :disabled="saving" class="btn-primary">
            {{ saving ? 'Saving...' : 'Save Settings' }}
          </button>
          <button @click="previewDigest" :disabled="previewing" class="btn-secondary">
            {{ previewing ? 'Loading...' : 'Preview Digest' }}
          </button>
          <button @click="sendNow" :disabled="sending" class="btn-secondary text-amber-700 border-amber-200 hover:bg-amber-50">
            {{ sending ? 'Sending...' : 'Send Now' }}
          </button>
        </div>

        <!-- Send History -->
        <div v-if="history.length > 0" class="card p-5">
          <h2 class="text-base font-semibold text-slate-900 mb-3">Send History</h2>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-xs font-medium text-slate-500 border-b">
                  <th class="pb-2 pr-4">Type</th>
                  <th class="pb-2 pr-4">Period</th>
                  <th class="pb-2 pr-4">Recipients</th>
                  <th class="pb-2">Sent</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="h in history" :key="h.id" class="border-b border-slate-100 last:border-0">
                  <td class="py-2.5 pr-4">
                    <span class="inline-flex px-2 py-0.5 rounded-full text-xs font-medium"
                      :class="h.digest_type === 'weekly' ? 'bg-blue-50 text-blue-700' : 'bg-emerald-50 text-emerald-700'">
                      {{ h.digest_type }}
                    </span>
                  </td>
                  <td class="py-2.5 pr-4 text-slate-600">
                    {{ new Date(h.period_start).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) }}
                    –
                    {{ new Date(h.period_end).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) }}
                  </td>
                  <td class="py-2.5 pr-4 text-slate-600">{{ h.recipients_count }}</td>
                  <td class="py-2.5 text-slate-500 text-xs">{{ formatDateTime(h.sent_at) }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <div v-else class="card p-10 text-center">
        <p class="text-slate-500">No digest configuration found. Something went wrong during setup.</p>
      </div>
    </template>

    <!-- Preview Modal -->
    <div v-if="showPreview" class="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4" @click.self="showPreview = false">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-2xl max-h-[85vh] flex flex-col animate-[slideUp_0.2s_ease-out]">
        <div class="flex items-center justify-between p-5 border-b shrink-0">
          <div>
            <h2 class="text-lg font-bold text-slate-900">Digest Preview</h2>
            <p class="text-xs text-slate-500 mt-0.5">This is what recipients will see</p>
          </div>
          <button @click="showPreview = false" class="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" /></svg>
          </button>
        </div>

        <!-- Stats bar -->
        <div v-if="Object.values(previewStats).some(v => v > 0)" class="flex flex-wrap gap-3 px-5 py-3 bg-slate-50 border-b">
          <span v-if="previewStats.announcements_count" class="text-xs text-slate-600">{{ previewStats.announcements_count }} announcements</span>
          <span v-if="previewStats.posts_count" class="text-xs text-slate-600">{{ previewStats.posts_count }} posts</span>
          <span v-if="previewStats.birthdays_count" class="text-xs text-slate-600">{{ previewStats.birthdays_count }} birthdays</span>
          <span v-if="previewStats.anniversaries_count" class="text-xs text-slate-600">{{ previewStats.anniversaries_count }} anniversaries</span>
          <span v-if="previewStats.new_joiners_count" class="text-xs text-slate-600">{{ previewStats.new_joiners_count }} new joiners</span>
          <span v-if="previewStats.kudos_count" class="text-xs text-slate-600">{{ previewStats.kudos_count }} kudos</span>
          <span v-if="previewStats.badges_count" class="text-xs text-slate-600">{{ previewStats.badges_count }} badges</span>
          <span v-if="previewStats.events_count" class="text-xs text-slate-600">{{ previewStats.events_count }} events</span>
        </div>

        <div class="flex-1 overflow-y-auto p-5">
          <div v-html="previewHtml" class="prose prose-sm max-w-none"></div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes slideUp {
  from { opacity: 0; transform: translateY(12px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
