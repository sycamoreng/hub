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

async function load() {
  loading.value = true
  try {
    const { data } = await supabase
      .from('learning_budgets')
      .select('*')
      .order('level')
    items.value = data ?? []
  } finally {
    loading.value = false
  }
}
load()

function blank() {
  return { level: '', annual_amount: 0, currency: 'NGN', notes: '', is_active: true }
}

function openNew() { editing.value = blank() }
function openEdit(row: any) { editing.value = { ...row } }

function formatNGN(n: number, currency = 'NGN') {
  try {
    return new Intl.NumberFormat('en-NG', { style: 'currency', currency, maximumFractionDigits: 0 }).format(Number(n) || 0)
  } catch {
    return `${currency} ${Number(n).toLocaleString()}`
  }
}

async function save() {
  if (!editing.value) return
  if (!editing.value.level?.trim()) { toast.error('Level is required'); return }
  saving.value = true
  try {
    const payload = {
      level: editing.value.level.trim(),
      annual_amount: Number(editing.value.annual_amount) || 0,
      currency: (editing.value.currency || 'NGN').trim().toUpperCase(),
      notes: editing.value.notes ?? '',
      is_active: !!editing.value.is_active,
      updated_at: new Date().toISOString()
    }
    if (editing.value.id) {
      const { error } = await supabase.from('learning_budgets').update(payload).eq('id', editing.value.id)
      if (error) throw error
    } else {
      const { error } = await supabase.from('learning_budgets').insert(payload)
      if (error) throw error
    }
    auditLog({ action: editing.value.id ? 'update' : 'create', target_type: 'learning_budget', target_label: payload.level })
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
  const ok = await toast.confirm({ title: 'Delete budget', message: `Delete budget for "${row.level}"?`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try {
    const { error } = await supabase.from('learning_budgets').delete().eq('id', row.id)
    if (error) throw error
    auditLog({ action: 'delete', target_type: 'learning_budget', target_id: row.id, target_label: row.level })
    toast.success('Deleted')
    await load()
  } catch (e: any) {
    toast.error(e.message ?? 'Failed')
  }
}
</script>

<template>
  <div class="max-w-4xl">
    <header class="mb-6 flex items-center justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold text-slate-900">Learning budgets</h1>
        <p class="text-sm text-slate-500 mt-1">Set the annual learning &amp; development budget per staff level.</p>
      </div>
      <button type="button" @click="openNew" class="text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white">New level budget</button>
    </header>

    <section class="bg-white border border-slate-200 rounded-xl overflow-hidden">
      <div v-if="loading" class="p-5 text-sm text-slate-500">Loading...</div>
      <div v-else-if="!items.length" class="p-5 text-sm text-slate-500">No budgets defined yet.</div>
      <table v-else class="w-full text-sm">
        <thead class="bg-slate-50 text-slate-500 text-xs uppercase tracking-wide">
          <tr>
            <th class="text-left px-5 py-2">Level</th>
            <th class="text-left px-5 py-2">Annual amount</th>
            <th class="text-left px-5 py-2">Active</th>
            <th class="text-left px-5 py-2">Notes</th>
            <th class="text-right px-5 py-2"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in items" :key="r.id" class="border-t border-slate-100 align-top">
            <td class="px-5 py-3 font-medium text-slate-900">{{ r.level }}</td>
            <td class="px-5 py-3 text-slate-700">{{ formatNGN(r.annual_amount, r.currency) }}</td>
            <td class="px-5 py-3">{{ r.is_active ? 'Yes' : 'No' }}</td>
            <td class="px-5 py-3 text-slate-500 text-xs whitespace-pre-line">{{ r.notes || '—' }}</td>
            <td class="px-5 py-3 text-right space-x-3 whitespace-nowrap">
              <button type="button" @click="openEdit(r)" class="text-xs font-semibold text-slate-700">Edit</button>
              <button type="button" @click="remove(r)" class="text-xs font-semibold text-rose-600">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>
    </section>

    <div v-if="editing" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="editing = null">
      <div class="bg-white rounded-2xl max-w-md w-full shadow-xl">
        <header class="px-6 py-4 border-b border-slate-200">
          <h3 class="text-base font-semibold text-slate-900">{{ editing.id ? 'Edit' : 'New' }} learning budget</h3>
        </header>
        <div class="p-6 grid grid-cols-2 gap-4">
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Level</span>
            <input v-model="editing.level" placeholder="e.g. Analyst, Manager, Director" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Annual amount</span>
            <input v-model.number="editing.annual_amount" type="number" min="0" step="1000" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block"><span class="text-xs font-medium text-slate-600">Currency</span>
            <input v-model="editing.currency" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm" /></label>
          <label class="block col-span-2"><span class="text-xs font-medium text-slate-600">Notes</span>
            <textarea v-model="editing.notes" rows="3" class="mt-1 w-full border border-slate-300 rounded-lg px-3 py-2 text-sm"></textarea></label>
          <label class="inline-flex items-center gap-2 text-sm col-span-2">
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
