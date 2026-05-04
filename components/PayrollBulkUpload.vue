<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const props = defineProps<{ open: boolean }>()
const emit = defineEmits<{ (e: 'close'): void; (e: 'imported'): void }>()

const supabase = useSupabase()
const toast = useToast()

const csv = ref('')
const fileInput = ref<HTMLInputElement | null>(null)
const parsed = ref<{ rows: any[], errors: string[] }>({ rows: [], errors: [] })
const importing = ref(false)

const REQUIRED = ['full_name', 'email']
const NUMERIC_FIELDS = ['pay_basic','pay_housing','pay_transport','pay_utility','pay_meal','pay_leave','pay_other']
const HEADERS = [
  'full_name','email','grade','job_title','tin','bank_name','bank_account',
  'pfa_name','pfa_pin','nhf_enabled','is_active',
  ...NUMERIC_FIELDS
]

const sample = `full_name,email,grade,job_title,pay_basic,pay_housing,pay_transport,pay_utility,pay_meal,pay_leave,pay_other,nhf_enabled,is_active,bank_name,bank_account,tin,pfa_name,pfa_pin
Ada Lovelace,ada@sycamore.ng,L3,Engineer,400000,120000,60000,20000,15000,30000,0,false,true,GTBank,0123456789,12345678-0001,Stanbic IBTC PFA,PEN100000001
Ken Saro-Wiwa,ken@sycamore.ng,L4,Senior Engineer,550000,150000,80000,25000,20000,45000,0,true,true,Access Bank,0987654321,87654321-0001,ARM Pensions,PEN100000002`

function parseCsv(text: string) {
  const lines = text.trim().split(/\r?\n/).filter(l => l.trim().length > 0)
  if (lines.length < 2) return { rows: [], errors: ['Need at least a header row and one data row.'] }
  const header = parseLine(lines[0]).map(h => h.trim().toLowerCase())
  const missing = REQUIRED.filter(r => !header.includes(r))
  if (missing.length) return { rows: [], errors: [`Missing required columns: ${missing.join(', ')}`] }
  const rows: any[] = []
  const errors: string[] = []
  for (let i = 1; i < lines.length; i++) {
    const cells = parseLine(lines[i])
    const row: any = {}
    header.forEach((h, idx) => { row[h] = (cells[idx] ?? '').trim() })
    if (!row.full_name || !row.email) { errors.push(`Row ${i + 1}: missing full_name or email`); continue }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(row.email)) { errors.push(`Row ${i + 1}: invalid email "${row.email}"`); continue }
    for (const n of NUMERIC_FIELDS) {
      if (row[n] === undefined || row[n] === '') { row[n] = 0; continue }
      const v = Number(row[n])
      if (!isFinite(v) || v < 0) { errors.push(`Row ${i + 1}: invalid number for ${n}: "${row[n]}"`); row[n] = 0 }
      else row[n] = v
    }
    row.nhf_enabled = parseBool(row.nhf_enabled, false)
    row.is_active = parseBool(row.is_active, true)
    row.email = row.email.toLowerCase()
    rows.push(row)
  }
  return { rows, errors }
}

function parseLine(line: string): string[] {
  const out: string[] = []
  let cur = ''
  let inQuote = false
  for (let i = 0; i < line.length; i++) {
    const c = line[i]
    if (inQuote) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++ }
      else if (c === '"') inQuote = false
      else cur += c
    } else {
      if (c === '"') inQuote = true
      else if (c === ',') { out.push(cur); cur = '' }
      else cur += c
    }
  }
  out.push(cur)
  return out
}

function parseBool(v: any, fallback: boolean) {
  if (v === undefined || v === '' || v === null) return fallback
  const s = String(v).trim().toLowerCase()
  if (['true','yes','y','1'].includes(s)) return true
  if (['false','no','n','0'].includes(s)) return false
  return fallback
}

watch(csv, (v) => {
  if (!v.trim()) { parsed.value = { rows: [], errors: [] }; return }
  parsed.value = parseCsv(v)
})

async function pickFile(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  csv.value = await file.text()
}

function useSample() { csv.value = sample }

