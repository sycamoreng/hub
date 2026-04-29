<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()

const templates = ref<any[]>([])
const loading = ref(true)
const editing = ref<any | null>(null)
const saving = ref(false)

function varLabel(v: string) { return '{{' + v + '}}' }

async function load() {
  loading.value = true
  const { data } = await supabase.from('email_templates').select('*').order('is_system', { ascending: false }).order('name')
  templates.value = data ?? []
  loading.value = false
}

await load()

function openEdit(t: any) { editing.value = { ...t } }
function closeEdit() { editing.value = null }

async function save() {
  if (!editing.value) return
  saving.value = true
  try {
    const payload = {
      name: editing.value.name,
      description: editing.value.description ?? '',
      subject: editing.value.subject,
      html_body: editing.value.html_body,
      text_body: editing.value.text_body ?? '',
      is_active: !!editing.value.is_active,
      updated_at: new Date().toISOString()
    }
    if (editing.value.id) {
      await supabase.from('email_templates').update(payload).eq('id', editing.value.id)
    } else {
      await supabase.from('email_templates').insert({
        ...payload,
        slug: editing.value.slug,
        variables: editing.value.variables ?? [],
        is_system: false
      })
    }
    toast.success('Saved')
    closeEdit()
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally {
    saving.value = false
  }
}

async function remove(t: any) {
  if (t.is_system) { toast.error('System templates cannot be deleted'); return }
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${t.name}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  await supabase.from('email_templates').delete().eq('id', t.id)
  await load()
  toast.success('Deleted')
}
</script>

<template>
  <div class="max-w-6xl space-y-6">
    <header>
      <h1 class="text-2xl font-bold text-slate-900">Email templates</h1>
      <p class="text-sm text-slate-500 mt-1">Edit the copy and styling of each system email. Use <code>&#123;&#123;variable&#125;&#125;</code> placeholders inside the subject and body.</p>
    </header>

    <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
    <div v-else class="grid gap-3">
      <article v-for="t in templates" :key="t.id" class="card p-5">
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <h3 class="font-semibold text-slate-900">{{ t.name }}</h3>
              <span v-if="t.is_system" class="badge badge-slate">System</span>
              <span v-if="!t.is_active" class="badge badge-amber">Inactive</span>
            </div>
            <div class="text-xs text-slate-500 mt-1">{{ t.slug }}</div>
            <p class="text-sm text-slate-600 mt-2">{{ t.description }}</p>
            <div v-if="t.variables?.length" class="mt-3 flex flex-wrap gap-1.5">
              <code v-for="v in t.variables" :key="v" class="text-[11px] px-2 py-0.5 rounded-md bg-slate-100 text-slate-700">{{ varLabel(v) }}</code>
            </div>
          </div>
          <div class="flex gap-2 flex-shrink-0">
            <button class="btn-secondary" @click="openEdit(t)">Edit</button>
            <button v-if="!t.is_system" class="btn-ghost text-rose-600" @click="remove(t)">Delete</button>
          </div>
        </div>
      </article>
    </div>

    <Teleport to="body">
      <div v-if="editing" class="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4" @click.self="closeEdit">
        <div class="bg-white rounded-2xl shadow-xl max-w-5xl w-full max-h-[92vh] flex flex-col">
          <header class="flex items-center justify-between p-6 border-b border-slate-100">
            <div>
              <h2 class="text-xl font-bold text-slate-900">{{ editing.name }}</h2>
              <div class="text-xs text-slate-500 mt-1">{{ editing.slug }}</div>
            </div>
            <button class="p-2 rounded-lg hover:bg-slate-100" @click="closeEdit" aria-label="Close"><SidebarIcon name="close" /></button>
          </header>
          <div class="flex-1 overflow-y-auto p-6 grid lg:grid-cols-2 gap-6">
            <div class="space-y-4">
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1.5">Name</label>
                <input v-model="editing.name" class="input" />
              </div>
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1.5">Description</label>
                <input v-model="editing.description" class="input" />
              </div>
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1.5">Subject</label>
                <input v-model="editing.subject" class="input" />
              </div>
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1.5">HTML body</label>
                <textarea v-model="editing.html_body" rows="14" class="input font-mono text-xs"></textarea>
              </div>
              <div>
                <label class="block text-sm font-medium text-slate-700 mb-1.5">Plain text body</label>
                <textarea v-model="editing.text_body" rows="6" class="input font-mono text-xs"></textarea>
              </div>
              <label class="flex items-center gap-2">
                <input type="checkbox" v-model="editing.is_active" class="w-4 h-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-300" />
                <span class="text-sm text-slate-700">Active</span>
              </label>
            </div>
            <div class="space-y-3">
              <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Preview</div>
              <div class="rounded-xl border border-slate-200 bg-slate-50 p-4">
                <div class="text-sm font-semibold text-slate-900 mb-2">{{ editing.subject }}</div>
                <div class="bg-white rounded-lg p-2 max-h-[520px] overflow-y-auto" v-html="editing.html_body" />
              </div>
              <p class="text-xs text-slate-500">Placeholders are not substituted in preview. They will be filled in at send time.</p>
            </div>
          </div>
          <footer class="flex items-center justify-end gap-3 p-6 border-t border-slate-100">
            <button class="btn-secondary" @click="closeEdit">Cancel</button>
            <button class="btn-primary" :disabled="saving" @click="save"><span v-if="saving">Saving...</span><span v-else>Save</span></button>
          </footer>
        </div>
      </div>
    </Teleport>
  </div>
</template>
