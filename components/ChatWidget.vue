<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { user } = useAuth()
const config = useRuntimeConfig()
const supabaseUrl = config.public.supabaseUrl as string

const open = ref(false)
const enabled = ref(false)
const welcome = ref('')
const messages = ref<{ role: 'user' | 'assistant', content: string }[]>([])
const input = ref('')
const sending = ref(false)
const error = ref('')
const scroller = ref<HTMLElement | null>(null)

async function loadSettings() {
  const { data } = await supabase
    .from('chatbot_settings')
    .select('is_enabled, welcome_message')
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle()
  enabled.value = !!data?.is_enabled
  welcome.value = data?.welcome_message ?? ''
}

onMounted(loadSettings)

function scrollToEnd() {
  nextTick(() => {
    if (scroller.value) scroller.value.scrollTop = scroller.value.scrollHeight
  })
}

async function send() {
  const text = input.value.trim()
  if (!text || sending.value) return
  if (!user.value) {
    error.value = 'Please sign in to chat.'
    return
  }
  error.value = ''
  messages.value.push({ role: 'user', content: text })
  input.value = ''
  sending.value = true
  scrollToEnd()
  try {
    const { data: sessionData } = await supabase.auth.getSession()
    const token = sessionData.session?.access_token
    const url = `${supabaseUrl}/functions/v1/chat`
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ message: text })
    })
    const body = await res.json()
    if (!res.ok) {
      error.value = body.error || 'Something went wrong.'
    } else {
      messages.value.push({ role: 'assistant', content: body.reply })
    }
  } catch (e: any) {
    error.value = e.message ?? 'Network error'
  } finally {
    sending.value = false
    scrollToEnd()
  }
}

function toggle() {
  open.value = !open.value
  if (open.value && messages.value.length === 0 && welcome.value) {
    messages.value.push({ role: 'assistant', content: welcome.value })
  }
  scrollToEnd()
}
</script>

<template>
  <div v-if="enabled" class="fixed bottom-5 right-5 z-50">
    <div
      v-if="open"
      class="mb-3 w-[min(380px,calc(100vw-2.5rem))] h-[min(560px,calc(100vh-7rem))] flex flex-col card shadow-xl border-slate-200 overflow-hidden"
    >
      <div class="flex items-center justify-between px-4 py-3 bg-gradient-to-r from-sycamore-700 to-sycamore-900 text-white">
        <div class="flex items-center gap-2.5">
          <div class="w-8 h-8 rounded-full bg-white/15 flex items-center justify-center">
            <SidebarIcon name="chat" />
          </div>
          <div>
            <div class="font-semibold text-sm leading-tight">Sycamore Assistant</div>
            <div class="text-xs text-sycamore-100/80">Knowledgebase-powered</div>
          </div>
        </div>
        <button @click="toggle" class="p-1 rounded hover:bg-white/10" aria-label="Close chat">
          <SidebarIcon name="close" />
        </button>
      </div>

      <div ref="scroller" class="flex-1 overflow-y-auto p-4 space-y-3 bg-slate-50">
        <div v-if="!user" class="text-sm text-slate-500 text-center py-8">
          <NuxtLink to="/login" class="text-sycamore-700 underline">Sign in</NuxtLink> to chat with the assistant.
        </div>
        <div
          v-for="(m, i) in messages"
          :key="i"
          :class="['flex', m.role === 'user' ? 'justify-end' : 'justify-start']"
        >
          <div
            :class="[
              'max-w-[85%] rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap',
              m.role === 'user'
                ? 'bg-sycamore-600 text-white rounded-br-sm'
                : 'bg-white border border-slate-200 text-slate-800 rounded-bl-sm'
            ]"
          >{{ m.content }}</div>
        </div>
        <div v-if="sending" class="flex justify-start">
          <div class="bg-white border border-slate-200 rounded-2xl px-3.5 py-2 text-sm text-slate-500">Thinking...</div>
        </div>
        <div v-if="error" class="text-xs text-rose-600 bg-rose-50 border border-rose-200 rounded-lg p-2">{{ error }}</div>
      </div>

      <form @submit.prevent="send" class="p-3 border-t border-slate-200 bg-white flex gap-2">
        <input
          v-model="input"
          type="text"
          :disabled="!user || sending"
          placeholder="Ask about policies, products, anything..."
          class="flex-1 px-3 py-2 rounded-lg border border-slate-200 text-sm focus:outline-none focus:border-sycamore-400 focus:ring-2 focus:ring-sycamore-100"
        />
        <button
          type="submit"
          :disabled="!user || sending || !input.trim()"
          class="px-3 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium disabled:bg-slate-300"
        >Send</button>
      </form>
    </div>

    <button
      @click="toggle"
      :class="[
        'w-14 h-14 rounded-full shadow-lg flex items-center justify-center transition-transform hover:scale-105',
        open ? 'bg-slate-700 text-white' : 'bg-gradient-to-br from-sycamore-600 to-sycamore-800 text-white'
      ]"
      :aria-label="open ? 'Close chat' : 'Open chat'"
    >
      <SidebarIcon v-if="!open" name="chat" />
      <SidebarIcon v-else name="close" />
    </button>
  </div>
</template>
