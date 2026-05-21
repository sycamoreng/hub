<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()

const items = ref<any[]>([])
const loading = ref(true)
const editing = ref<any | null>(null)
const saving = ref(false)
const uploadingDoc = ref(false)
const uploadingLogo = ref(false)

const enrollments = ref<any[]>([])
const staffOptions = ref<any[]>([])
const enrollmentsLoading = ref(true)
const enrollmentEditing = ref<any | null>(null)
const enrollmentSaving = ref(false)
const enrollmentSearch = ref('')

const bulkOpen = ref(false)
const bulkCsv = ref('')
const bulkParsed = ref<{ rows: any[]; errors: string[] }>({ rows: [], errors: [] })
const bulkImporting = ref(false)

const bulkSample = `email,enrollee_id,plan_name,provider_name,effective_date
ada@sycamore.ng,AVN-123456,Gold,Avon HMO,2026-01-01
ken@sycamore.ng,HYG-987654,Platinum,Hygeia,2026-02-15`

function parseCsvLine(line: string): string[] {
  const out: string[] = []
  let cur = ''
  let q = false
  for (let i = 0; i < line.length; i++) {
    const c = line[i]
    if (q) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++ }
      else if (c === '"') q = false
      else cur += c
    } else {
      if (c === '"') q = true
      else if (c === ',') { out.push(cur); cur = '' }
      else cur += c
    }
  }
  out.push(cur)
  return out
}

function parseBulkCsv(text: string) {
  const lines = text.trim().split(/\r?\n/).filter(l => l.trim().length > 0)
  if (lines.length < 2) return { rows: [], errors: ['Need a header row and at least one data row.'] }
  const header = parseCsvLine(lines[0]).map(h => h.trim().toLowerCase())
  if (!header.includes('email')) return { rows: [], errors: ['Missing required column: email'] }
  const rows: any[] = []
  const errors: string[] = []
  for (let i = 1; i < lines.length; i++) {
    const cells = parseCsvLine(lines[i])
    const r: any = {}
    header.forEach((h, idx) => { r[h] = (cells[idx] ?? '').trim() })
    if (!r.email) { errors.push(`Row ${i + 1}: missing email`); continue }
    r.email = r.email.toLowerCase()
    if (r.effective_date && !/^\d{4}-\d{2}-\d{2}$/.test(r.effective_date)) {
      errors.push(`Row ${i + 1}: effective_date must be YYYY-MM-DD`)
      continue
    }
    rows.push(r)
  }
  return { rows, errors }
}

watch(bulkCsv, (v) => {
  if (!v.trim()) { bulkParsed.value = { rows: [], errors: [] }; return }
  bulkParsed.value = parseBulkCsv(v)
})

async function onBulkFile(e: Event) {
  const f = (e.target as HTMLInputElement).files?.[0]
  if (!f) return
  bulkCsv.value = await f.text()
}

function bulkUseSample() { bulkCsv.value = bulkSample }

function openBulk() {
  bulkOpen.value = true
  bulkCsv.value = ''
  bulkParsed.value = { rows: [], errors: [] }
}

async function runBulkImport() {
  const rows = bulkParsed.value.rows
  if (!rows.length) return
  bulkImporting.value = true
  try {
    const emails = Array.from(new Set(rows.map(r => r.email)))
    const { data: staff } = await supabase
      .from('staff_members')
      .select('id, email')
      .in('email', emails)
    const staffByEmail = new Map((staff ?? []).map((s: any) => [String(s.email).toLowerCase(), s.id]))

    const providerNames = Array.from(new Set(rows.map(r => (r.provider_name ?? '').trim()).filter(Boolean)))
    let providersByName = new Map<string, string>()
    if (providerNames.length) {
      const { data: provs } = await supabase
        .from('hmo_providers')
        .select('id, name')
        .in('name', providerNames)
      providersByName = new Map((provs ?? []).map((p: any) => [String(p.name).toLowerCase(), p.id]))
    }

    const skipped: string[] = []
    const inserts: any[] = []
    const updates: { id: string; payload: any }[] = []

    const { data: existing } = await supabase
      .from('staff_hmo_enrollments')
      .select('id, staff_id')
      .in('staff_id', Array.from(staffByEmail.values()))
    const existingByStaff = new Map((existing ?? []).map((e: any) => [e.staff_id, e.id]))

    for (const r of rows) {
      const staff_id = staffByEmail.get(r.email)
      if (!staff_id) { skipped.push(r.email); continue }
      const provider_id = r.provider_name ? (providersByName.get(String(r.provider_name).toLowerCase()) ?? null) : null
      const payload: any = {
        staff_id,
        provider_id,
        enrollee_id: r.enrollee_id ?? '',
        plan_name: r.plan_name ?? '',
        effective_date: r.effective_date || null,
        notes: r.notes ?? '',
        updated_at: new Date().toISOString()
      }
      const existingId = existingByStaff.get(staff_id)
      if (existingId) updates.push({ id: existingId, payload })
      else inserts.push(payload)
    }

    if (inserts.length) {
      const { error } = await supabase.from('staff_hmo_enrollments').insert(inserts)
      if (error) throw error
    }
    for (const u of updates) {
      const { error } = await supabase.from('staff_hmo_enrollments').update(u.payload).eq('id', u.id)
      if (error) throw error
    }

    let msg = `Imported ${inserts.length + updates.length} enrollments (${inserts.length} new, ${updates.length} updated)`
    if (skipped.length) msg += ` — skipped ${skipped.length} unknown email${skipped.length === 1 ? '' : 's'}`
    auditLog({ action: 'bulk_import', target_type: 'hmo_enrollment', target_label: msg })
    toast.success(msg)
    bulkOpen.value = false
    bulkCsv.value = ''
    await loadEnrollments()
  } catch (e: any) {
    toast.error(e.message ?? 'Import failed')
  } finally {
    bulkImporting.value = false
  }
}

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
    directory_url: '',
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
      directory_url: editing.value.directory_url ?? '',
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
    auditLog({ action: editing.value.id ? 'update' : 'create', target_type: 'hmo_provider', target_label: payload.name })
    toast.success('Saved')
    editing.value = null
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  } finally {
    saving.value = false
  }
}

