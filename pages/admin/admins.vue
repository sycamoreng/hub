<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const toast = useToast()
import { useSupabase } from '~/utils/supabase'
import type { CrudAction, SectionPermissions } from '~/composables/useAuth'

interface AdminRow {
  email: string
  role: 'super_admin' | 'admin'
  display_name: string
  title: string
  function: string
  permissions: Record<string, Partial<SectionPermissions>>
  sections: string[]
  added_by: string
  created_at: string
}

interface RolePreset {
  id: string
  name: string
  description: string
  permissions: Record<string, Partial<SectionPermissions>>
  is_default: boolean
}

const SECTIONS = [
  { key: 'onboarding', label: 'Onboarding' },
  { key: 'products', label: 'Products' },
  { key: 'technology', label: 'Technology' },
  { key: 'chatbot', label: 'Chatbot' },
  { key: 'announcements', label: 'Announcements' },
  { key: 'events', label: 'Events & Holidays' },
  { key: 'policies', label: 'Policies' },
  { key: 'staff', label: 'Staff' },
  { key: 'leadership', label: 'Leadership' },
  { key: 'departments', label: 'Departments' },
  { key: 'locations', label: 'Locations' },
  { key: 'contacts', label: 'Key Contacts' },
  { key: 'communication', label: 'Communication' },
  { key: 'branding', label: 'Branding' },
  { key: 'benefits', label: 'Benefits' },
  { key: 'company', label: 'Company Info' }
]
const ACTIONS: CrudAction[] = ['create', 'read', 'update', 'delete']

const supabase = useSupabase()
const { profile } = useAuth()

