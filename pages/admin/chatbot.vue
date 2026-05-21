<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { log: auditLog } = useAuditLog()
const settings = ref<any | null>(null)
const loading = ref(true)
const saving = ref(false)
const message = ref('')

// Knowledge Base state
const documents = ref<any[]>([])
const docsLoading = ref(false)
const uploading = ref(false)
const uploadMsg = ref('')
const pasteTitle = ref('')
const pasteContent = ref('')
const showPaste = ref(false)

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

async function loadDocs() {
  docsLoading.value = true
  const { data } = await supabase
    .from('kb_documents')
    .select('*')
    .order('created_at', { ascending: false })
  documents.value = data ?? []
  docsLoading.value = false
}

onMounted(() => { load(); loadDocs() })

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
    auditLog({ action: 'update', target_type: 'chatbot_settings', target_label: 'Chatbot settings' })
    message.value = 'Settings saved.'
  } catch (e: any) {
    message.value = e.message ?? 'Failed to save'
  } finally {
    saving.value = false
  }
}

async function uploadFile(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  uploading.value = true
  uploadMsg.value = ''
  try {
    const config = useRuntimeConfig()
    const supabaseUrl = config.public.supabaseUrl || import.meta.env.VITE_SUPABASE_URL
    const { data: sessionData } = await supabase.auth.getSession()
    const token = sessionData?.session?.access_token
    const formData = new FormData()
    formData.append('file', file)
    formData.append('title', file.name.replace(/\.[^/.]+$/, ''))
    const res = await fetch(`${supabaseUrl}/functions/v1/kb-upload`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
      },
      body: formData,
    })
    const result = await res.json()
    if (!res.ok) throw new Error(result.error || 'Upload failed')
    auditLog({ action: 'upload_kb_document', target_type: 'kb_document', target_label: result.title })
    uploadMsg.value = `Uploaded "${result.title}" - ${result.chunks} chunks created.`
    loadDocs()
  } catch (e: any) {
    uploadMsg.value = e.message ?? 'Upload failed'
  } finally {
    uploading.value = false
    input.value = ''
  }
}

async function uploadPaste() {
  if (!pasteContent.value.trim()) return
  uploading.value = true
  uploadMsg.value = ''
  try {
    const config = useRuntimeConfig()
    const supabaseUrl = config.public.supabaseUrl || import.meta.env.VITE_SUPABASE_URL
    const { data: sessionData } = await supabase.auth.getSession()
    const token = sessionData?.session?.access_token
    const res = await fetch(`${supabaseUrl}/functions/v1/kb-upload`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        title: pasteTitle.value || 'Pasted content',
        content: pasteContent.value,
      }),
    })
    const result = await res.json()
    if (!res.ok) throw new Error(result.error || 'Upload failed')
    auditLog({ action: 'upload_kb_document', target_type: 'kb_document', target_label: result.title })
    uploadMsg.value = `Added "${result.title}" - ${result.chunks} chunks created.`
    pasteTitle.value = ''
    pasteContent.value = ''
    showPaste.value = false
    loadDocs()
  } catch (e: any) {
    uploadMsg.value = e.message ?? 'Upload failed'
  } finally {
    uploading.value = false
  }
}

async function deleteDoc(doc: any) {
  if (!confirm(`Delete "${doc.title}"? This removes it from the knowledge base.`)) return
  await supabase.from('kb_documents').delete().eq('id', doc.id)
  auditLog({ action: 'delete', target_type: 'kb_document', target_id: doc.id, target_label: doc.title })
  loadDocs()
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
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

    <!-- Knowledge Base Section -->
    <div class="mt-10">
      <h2 class="section-title">Knowledge base</h2>
      <p class="section-subtitle mb-4">Upload documents to give the chatbot more context. It uses semantic search to find relevant information when answering questions.</p>

      <!-- Upload controls -->
      <div class="card p-5 space-y-4">
        <div class="flex flex-wrap gap-3 items-center">
          <label class="btn-primary cursor-pointer inline-flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v2a2 2 0 002 2h12a2 2 0 002-2v-2M7 10l5-5m0 0l5 5m-5-5v12"/></svg>
            {{ uploading ? 'Processing...' : 'Upload file' }}
            <input type="file" class="hidden" accept=".txt,.csv,.md,.json,.pdf" :disabled="uploading" @change="uploadFile" />
          </label>
          <button type="button" class="btn-secondary" @click="showPaste = !showPaste">
            {{ showPaste ? 'Cancel paste' : 'Paste text' }}
          </button>
          <span class="text-xs text-slate-500">Supported: TXT, CSV, MD, JSON, PDF (max 10 MB)</span>
        </div>

        <!-- Paste form -->
        <div v-if="showPaste" class="border border-slate-200 rounded-lg p-4 space-y-3 bg-slate-50">
          <input v-model="pasteTitle" type="text" class="input" placeholder="Document title" />
          <textarea v-model="pasteContent" rows="6" class="input font-mono text-xs" placeholder="Paste your content here..."></textarea>
          <button type="button" class="btn-primary" :disabled="uploading || !pasteContent.trim()" @click="uploadPaste">
            {{ uploading ? 'Processing...' : 'Add to knowledge base' }}
          </button>
        </div>

        <p v-if="uploadMsg" class="text-sm" :class="uploadMsg.includes('failed') || uploadMsg.includes('Error') ? 'text-rose-600' : 'text-leaf-700'">{{ uploadMsg }}</p>
      </div>

      <!-- Documents list -->
      <div class="mt-5">
        <div v-if="docsLoading" class="text-sm text-slate-400">Loading documents...</div>
        <div v-else-if="documents.length === 0" class="card p-6 text-center text-slate-500 text-sm">
          No documents uploaded yet. Upload files or paste text to build the chatbot's knowledge base.
        </div>
        <div v-else class="space-y-2">
          <div v-for="doc in documents" :key="doc.id" class="card p-4 flex items-center justify-between gap-4">
            <div class="min-w-0 flex-1">
              <div class="font-medium text-slate-900 truncate">{{ doc.title }}</div>
              <div class="text-xs text-slate-500 flex flex-wrap gap-3 mt-1">
                <span>{{ doc.file_name }}</span>
                <span>{{ formatSize(doc.file_size) }}</span>
                <span>{{ doc.chunk_count }} chunks</span>
                <span :class="doc.status === 'ready' ? 'text-leaf-700' : doc.status === 'error' ? 'text-rose-600' : 'text-amber-600'">
                  {{ doc.status }}
                </span>
              </div>
              <div v-if="doc.error_message" class="text-xs text-rose-600 mt-1">{{ doc.error_message }}</div>
            </div>
            <button type="button" class="text-slate-400 hover:text-rose-600 transition-colors shrink-0" title="Delete document" @click="deleteDoc(doc)">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