async function loadEnrollments() {
  enrollmentsLoading.value = true
  try {
    const [enrRes, staffRes] = await Promise.all([
      supabase
        .from('staff_hmo_enrollments')
        .select('*, staff:staff_members(id, full_name, email, role), provider:hmo_providers(id, name)')
        .order('updated_at', { ascending: false }),
      supabase
        .from('staff_members')
        .select('id, full_name, email, role')
        .eq('is_active', true)
        .order('full_name')
    ])
    enrollments.value = enrRes.data ?? []
    staffOptions.value = staffRes.data ?? []
  } finally {
    enrollmentsLoading.value = false
  }
}
loadEnrollments()

const filteredEnrollments = computed(() => {
  const q = enrollmentSearch.value.trim().toLowerCase()
  if (!q) return enrollments.value
  return enrollments.value.filter(e =>
    `${e.staff?.full_name ?? ''} ${e.staff?.email ?? ''} ${e.enrollee_id ?? ''} ${e.plan_name ?? ''} ${e.provider?.name ?? ''}`
      .toLowerCase()
      .includes(q)
  )
})

function blankEnrollment() {
  return {
    staff_id: '',
    provider_id: '',
    enrollee_id: '',
    plan_name: '',
    effective_date: '',
    notes: ''
  }
}

function openNewEnrollment() { enrollmentEditing.value = blankEnrollment() }
function openEditEnrollment(row: any) {
  enrollmentEditing.value = {
    id: row.id,
    staff_id: row.staff_id,
    provider_id: row.provider_id ?? '',
    enrollee_id: row.enrollee_id ?? '',
    plan_name: row.plan_name ?? '',
    effective_date: row.effective_date ?? '',
    notes: row.notes ?? ''
  }
}

