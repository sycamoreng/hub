<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()

const items = ref<any[]>([])
const loading = ref(true)
const editing = ref<any | null>(null)
const saving = ref(false)
const uploadingDoc = ref(false)
const uploadingLogo = ref(false)

async function load() {
  loading.value = true
  try {
    const { data } = await supabase
      .from('hmo_providers')
      .select('*')
      .order('sort_order')
      .order('name')
    items.value = data ?? []
  } finally {
    loading.value = false
  }
}
load()

function blank() {
  return {
    name: '',
    description: '',
    logo_url: '',
    document_url: '',
    contact_email: '',
    contact_phone: '',
    website: '',
    coverage_summary: '',
    sort_order: 100,
    is_active: true
  }
}

function openNew() { editing.value = blank() }
function openEdit(row: any) { editing.value = { ...row } }

async function uploadFile(kind: 'doc' | 'logo', file: File): Promise<string | null> {
  const path = `${kind}/${Date.now()}-${file.name}`
  const { error } = await supabase.storage.from('hmo-documents').upload(path, file, {
    cacheControl: '3600',
    upsert: false
  })
  if (error) { toast.error(error.message); return null }
  const { data } = supabase.storage.from('hmo-documents').getPublicUrl(path)
  return data.publicUrl
}

async function onUploadDoc(e: Event) {
  const f = (e.target as HTMLInputElement).files?.[0]
  if (!f || !editing.value) return
  uploadingDoc.value = true
  try {
    const url = await uploadFile('doc', f)
    if (url) editing.value.document_url = url
  } finally { uploadingDoc.value = false }
}

async function onUploadLogo(e: Event) {
  const f = (e.target as HTMLInputElement).files?.[0]
  if (!f || !editing.value) return
  uploadingLogo.value = true
  try {
    const url = await uploadFile('logo', f)
    if (url) editing.value.logo_url = url
  } finally { uploadingLogo.value = false }
}

async function save() {
  if (!editing.value) return
  if (!editing.value.name?.trim()) { toast.error('Name is required'); return }
  saving.value = true
  try {
    const payload = {
      name: editing.value.name.trim(),
      description: editing.value.description ?? '',
      logo_url: editing.value.logo_url ?? '',
      document_url: editing.value.document_url ?? '',
      contact_email: editing.value.contact_email ?? '',
      contact_phone: editing.value.contact_phone ?? '',
      website: editing.value.website ?? '',
      coverage_summary: editing.value.coverage_summary ?? '',
      sort_order: Number(editing.value.sort_order) || 100,
      is_active: !!editing.value.is_active,
      updated_at: new Date().toISOString()
    }
    if (editing.value.id) {
      const { error } = await supabase.from('hmo_providers').update(payload).eq('id', editing.value.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from('hmo_providers').insert(payload)
      if (error) throw error
    }
    toast.success('Saved')
    editing.value = null
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  } finally {
    saving.value = false
  }
}

async function remove(row: any) {
  const ok = await toast.confirm({ title: 'Delete provider', message: `Delete "${row.name}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('hmo_providers').delete().eq('id', row.id)
    if (error) throw error
    toast.success('Deleted')
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  }
}
</script>

<template>
  <div class="max-w-6xl">
    <header class="mb-6 flex items-center justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold text-slate-900">HMO providers</h1>
        <p class="text-sm text-slate-500 mt-1">Manage approved HMO providers and the document staff use to enrol.</p>
      </div>
      <button type="button" @click="openNew" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">New provider</button>
    </header>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="!items.length" class="p-5 text-sm text-slate-500">No providers yet.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Name</th>
            <th class="text-left px-5 py-2">Coverage</th>
            <th class="text-left px-5 py-2">Active</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in items" :key="r.id" class="border-t border-slate-100 align-top">
            <td class="px-5 py-3">
              <div class="font-medium text-slate-900">{{ r.name }}</div>
              <div v-if="r.website" class="text-xs text-slate-500">{{ r.website }}</div>
            </td>
            <td class="px-5 py-3 text-slate-600 text-xs whitespace-pre-line">{{ r.coverage_summary || '—' }}</td>
            <td class="px-5 py-3">{{ r.is_active ? 'Yes' : 'No' }}</td>
            <td class="px-5 py-3 text-right space-x-3 whitespace-nowrap">
              <a v-if="r.document_url" :href="r.document_url" target="_blank" rel="noopener" class="text-xs font-semibold text-sycamore-700">Document</a>
              <button type="button" @click="openEdit(r)" class="text-xs font-semibold text-slate-700">Edit</button>
              <button type="button" @click="remove(r)" class="text-xs font-semibold text-rose-600">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <div v-if="editing" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="editing = null">
      <div class="bg-white rounded-2xl max-w-lg w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ editing.id ? 'Edit' : 'New' }} HMO provider</h3>
        </header>
        <div class="p-6 grid grid-cols-2 gap-4">
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Name</span>
            <input v-model="editing.name" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Description</span>
            <input v-model="editing.description" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Contact email</span>
            <input v-model="editing.contact_email" type="email" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Contact phone</span>
            <input v-model="editing.contact_phone" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Website</span>
            <input v-model="editing.website" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Coverage summary</span>
            <textarea v-model="editing.coverage_summary" rows="3" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Logo</span>
            <input type="file" accept="image/*" @change="onUploadLogo" class="mt-1 w-full text-sm" :disabled="uploadingLogo" />
            <span v-if="editing.logo_url" class="text-xs text-emerald-700">Logo set.</span></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Provider list document (PDF)</span>
            <input type="file" accept=".pdf,.doc,.docx" @change="onUploadDoc" class="mt-1 w-full text-sm" :disabled="uploadingDoc" />
            <a v-if="editing.document_url" :href="editing.document_url" target="_blank" rel="noopener" class="text-xs text-sycamore-700">Current document</a></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Sort order</span>
            <input v-model.number="editing.sort_order" type="number" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="inline-flex items-center gap-2 text-sm">
            <input v-model="editing.is_active" type="checkbox" class="w-4 h-4 rounded border-slate-300 text-sycamore-600" />
            Active
          </label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="editing = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="save" :disabled="saving" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">
            {{ saving ? 'Saving...' : 'Save' }}
          </button>
        </footer>
      </div>
    </div>
  </div>
</template>