async function doImport() {
  if (parsed.value.rows.length === 0) return
  importing.value = true
  try {
    const payload = parsed.value.rows.map(r => ({
      full_name: r.full_name,
      email: r.email,
      grade: r.grade || '',
      job_title: r.job_title || '',
      tin: r.tin || '',
      bank_name: r.bank_name || '',
      bank_account: r.bank_account || '',
      pfa_name: r.pfa_name || '',
      pfa_pin: r.pfa_pin || '',
      pay_basic: r.pay_basic,
      pay_housing: r.pay_housing,
      pay_transport: r.pay_transport,
      pay_utility: r.pay_utility,
      pay_meal: r.pay_meal,
      pay_leave: r.pay_leave,
      pay_other: r.pay_other,
      nhf_enabled: r.nhf_enabled,
      is_active: r.is_active,
      updated_at: new Date().toISOString()
    }))

    const emails = payload.map(p => p.email)
    const { data: existing } = await supabase.from('payroll_employees').select('id, email').in('email', emails)
    const existingMap = new Map((existing ?? []).map(e => [e.email, e.id]))

    const inserts = payload.filter(p => !existingMap.has(p.email))
    const updates = payload.filter(p => existingMap.has(p.email))

    if (inserts.length) {
      const { error } = await supabase.from('payroll_employees').insert(inserts)
      if (error) throw error
    }
    for (const u of updates) {
      const id = existingMap.get(u.email)
      const { error } = await supabase.from('payroll_employees').update(u).eq('id', id!)
      if (error) throw error
    }

    // try to link staff_id by email
    const { data: staffMatches } = await supabase.from('staff_members').select('id, email').in('email', emails)
    const staffByEmail = new Map((staffMatches ?? []).map(s => [s.email.toLowerCase(), s.id]))
    for (const p of payload) {
      const sid = staffByEmail.get(p.email)
      if (sid) await supabase.from('payroll_employees').update({ staff_id: sid }).eq('email', p.email)
    }

    toast.success(`Imported ${payload.length} employees (${inserts.length} new, ${updates.length} updated)`)
    emit('imported')
    emit('close')
    csv.value = ''
  } catch (e: any) { toast.error(e.message ?? 'Import failed') }
  finally { importing.value = false }
}
</script>

<template>
  <div v-if="props.open" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40" @click.self="emit('close')">
    <div class="bg-white rounded-2xl max-w-4xl w-full max-h-[90vh] overflow-y-auto shadow-xl">
      <header class="px-6 py-4 border-b border-slate-200 flex items-center justify-between">
        <div>
          <h3 class="text-base font-semibold text-slate-900">Bulk upload payroll employees</h3>
          <p class="text-xs text-slate-500">Paste a CSV or upload a file. Rows are upserted by email.</p>
        </div>
        <button type="button" @click="emit('close')" class="text-slate-400 hover:text-slate-600">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z"/></svg>
        </button>
      </header>

      <div class="p-6 space-y-4">
        <section class="bg-slate-50 border border-slate-200 rounded-lg p-4 text-xs text-slate-600">
          <div class="font-semibold text-slate-900 mb-1">Expected columns</div>
          <code class="block text-[11px] text-slate-700 break-all">{{ HEADERS.join(', ') }}</code>
          <div class="mt-2">Required: <strong>full_name</strong>, <strong>email</strong>. Numeric fields default to 0. Booleans accept true/false/yes/no/1/0.</div>
          <button type="button" @click="useSample" class="mt-2 text-sycamore-700 font-medium">Load sample CSV</button>
        </section>

        <div class="flex items-center gap-3">
          <input ref="fileInput" type="file" accept=".csv,text/csv,text/plain" @change="pickFile" class="text-sm" />
        </div>

        <textarea
          v-model="csv"
          rows="8"
          placeholder="Paste CSV here..."
          class="w-full border border-slate-300 rounded-md px-3 py-2 font-mono text-xs"
        />

        <div v-if="parsed.errors.length" class="bg-rose-50 border border-rose-200 rounded-md p-3 text-xs text-rose-800 space-y-1">
          <div v-for="(err, i) in parsed.errors" :key="i">{{ err }}</div>
        </div>

        <section v-if="parsed.rows.length" class="border border-slate-200 rounded-lg overflow-hidden">
          <header class="px-4 py-2 bg-slate-50 text-xs font-semibold text-slate-600">Preview &middot; {{ parsed.rows.length }} row(s)</header>
          <div class="max-h-64 overflow-auto">
            <table class="w-full text-xs">
              <thead class="bg-slate-50 text-slate-500 uppercase tracking-wide">
                <tr>
                  <th class="text-left px-3 py-2">Name</th>
                  <th class="text-left px-3 py-2">Email</th>
                  <th class="text-left px-3 py-2">Grade</th>
                  <th class="text-right px-3 py-2">Basic</th>
                  <th class="text-right px-3 py-2">Housing</th>
                  <th class="text-right px-3 py-2">Transport</th>
                  <th class="text-left px-3 py-2">NHF</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(r, i) in parsed.rows" :key="i" class="border-t border-slate-100">
                  <td class="px-3 py-1.5">{{ r.full_name }}</td>
                  <td class="px-3 py-1.5">{{ r.email }}</td>
                  <td class="px-3 py-1.5">{{ r.grade }}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums">{{ r.pay_basic.toLocaleString() }}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums">{{ r.pay_housing.toLocaleString() }}</td>
                  <td class="px-3 py-1.5 text-right tabular-nums">{{ r.pay_transport.toLocaleString() }}</td>
                  <td class="px-3 py-1.5">{{ r.nhf_enabled ? 'Yes' : 'No' }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <footer class="px-6 py-4 border-t border-slate-200 flex items-center justify-end gap-2">
        <button type="button" @click="emit('close')" class="px-4 py-2 text-sm text-slate-600 hover:text-slate-900">Cancel</button>
        <button type="button" @click="doImport" :disabled="importing || parsed.rows.length === 0"
          class="px-4 py-2 bg-sycamore-600 hover:bg-sycamore-700 text-white rounded-md text-sm font-medium disabled:opacity-50">
          {{ importing ? 'Importing...' : `Import ${parsed.rows.length || ''}` }}
        </button>
      </footer>
    </div>
  </div>
</template>