async function saveEnrollment() {
  if (!enrollmentEditing.value) return
  if (!enrollmentEditing.value.staff_id) { toast.error('Pick a staff member'); return }
  enrollmentSaving.value = true
  try {
    const payload: any = {
      staff_id: enrollmentEditing.value.staff_id,
      provider_id: enrollmentEditing.value.provider_id || null,
      enrollee_id: (enrollmentEditing.value.enrollee_id ?? '').trim(),
      plan_name: (enrollmentEditing.value.plan_name ?? '').trim(),
      effective_date: enrollmentEditing.value.effective_date || null,
      notes: enrollmentEditing.value.notes ?? '',
      updated_at: new Date().toISOString()
    }
    if (enrollmentEditing.value.id) {
      const { error } = await supabase.from('staff_hmo_enrollments').update(payload).eq('id', enrollmentEditing.value.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from('staff_hmo_enrollments').insert(payload)
      if (error) throw error
    }
    auditLog({ action: enrollmentEditing.value.id ? 'update' : 'create', target_type: 'hmo_enrollment', target_label: staffOptions.value.find(s => s.id === payload.staff_id)?.full_name ?? payload.staff_id })
    toast.success('Enrollment saved')
    enrollmentEditing.value = null
    await loadEnrollments()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  } finally {
    enrollmentSaving.value = false
  }
}

async function removeEnrollment(row: any) {
  const ok = await toast.confirm({ title: 'Remove enrollment', message: `Remove HMO enrollment for ${row.staff?.full_name ?? 'this staff member'}?`, variant: 'danger', confirmLabel: 'Remove' })
  if (!ok) return
  try {
    const { error } = await supabase.from('staff_hmo_enrollments').delete().eq('id', row.id)
    if (error) throw error
    auditLog({ action: 'delete', target_type: 'hmo_enrollment', target_id: row.id, target_label: row.staff?.full_name ?? '' })
    toast.success('Enrollment removed')
    await loadEnrollments()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  }
}

async function remove(row: any) {
  const ok = await toast.confirm({ title: 'Delete provider', message: `Delete "${row.name}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('hmo_providers').delete().eq('id', row.id)
    if (error) throw error
    auditLog({ action: 'delete', target_type: 'hmo_provider', target_id: row.id, target_label: row.name })
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

    <header class="mt-10 mb-4 flex items-center justify-between flex-wrap gap-3">
      <div>
        <h2 class="text-xl font-semibold text-slate-900">Staff enrollments</h2>
        <p class="text-sm text-slate-500 mt-1">Set the enrollee ID and plan for each member of staff.</p>
      </div>
      <div class="flex items-center gap-2">
        <input v-model="enrollmentSearch" type="search" placeholder="Search..." class="text-sm border border-slate-200 rounded-lg px-3 py-2 w-56" />
        <button type="button" @click="openBulk" class="text-sm font-semibold px-4 py-2 rounded-lg border border-slate-200 text-slate-800 hover:bg-slate-50">Bulk upload</button>
        <button type="button" @click="openNewEnrollment" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">Add enrollment</button>
      </div>
    </header>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <div v-if="enrollmentsLoading" class="p-5 text-sm text-slate-500">Loading enrollments...</div>
      <div v-else-if="!filteredEnrollments.length" class="p-5 text-sm text-slate-500">No staff enrollments yet.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Staff</th>
            <th class="text-left px-5 py-2">Provider</th>
            <th class="text-left px-5 py-2">Enrollee ID</th>
            <th class="text-left px-5 py-2">Plan</th>
            <th class="text-left px-5 py-2">Effective</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in filteredEnrollments" :key="e.id" class="border-t border-slate-100 align-top">
            <td class="px-5 py-3">
              <div class="font-medium text-slate-900">{{ e.staff?.full_name ?? '—' }}</div>
              <div class="text-xs text-slate-500">{{ e.staff?.role ?? '' }}</div>
            </td>
            <td class="px-5 py-3 text-slate-700">{{ e.provider?.name ?? '—' }}</td>
            <td class="px-5 py-3 font-mono text-xs">{{ e.enrollee_id || '—' }}</td>
            <td class="px-5 py-3">{{ e.plan_name || '—' }}</td>
            <td class="px-5 py-3 text-slate-600 text-xs">{{ e.effective_date ?? '—' }}</td>
            <td class="px-5 py-3 text-right space-x-3 whitespace-nowrap">
              <button type="button" @click="openEditEnrollment(e)" class="text-xs font-semibold text-slate-700">Edit</button>
              <button type="button" @click="removeEnrollment(e)" class="text-xs font-semibold text-rose-600">Remove</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <div v-if="bulkOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="bulkOpen = false">
      <div class="bg-white rounded-2xl max-w-3xl w-full max-h-[90vh] overflow-y-auto shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200 flex items-center justify-between">
          <h3 class="text-base font-semibold text-slate-900">Bulk upload HMO enrollments</h3>
          <button type="button" @click="bulkOpen = false" class="text-slate-400 hover:text-slate-700 text-xl leading-none">&times;</button>
        </header>
        <div class="p-6 space-y-4">
          <p class="text-sm text-slate-600">
            Upload a CSV with columns: <code class="px-1 rounded bg-slate-100 text-xs">email</code>,
            <code class="px-1 rounded bg-slate-100 text-xs">enrollee_id</code>,
            <code class="px-1 rounded bg-slate-100 text-xs">plan_name</code>,
            <code class="px-1 rounded bg-slate-100 text-xs">provider_name</code> (optional),
            <code class="px-1 rounded bg-slate-100 text-xs">effective_date</code> (optional, YYYY-MM-DD).
            Emails are matched against active staff. Existing enrollments are updated; new ones are created.
          </p>

          <div class="flex flex-wrap gap-2">
            <label class="text-sm font-semibold px-3 py-2 rounded-lg border border-slate-200 hover:bg-slate-50 cursor-pointer">
              <input type="file" accept=".csv,text/csv" class="hidden" @change="onBulkFile" />
              Choose CSV file
            </label>
            <button type="button" @click="bulkUseSample" class="text-sm font-semibold px-3 py-2 rounded-lg border border-slate-200 hover:bg-slate-50">Use sample</button>
          </div>

          <textarea
            v-model="bulkCsv"
            rows="8"
            placeholder="Paste CSV content here..."
            class="w-full border border-slate-300 rounded-lg px-3 py-2 text-xs font-mono"
          ></textarea>

          <div v-if="bulkParsed.errors.length" class="rounded-lg border border-rose-200 bg-rose-50 p-3 text-xs text-rose-800 space-y-0.5">
            <div v-for="(err, i) in bulkParsed.errors" :key="i">{{ err }}</div>
          </div>

          <div v-if="bulkParsed.rows.length" class="border border-slate-200 rounded-lg overflow-hidden">
            <div class="px-3 py-2 bg-slate-50 text-xs font-semibold text-slate-600 uppercase tracking-wide">
              Preview ({{ bulkParsed.rows.length }} row{{ bulkParsed.rows.length === 1 ? '' : 's' }})
            </div>
            <table class="w-full text-xs">
              <thead class="bg-white text-slate-500">
                <tr>
                  <th class="text-left px-3 py-2">Email</th>
                  <th class="text-left px-3 py-2">Enrollee ID</th>
                  <th class="text-left px-3 py-2">Plan</th>
                  <th class="text-left px-3 py-2">Provider</th>
                  <th class="text-left px-3 py-2">Effective</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(r, i) in bulkParsed.rows.slice(0, 50)" :key="i" class="border-t border-slate-100">
                  <td class="px-3 py-1.5">{{ r.email }}</td>
                  <td class="px-3 py-1.5 font-mono">{{ r.enrollee_id }}</td>
                  <td class="px-3 py-1.5">{{ r.plan_name }}</td>
                  <td class="px-3 py-1.5">{{ r.provider_name }}</td>
                  <td class="px-3 py-1.5">{{ r.effective_date }}</td>
                </tr>
              </tbody>
            </table>
            <div v-if="bulkParsed.rows.length > 50" class="px-3 py-2 text-xs text-slate-500 bg-slate-50">+ {{ bulkParsed.rows.length - 50 }} more...</div>
          </div>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="bulkOpen = false" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button
            type="button"
            @click="runBulkImport"
            :disabled="bulkImporting || !bulkParsed.rows.length"
            class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white disabled:opacity-60"
          >
            {{ bulkImporting ? 'Importing...' : `Import ${bulkParsed.rows.length} row${bulkParsed.rows.length === 1 ? '' : 's'}` }}
          </button>
        </footer>
      </div>
    </div>

    <div v-if="enrollmentEditing" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="enrollmentEditing = null">
      <div class="bg-white rounded-2xl max-w-lg w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ enrollmentEditing.id ? 'Edit' : 'New' }} staff HMO enrollment</h3>
        </header>
        <div class="p-6 grid grid-cols-2 gap-4">
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Staff</span>
            <select v-model="enrollmentEditing.staff_id" :disabled="!!enrollmentEditing.id" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
              <option value="">Select staff...</option>
              <option v-for="s in staffOptions" :key="s.id" :value="s.id">{{ s.full_name }}{{ s.email ? ' — ' + s.email : '' }}</option>
            </select>
          </label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Provider</span>
            <select v-model="enrollmentEditing.provider_id" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm">
              <option value="">Not assigned</option>
              <option v-for="p in items" :key="p.id" :value="p.id">{{ p.name }}</option>
            </select>
          </label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Enrollee ID</span>
            <input v-model="enrollmentEditing.enrollee_id" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm font-mono" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Plan</span>
            <input v-model="enrollmentEditing.plan_name" placeholder="e.g. Gold" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Effective date</span>
            <input v-model="enrollmentEditing.effective_date" type="date" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Notes</span>
            <textarea v-model="enrollmentEditing.notes" rows="2" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea></label>
        </div>
        <footer class="px-6 py-4 border-t border-slate-200 flex justify-end gap-2">
          <button type="button" @click="enrollmentEditing = null" class="text-sm px-3 py-2 rounded-lg hover:bg-slate-100">Cancel</button>
          <button type="button" @click="saveEnrollment" :disabled="enrollmentSaving" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">
            {{ enrollmentSaving ? 'Saving...' : 'Save' }}
          </button>
        </footer>
      </div>
    </div>

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
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Hospital directory link (Excel / Google Sheet)</span>
            <input v-model="editing.directory_url" type="url" placeholder="https://docs.google.com/spreadsheets/..." class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" />
            <span class="block text-[11px] text-slate-500 mt-1">Staff are redirected to this link to see hospitals under this provider.</span>
          </label>
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