const admins = ref<AdminRow[]>([])
const presets = ref<RolePreset[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const saving = ref(false)

const showForm = ref(false)
const editingEmail = ref<string | null>(null)
const form = ref({
  email: '',
  role: 'admin' as 'admin' | 'super_admin',
  display_name: '',
  title: '',
  function: '',
  permissions: {} as Record<string, Partial<SectionPermissions>>,
  presetId: ''
})

async function load() {
  loading.value = true
  error.value = null
  const [adminsRes, presetsRes] = await Promise.all([
    supabase.from('admin_users').select('*').order('role', { ascending: true }).order('email', { ascending: true }),
    supabase.from('admin_role_presets').select('*').order('is_default', { ascending: false }).order('name')
  ])
  if (adminsRes.error) error.value = adminsRes.error.message
  else admins.value = (adminsRes.data as AdminRow[]) ?? []
  if (!presetsRes.error) presets.value = (presetsRes.data as RolePreset[]) ?? []
  loading.value = false
}

onMounted(load)

function emptyPermissions(): Record<string, Partial<SectionPermissions>> {
  return {}
}

function resetForm() {
  form.value = { email: '', role: 'admin', display_name: '', title: '', function: '', permissions: emptyPermissions(), presetId: '' }
  editingEmail.value = null
}

function startCreate() {
  resetForm()
  showForm.value = true
}

function startEdit(row: AdminRow) {
  editingEmail.value = row.email
  form.value = {
    email: row.email,
    role: row.role,
    display_name: row.display_name || '',
    title: row.title || '',
    function: row.function || '',
    permissions: JSON.parse(JSON.stringify(row.permissions || {})),
    presetId: ''
  }
  showForm.value = true
}

function permissionFor(section: string): Partial<SectionPermissions> {
  return form.value.permissions[section] || {}
}

function togglePermission(section: string, action: CrudAction) {
  const current = { ...permissionFor(section) }
  current[action] = !current[action]
  const allFalse = ACTIONS.every(a => !current[a])
  if (allFalse) {
    delete form.value.permissions[section]
  } else {
    form.value.permissions[section] = current
  }
}

function setSectionFull(section: string) {
  form.value.permissions[section] = { create: true, read: true, update: true, delete: true }
}

function clearSection(section: string) {
  delete form.value.permissions[section]
}

function applyPreset(presetId: string) {
  form.value.presetId = presetId
  if (!presetId) return
  const p = presets.value.find(x => x.id === presetId)
  if (!p) return
  if (p.name === 'Super Admin') {
    form.value.role = 'super_admin'
    form.value.permissions = emptyPermissions()
  } else {
    form.value.role = 'admin'
    form.value.permissions = JSON.parse(JSON.stringify(p.permissions || {}))
  }
}

async function save() {
  error.value = null
  const email = form.value.email.trim().toLowerCase()
  if (!email || !email.includes('@')) {
    error.value = 'A valid email is required.'
    return
  }
  saving.value = true
  const permissions = form.value.role === 'super_admin' ? {} : form.value.permissions
  const sections = Object.keys(permissions || {})
  const payload = {
    email,
    role: form.value.role,
    display_name: form.value.display_name.trim(),
    title: form.value.title.trim(),
    function: form.value.function.trim(),
    permissions,
    sections,
    added_by: profile.value?.email || '',
    updated_at: new Date().toISOString()
  }
  const { error: e } = editingEmail.value
    ? await supabase.from('admin_users').update(payload).eq('email', editingEmail.value)
    : await supabase.from('admin_users').insert(payload)
  saving.value = false
  if (e) {
    error.value = e.message
    return
  }
  showForm.value = false
  resetForm()
  await load()
}

async function removeAdmin(row: AdminRow) {
  if (row.email === profile.value?.email) {
    error.value = 'You cannot remove your own admin access.'
    return
  }
  if (row.role === 'super_admin') {
    const remaining = admins.value.filter(a => a.role === 'super_admin').length
    if (remaining <= 1) {
      error.value = 'Cannot remove the last super-admin.'
      return
    }
  }
  const ok = await toast.confirm({ title: 'Delete', message: `Remove admin access for ${row.email}?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  const { error: e } = await supabase.from('admin_users').delete().eq('email', row.email)
  if (e) {
    error.value = e.message
    return
  }
  await load()
}

function summarisePermissions(perms: Record<string, Partial<SectionPermissions>> | null): string {
  if (!perms) return 'None'
  const keys = Object.keys(perms)
  if (!keys.length) return 'None'
  return keys
    .map(k => {
      const label = SECTIONS.find(s => s.key === k)?.label || k
      const enabled = ACTIONS.filter(a => perms[k]?.[a]).map(a => a[0].toUpperCase()).join('')
      return `${label} (${enabled || '-'})`
    })
    .join(', ')
}

function sectionPermissionCount(section: string) {
  return ACTIONS.filter(a => permissionFor(section)[a]).length
}
</script>

<template>
  <div class="max-w-6xl">
    <div class="flex items-start justify-between gap-4 mb-8">
      <div>
        <h1 class="section-title">Admin Access</h1>
        <p class="section-subtitle">Grant admin permissions by department role and fine-tune CRUD rights per section.</p>
      </div>
      <button @click="startCreate" class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-semibold hover:bg-sycamore-700 inline-flex items-center gap-2">
        <SidebarIcon name="plus" /> Add admin
      </button>
    </div>

    <div v-if="error" class="mb-4 p-3 rounded-lg bg-rose-50 border border-rose-200 text-rose-700 text-sm">{{ error }}</div>

    <div v-if="showForm" class="card p-6 mb-6">
      <h2 class="font-bold text-slate-900 mb-4">{{ editingEmail ? 'Edit admin' : 'New admin' }}</h2>

      <div class="grid sm:grid-cols-2 gap-4">
        <div>
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Email</label>
          <input
            v-model="form.email"
            type="email"
            :disabled="!!editingEmail"
            placeholder="user@sycamore.ng"
            class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500 disabled:bg-slate-50"
          />
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Apply role preset</label>
          <select :value="form.presetId" @change="(e) => applyPreset((e.target as HTMLSelectElement).value)" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500">
            <option value="">Custom (no preset)</option>
            <option v-for="p in presets" :key="p.id" :value="p.id">{{ p.name }}</option>
          </select>
          <p v-if="form.presetId" class="text-xs text-slate-500 mt-1">{{ presets.find(p => p.id === form.presetId)?.description }}</p>
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Display name</label>
          <input v-model="form.display_name" type="text" placeholder="Jane Doe" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Title</label>
          <input v-model="form.title" type="text" placeholder="Head of HR" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Function / department</label>
          <input v-model="form.function" type="text" placeholder="Human Resources" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500" />
        </div>
        <div>
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Role</label>
          <select v-model="form.role" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500">
            <option value="admin">Admin (granular permissions)</option>
            <option value="super_admin">Super admin (full access)</option>
          </select>
        </div>
      </div>

      <div v-if="form.role === 'admin'" class="mt-6">
        <div class="flex items-center justify-between mb-3">
          <label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Section permissions</label>
          <span class="text-xs text-slate-400">C = Create &middot; R = Read &middot; U = Update &middot; D = Delete</span>
        </div>
        <div class="overflow-x-auto rounded-lg border border-slate-200">
          <table class="w-full text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="text-left p-3">Section</th>
                <th v-for="a in ACTIONS" :key="a" class="text-center p-3 capitalize">{{ a }}</th>
                <th class="text-right p-3"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="s in SECTIONS" :key="s.key" class="border-t border-slate-100" :class="{ 'bg-sycamore-50/40': sectionPermissionCount(s.key) > 0 }">
                <td class="p-3 font-medium text-slate-700">{{ s.label }}</td>
                <td v-for="a in ACTIONS" :key="a" class="text-center p-3">
                  <input
                    type="checkbox"
                    :checked="!!permissionFor(s.key)[a]"
                    @change="togglePermission(s.key, a)"
                    class="accent-sycamore-600 w-4 h-4"
                  />
                </td>
                <td class="p-3 text-right whitespace-nowrap">
                  <button type="button" @click="setSectionFull(s.key)" class="text-xs text-sycamore-700 hover:underline mr-3">Full</button>
                  <button type="button" @click="clearSection(s.key)" class="text-xs text-slate-500 hover:underline">Clear</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <div v-else class="mt-4 p-3 rounded-lg bg-amber-50 border border-amber-200 text-sm text-amber-800">
        Super admins have full access to every section, including managing other admins and role presets.
      </div>

      <div class="flex items-center justify-end gap-3 mt-6">
        <button @click="showForm = false; resetForm()" class="px-4 py-2 rounded-lg border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50">Cancel</button>
        <button :disabled="saving" @click="save" class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-semibold hover:bg-sycamore-700 disabled:opacity-60">
          {{ saving ? 'Saving...' : (editingEmail ? 'Save changes' : 'Add admin') }}
        </button>
      </div>
    </div>

    <div class="card overflow-hidden">
      <div v-if="loading" class="p-10 text-center text-slate-500">Loading admins...</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
          <tr>
            <th class="text-left p-4">User</th>
            <th class="text-left p-4">Role</th>
            <th class="text-left p-4">Function</th>
            <th class="text-left p-4">Permissions</th>
            <th class="text-right p-4">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in admins" :key="row.email" class="border-t border-slate-100 align-top">
            <td class="p-4">
              <div class="font-semibold text-slate-900">{{ row.display_name || row.email.split('@')[0] }}</div>
              <div class="text-xs text-slate-500">{{ row.email }}</div>
              <div v-if="row.title" class="text-xs text-slate-400 mt-0.5">{{ row.title }}</div>
            </td>
            <td class="p-4">
              <span
                class="inline-flex px-2 py-1 rounded-full text-xs font-medium"
                :class="row.role === 'super_admin' ? 'bg-amber-50 text-amber-700' : 'bg-sycamore-50 text-sycamore-700'"
              >
                {{ row.role === 'super_admin' ? 'Super admin' : 'Admin' }}
              </span>
            </td>
            <td class="p-4 text-slate-600">{{ row.function || '-' }}</td>
            <td class="p-4 text-slate-600 max-w-md text-xs leading-relaxed">
              <span v-if="row.role === 'super_admin'" class="text-amber-700 font-medium">All sections, full CRUD</span>
              <span v-else>{{ summarisePermissions(row.permissions) }}</span>
            </td>
            <td class="p-4 text-right whitespace-nowrap">
              <button @click="startEdit(row)" class="text-sycamore-700 hover:underline text-xs font-semibold mr-3">Edit</button>
              <button
                @click="removeAdmin(row)"
                :disabled="row.email === profile?.email"
                class="text-rose-600 hover:underline text-xs font-semibold disabled:opacity-40 disabled:no-underline disabled:cursor-not-allowed"
              >
                Remove
              </button>
            </td>
          </tr>
          <tr v-if="!admins.length">
            <td colspan="5" class="p-10 text-center text-slate-500">No admins configured.</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="mt-10">
      <h2 class="text-lg font-bold text-slate-900 mb-1">Default role presets</h2>
      <p class="text-sm text-slate-500 mb-4">Pre-built permission templates for common departments. Apply them when adding or editing an admin.</p>
      <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <div v-for="p in presets" :key="p.id" class="card p-5">
          <div class="flex items-center justify-between mb-1">
            <div class="font-semibold text-slate-900">{{ p.name }}</div>
            <span v-if="p.is_default" class="text-[10px] px-2 py-0.5 rounded-full bg-slate-100 text-slate-500 uppercase tracking-wide">Default</span>
          </div>
          <p class="text-xs text-slate-500 mb-3">{{ p.description }}</p>
          <div class="text-xs text-slate-600 leading-relaxed">{{ summarisePermissions(p.permissions) }}</div>
        </div>
      </div>
    </div>
  </div>
</template>
