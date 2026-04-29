<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()

const subject = ref('')
const heading = ref('')
const bodyHtml = ref('')
const audience = ref<'all' | 'department'>('all')
const departmentId = ref('')
const sending = ref(false)
const departments = ref<{ id: string; name: string }[]>([])
const staffCount = ref<number | null>(null)

async function loadCounts() {
  const { data } = await supabase.from('departments').select('id, name').order('name')
  departments.value = data ?? []
  const { count } = await supabase.from('staff_members').select('*', { count: 'exact', head: true }).eq('is_active', true).not('email', 'is', null)
  staffCount.value = count ?? 0
}
await loadCounts()

async function send() {
  if (!subject.value.trim() || !bodyHtml.value.trim()) { toast.error('Subject and body are required'); return }
  const ok = await toast.confirm({
    title: 'Send broadcast?',
    message: audience.value === 'all'
      ? `Send this email to all ${staffCount.value ?? ''} active staff with an email?`
      : 'Send this email to the selected department?',
    variant: 'danger',
    confirmLabel: 'Send'
  })
  if (!ok) return
  sending.value = true
  try {
    const { data: session } = await supabase.auth.getSession()
    const res = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/email/broadcast`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${session.session?.access_token ?? ''}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        subject: subject.value,
        heading: heading.value || subject.value,
        body_html: bodyHtml.value,
        audience: audience.value,
        department_id: audience.value === 'department' ? departmentId.value : undefined
      })
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(body.error || 'Failed to send')
    toast.success(`Queued to ${body.queued ?? 0} recipients.`)
    subject.value = ''
    heading.value = ''
    bodyHtml.value = ''
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to send')
  } finally {
    sending.value = false
  }
}
</script>

<template>
  <div class="max-w-4xl grid lg:grid-cols-[1fr_auto] gap-6">
    <div class="space-y-6">
      <header>
        <h1 class="text-2xl font-bold text-slate-900">Broadcast email</h1>
        <p class="text-sm text-slate-500 mt-1">Send a one-off email to active staff. Uses the "Admin broadcast" template.</p>
      </header>

      <section class="card p-6 space-y-4">
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">Subject line</label>
          <input v-model="subject" class="input" placeholder="A quick update from the team" />
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">Heading (shown at top of email)</label>
          <input v-model="heading" class="input" placeholder="Defaults to the subject if left blank" />
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-700 mb-1.5">Body (HTML allowed)</label>
          <textarea v-model="bodyHtml" rows="12" class="input font-mono text-xs" placeholder="<p>Hi everyone,</p><p>...</p>"></textarea>
          <p class="text-xs text-slate-500 mt-1.5">Paragraphs, links, and basic formatting are fine. Keep it simple.</p>
        </div>
        <div class="grid sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-slate-700 mb-1.5">Audience</label>
            <select v-model="audience" class="input">
              <option value="all">All active staff ({{ staffCount ?? '?' }})</option>
              <option value="department">Specific department</option>
            </select>
          </div>
          <div v-if="audience === 'department'">
            <label class="block text-sm font-medium text-slate-700 mb-1.5">Department</label>
            <select v-model="departmentId" class="input">
              <option value="">Choose a department...</option>
              <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
            </select>
          </div>
        </div>
        <div class="flex justify-end">
          <button class="btn-primary" :disabled="sending" @click="send"><span v-if="sending">Sending...</span><span v-else>Send broadcast</span></button>
        </div>
      </section>
    </div>

    <aside class="hidden lg:block w-80 sticky top-24 self-start">
      <div class="card p-5">
        <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Live preview</div>
        <div class="bg-slate-50 border border-slate-200 rounded-xl p-4">
          <div class="text-sm font-semibold text-slate-900 mb-2">{{ subject || 'Subject preview' }}</div>
          <div class="bg-white rounded-lg p-3 max-h-[480px] overflow-y-auto text-sm leading-relaxed">
            <h1 class="text-lg font-bold text-slate-900 mb-2">{{ heading || subject || 'Heading' }}</h1>
            <div v-html="bodyHtml || '<p style=\'color:#94a3b8\'>Your message will appear here.</p>'" />
          </div>
        </div>
      </div>
    </aside>
  </div>
</template>
