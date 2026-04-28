<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const settings = ref<any | null>(null)
const loading = ref(true)
const saving = ref(false)
const message = ref('')

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('chatbot_settings')
    .select('*')
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle()
  settings.value = data ?? {
    is_enabled: true,
    system_prompt: '',
    welcome_message: '',
    allowed_topics: '',
    blocked_topics: '',
    max_messages_per_user_per_day: 50,
    response_tone: 'friendly and professional'
  }
  loading.value = false
}

onMounted(load)

async function save() {
  if (!settings.value) return
  saving.value = true
  message.value = ''
  try {
    const payload = {
      is_enabled: !!settings.value.is_enabled,
      system_prompt: settings.value.system_prompt ?? '',
      welcome_message: settings.value.welcome_message ?? '',
      allowed_topics: settings.value.allowed_topics ?? '',
      blocked_topics: settings.value.blocked_topics ?? '',
      max_messages_per_user_per_day: Number(settings.value.max_messages_per_user_per_day) || 50,
      response_tone: settings.value.response_tone ?? '',
      updated_at: new Date().toISOString()
    }
    if (settings.value.id) {
      const { error } = await supabase.from('chatbot_settings').update(payload).eq('id', settings.value.id)
      if (error) throw error
    } else {
      const { data, error } = await supabase.from('chatbot_settings').insert(payload).select().maybeSingle()
      if (error) throw error
      settings.value = data
    }
    message.value = 'Settings saved.'
  } catch (e: any) {
    message.value = e.message ?? 'Failed to save'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="max-w-3xl">
    <div class="mb-8">
      <h1 class="section-title">Chatbot settings</h1>
      <p class="section-subtitle">Control how the AI assistant behaves for staff.</p>
    </div>

    <div v-if="loading" class="text-slate-400">Loading settings...</div>
    <form v-else-if="settings" @submit.prevent="save" class="card p-6 space-y-5">
      <label class="flex items-start gap-3">
        <input type="checkbox" v-model="settings.is_enabled" class="mt-1 h-4 w-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500" />
        <span>
          <span class="font-medium text-slate-900 block">Chatbot enabled</span>
          <span class="text-xs text-slate-500">When off, the floating chat widget is hidden for everyone.</span>
        </span>
      </label>

      <div>
        <label class="block text-sm font-medium text-slate-800 mb-1">Welcome message</label>
        <textarea v-model="settings.welcome_message" rows="2" class="input"></textarea>
        <p class="text-xs text-slate-500 mt-1">Shown when a user opens the chat for the first time.</p>
      </div>

      <div>
        <label class="block text-sm font-medium text-slate-800 mb-1">System prompt</label>
        <textarea v-model="settings.system_prompt" rows="6" class="input font-mono text-xs"></textarea>
        <p class="text-xs text-slate-500 mt-1">The base instruction the AI follows. Knowledgebase context is appended automatically.</p>
      </div>

      <div class="grid sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium text-slate-800 mb-1">Allowed topics</label>
          <textarea v-model="settings.allowed_topics" rows="3" class="input"></textarea>
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-800 mb-1">Blocked topics</label>
          <textarea v-model="settings.blocked_topics" rows="3" class="input"></textarea>
        </div>
      </div>

      <div class="grid sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium text-slate-800 mb-1">Response tone</label>
          <input v-model="settings.response_tone" type="text" class="input" placeholder="e.g. friendly and professional" />
        </div>
        <div>
          <label class="block text-sm font-medium text-slate-800 mb-1">Max messages / user / day</label>
          <input v-model="settings.max_messages_per_user_per_day" type="number" min="0" class="input" />
        </div>
      </div>

      <div class="flex items-center justify-between pt-3 border-t border-slate-100">
        <div class="text-sm" :class="message.startsWith('Settings saved') ? 'text-leaf-700' : 'text-rose-600'">{{ message }}</div>
        <button type="submit" :disabled="saving" class="btn-primary">
          {{ saving ? 'Saving...' : 'Save settings' }}
        </button>
      </div>
    </form>

    <div class="card p-6 mt-6 bg-amber-50 border-amber-200">
      <div class="flex items-start gap-3">
        <div class="text-amber-700 mt-0.5"><SidebarIcon name="alert" /></div>
        <div>
          <div class="font-semibold text-amber-900">API key required</div>
          <p class="text-sm text-amber-800 mt-1">The chatbot uses Anthropic's Claude. Add an <code class="px-1 bg-white rounded">ANTHROPIC_API_KEY</code> secret in your Supabase project's edge function environment for the bot to respond.</p>
        </div>
      </div>
    </div>
  </div>
</template>
