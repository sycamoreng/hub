<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'
import {
  usePerformance,
  CYCLE_STATUSES,
  OBJECTIVE_STATUSES,
  OBJECTIVE_CATEGORIES,
  FRAMEWORK_KINDS,
  REVIEWER_TYPES,
  REVIEWER_TYPE_LABELS,
  RECOGNITION_KINDS,
  RECOGNITION_KIND_LABELS,
  PIP_STATUSES,
  type PerformanceCycle,
  type PerformanceFramework,
  type PerformanceObjective,
  type PerformanceMeasure,
  type PerformanceReview,
  type PerformanceRecognition,
  type PerformanceImprovementPlan,
  type PerformanceImprovementCheckin,
  type ReviewerType,
  type FrameworkKind,
  type CycleStatus,
  type RecognitionKind,
  type PipStatus
} from '~/composables/usePerformance'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()
const {
  loadCycles, saveCycle, deleteCycle, setPrimaryCycle,
  loadFrameworks, saveFramework, deleteFramework,
  loadObjectives, loadMeasures, saveObjective, deleteObjective, saveMeasure, deleteMeasure,
  loadReviews, saveReview, deleteReview,
  loadRecognitions, saveRecognition, deleteRecognition,
  loadPips, savePip, deletePip, loadPipCheckins, saveCheckin, deleteCheckin
} = usePerformance()

const tab = ref<'dashboard' | 'cycles' | 'frameworks' | 'objectives' | 'appraisals' | 'calibration' | 'templates' | 'values' | 'reviews' | 'recognitions' | 'pips'>('dashboard')
const loading = ref(true)

const cycles = ref<PerformanceCycle[]>([])
const frameworks = ref<PerformanceFramework[]>([])
const staffMembers = ref<any[]>([])
const departments = ref<{ id: string; name: string }[]>([])
const objectives = ref<any[]>([])
const selectedCycleId = ref<string>('')
const selectedStaffId = ref<string>('')
const selectedDepartmentId = ref<string>('')
const selectedPaygroup = ref<string>('')
const showBulkUpload = ref(false)
const bulkObjectivesText = ref('')
const bulkUploading = ref(false)

const editingCycle = ref<Partial<PerformanceCycle> | null>(null)
const editingFramework = ref<Partial<PerformanceFramework> | null>(null)
const editingObjective = ref<(Partial<PerformanceObjective> & { _measures?: Partial<PerformanceMeasure>[] }) | null>(null)

const reviews = ref<any[]>([])
const reviewStatusFilter = ref<string>('')
const reviewTypeFilter = ref<string>('')
const editingReview = ref<Partial<PerformanceReview> & { reviewer_ids?: string[] } | null>(null)

const recognitions = ref<any[]>([])
const editingRecognition = ref<Partial<PerformanceRecognition> | null>(null)
const pips = ref<any[]>([])
const editingPip = ref<Partial<PerformanceImprovementPlan> | null>(null)
const expandedPipId = ref<string>('')
const pipCheckins = ref<PerformanceImprovementCheckin[]>([])
const editingCheckin = ref<Partial<PerformanceImprovementCheckin> | null>(null)

async function loadAll() {
  loading.value = true
  try {
    const [c, f, { data: sm }, { data: dep }] = await Promise.all([
      loadCycles(),
      loadFrameworks(),
      supabase.from('staff_members').select('id, full_name, email, role, department_id, paygroup, is_active').eq('is_active', true).order('full_name'),
      supabase.from('departments').select('id, name').order('name')
    ])
    cycles.value = c
    frameworks.value = f
    staffMembers.value = sm ?? []
    departments.value = dep ?? []
    if (!selectedCycleId.value) {
      const primary = c.find(x => x.is_primary) ?? c[0]
      selectedCycleId.value = primary?.id ?? ''
    }
    await reloadObjectives()
    await reloadReviews()
    await reloadRecognitions()
    await reloadPips()
  } finally {
    loading.value = false
  }
}

async function reloadRecognitions() {
  const opts: any = {}
  if (selectedCycleId.value) opts.cycleId = selectedCycleId.value
  if (selectedStaffId.value) opts.subjectStaffId = selectedStaffId.value
  recognitions.value = await loadRecognitions(opts)
}

async function reloadPips() {
  const opts: any = {}
  if (selectedStaffId.value) opts.subjectStaffId = selectedStaffId.value
  pips.value = await loadPips(opts)
}

async function reloadObjectives() {
  if (!selectedCycleId.value) { objectives.value = []; return }
  const all = await loadObjectives({
    cycleId: selectedCycleId.value,
    staffId: selectedStaffId.value || undefined
  })
  const staffIndex = new Map(staffMembers.value.map(s => [s.id, s]))
  objectives.value = all.filter((o: any) => {
    const s = staffIndex.get(o.staff_id)
    if (selectedDepartmentId.value && s?.department_id !== selectedDepartmentId.value) return false
    if (selectedPaygroup.value && (s?.paygroup ?? '') !== selectedPaygroup.value) return false
    return true
  })
}

const paygroupOptions = computed(() => {
  const set = new Set<string>()
  for (const s of staffMembers.value) {
    if (s.paygroup) set.add(s.paygroup)
  }
  return [...set].sort()
})

const filteredStaff = computed(() => {
  return staffMembers.value.filter(s => {
    if (selectedDepartmentId.value && s.department_id !== selectedDepartmentId.value) return false
    if (selectedPaygroup.value && (s.paygroup ?? '') !== selectedPaygroup.value) return false
    return true
  })
})

watch([selectedCycleId, selectedStaffId, selectedDepartmentId, selectedPaygroup], () => { reloadObjectives(); reloadReviews(); reloadRecognitions(); reloadPips() })
watch([reviewStatusFilter, reviewTypeFilter], reloadReviews)

onMounted(loadAll)

async function reloadReviews() {
  if (!selectedCycleId.value) { reviews.value = []; return }
  const opts: any = { cycleId: selectedCycleId.value }
  if (selectedStaffId.value) opts.subjectStaffId = selectedStaffId.value
  if (reviewStatusFilter.value) opts.status = reviewStatusFilter.value
  const list = await loadReviews(opts)
  reviews.value = reviewTypeFilter.value ? list.filter((r: any) => r.reviewer_type === reviewTypeFilter.value) : list
}

function startNewReview() {
  if (!selectedCycleId.value) {
    toast.push({ type: 'error', title: 'Pick a cycle first', message: 'Create or select a performance cycle.' })
    return
  }
  editingReview.value = {
    cycle_id: selectedCycleId.value,
    subject_staff_id: selectedStaffId.value || '',
    reviewer_staff_id: '',
    reviewer_type: 'peer',
    status: 'invited',
    anonymous: true,
    due_at: null,
    overall_comment: '',
    strengths: '',
    improvements: '',
    reviewer_ids: []
  }
}

async function submitReviewInvitations() {
  if (!editingReview.value) return
  const payload = editingReview.value
  if (!payload.cycle_id || !payload.subject_staff_id || !payload.reviewer_type) {
    toast.push({ type: 'error', title: 'Missing fields', message: 'Cycle, subject and reviewer type are required.' })
    return
  }
  try {
    if (payload.reviewer_type === 'self') {
      await saveReview({
        cycle_id: payload.cycle_id,
        subject_staff_id: payload.subject_staff_id,
        reviewer_staff_id: payload.subject_staff_id,
        reviewer_type: 'self',
        status: 'invited',
        anonymous: false,
        due_at: payload.due_at
      })
    } else {
      const ids = (payload.reviewer_ids && payload.reviewer_ids.length ? payload.reviewer_ids : (payload.reviewer_staff_id ? [payload.reviewer_staff_id] : []))
      if (!ids.length) throw new Error('Choose at least one reviewer')
      for (const rid of ids) {
        await saveReview({
          cycle_id: payload.cycle_id,
          subject_staff_id: payload.subject_staff_id,
          reviewer_staff_id: rid,
          reviewer_type: payload.reviewer_type,
          status: 'invited',
          anonymous: payload.anonymous,
          due_at: payload.due_at
        })
      }
    }
    auditLog({ action: 'create', target_type: 'performance_review', target_label: `${REVIEWER_TYPE_LABELS[payload.reviewer_type as ReviewerType]} for ${payload.subject_staff_id}` })
    toast.push({ type: 'success', title: 'Review invitations sent', message: REVIEWER_TYPE_LABELS[payload.reviewer_type as ReviewerType] })
    editingReview.value = null
    await reloadReviews()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not invite', message: e?.message ?? 'Unexpected error' })
  }
}

async function cancelReview(r: any) {
  const ok = await toast.confirm({
    title: 'Cancel review?',
    message: `Cancel this ${REVIEWER_TYPE_LABELS[r.reviewer_type as ReviewerType]} for ${r.subject?.full_name ?? 'this staff member'}?`,
    confirmLabel: 'Cancel review',
    cancelLabel: 'Keep',
    variant: 'danger'
  })
  if (!ok) return
  try {
    await saveReview({ id: r.id, status: 'cancelled' })
    auditLog({ action: 'cancel', target_type: 'performance_review', target_id: r.id, target_label: r.subject?.full_name })
    toast.push({ type: 'success', title: 'Review cancelled', message: r.subject?.full_name })
    await reloadReviews()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not cancel', message: e?.message ?? 'Unexpected error' })
  }
}

async function removeReview(r: any) {
  const ok = await toast.confirm({ title: 'Delete review?', message: 'All responses on this review will be lost.', confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deleteReview(r.id)
    auditLog({ action: 'delete', target_type: 'performance_review', target_id: r.id, target_label: r.subject?.full_name ?? '' })
    toast.push({ type: 'success', title: 'Review deleted', message: r.subject?.full_name ?? '' })
    await reloadReviews()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}

// --- cycles ---
function startNewCycle() {
  const now = new Date()
  const in6Months = new Date(now)
  in6Months.setMonth(in6Months.getMonth() + 6)
  editingCycle.value = {
    name: '',
    description: '',
    period_start: now.toISOString().slice(0, 10),
    period_end: in6Months.toISOString().slice(0, 10),
    status: 'draft',
    default_framework: 'okr',
    is_primary: false
  }
}

function editCycle(c: PerformanceCycle) {
  editingCycle.value = { ...c }
}

async function submitCycle() {
  if (!editingCycle.value || !editingCycle.value.name) return
  try {
    const isNew = !editingCycle.value.id
    await saveCycle(editingCycle.value)
    auditLog({ action: isNew ? 'create' : 'update', target_type: 'performance_cycle', target_label: editingCycle.value.name ?? '' })
    toast.push({ type: 'success', title: 'Cycle saved', message: editingCycle.value.name ?? '' })
    editingCycle.value = null
    await loadAll()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}

async function removeCycle(c: PerformanceCycle) {
  const ok = await toast.confirm({ title: 'Delete cycle?', message: `"${c.name}" and all objectives and measures under it will be removed.`, confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deleteCycle(c.id)
    auditLog({ action: 'delete', target_type: 'performance_cycle', target_id: c.id, target_label: c.name })
    toast.push({ type: 'success', title: 'Cycle deleted', message: c.name })
    if (selectedCycleId.value === c.id) selectedCycleId.value = ''
    await loadAll()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}

async function markPrimary(c: PerformanceCycle) {
  try {
    await setPrimaryCycle(c.id)
    auditLog({ action: 'set_primary', target_type: 'performance_cycle', target_id: c.id, target_label: c.name })
    toast.push({ type: 'success', title: 'Primary cycle set', message: c.name })
    await loadAll()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not update', message: e?.message ?? 'Unexpected error' })
  }
}

// --- frameworks ---
function startNewFramework() {
  editingFramework.value = {
    name: '',
    kind: 'okr',
    description: '',
    scoring_scale: { min: 1, max: 5, labels: ['Needs work', 'Below', 'Meets', 'Exceeds', 'Outstanding'] },
    is_active: true,
    sort_order: (frameworks.value.at(-1)?.sort_order ?? 0) + 10
  }
}
function editFramework(f: PerformanceFramework) { editingFramework.value = { ...f, scoring_scale: { ...f.scoring_scale, labels: [...(f.scoring_scale?.labels ?? [])] } } }
async function submitFramework() {
  if (!editingFramework.value?.name) return
  try {
    const isNew = !editingFramework.value.id
    await saveFramework(editingFramework.value)
    auditLog({ action: isNew ? 'create' : 'update', target_type: 'performance_framework', target_label: editingFramework.value.name ?? '' })
    toast.push({ type: 'success', title: 'Framework saved', message: editingFramework.value.name ?? '' })
    editingFramework.value = null
    await loadAll()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}
async function removeFramework(f: PerformanceFramework) {
  const ok = await toast.confirm({ title: 'Delete framework?', message: `"${f.name}" will be removed.`, confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deleteFramework(f.id)
    auditLog({ action: 'delete', target_type: 'performance_framework', target_id: f.id, target_label: f.name })
    toast.push({ type: 'success', title: 'Framework deleted', message: f.name })
    await loadAll()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}
function addScaleLabel() {
  if (!editingFramework.value?.scoring_scale) return
  const labels = [...(editingFramework.value.scoring_scale.labels ?? []), '']
  editingFramework.value.scoring_scale = { ...editingFramework.value.scoring_scale, labels, max: labels.length }
}
function removeScaleLabel(i: number) {
  if (!editingFramework.value?.scoring_scale) return
  const labels = (editingFramework.value.scoring_scale.labels ?? []).filter((_, idx) => idx !== i)
  editingFramework.value.scoring_scale = { ...editingFramework.value.scoring_scale, labels, max: Math.max(labels.length, 1) }
}

// --- objectives ---
function startNewObjective() {
  if (!selectedCycleId.value) {
    toast.push({ type: 'error', title: 'Pick a cycle first', message: 'Create or select a performance cycle.' })
    return
  }
  const cycle = cycles.value.find(c => c.id === selectedCycleId.value)
  const defaultKind: FrameworkKind = (cycle?.default_framework === 'mixed' ? 'okr' : (cycle?.default_framework as FrameworkKind)) || 'okr'
  const framework = frameworks.value.find(f => f.kind === defaultKind && f.is_active) ?? null
  editingObjective.value = {
    cycle_id: selectedCycleId.value,
    staff_id: selectedStaffId.value || '',
    framework_id: framework?.id ?? null,
    kind: defaultKind,
    title: '',
    description: '',
    category: 'business',
    weight: 0,
    target_value: '',
    status: 'draft',
    progress: 0,
    manager_notes: '',
    staff_notes: '',
    sort_order: objectives.value.length * 10,
    _measures: []
  }
}

async function editObjective(o: any) {
  const measures = await loadMeasures(o.id)
  editingObjective.value = { ...o, _measures: measures.map(m => ({ ...m })) }
}

function addMeasure() {
  if (!editingObjective.value) return
  const list = editingObjective.value._measures ?? []
  editingObjective.value._measures = [
    ...list,
    { label: '', unit: '', baseline_value: '', target_value: '', current_value: '', weight: 0, progress: 0, status: 'pending', sort_order: list.length * 10 }
  ]
}
function removeLocalMeasure(idx: number) {
  if (!editingObjective.value) return
  editingObjective.value._measures = (editingObjective.value._measures ?? []).filter((_, i) => i !== idx)
}

async function submitObjective() {
  if (!editingObjective.value?.title || !editingObjective.value.staff_id || !editingObjective.value.cycle_id) {
    toast.push({ type: 'error', title: 'Missing fields', message: 'Title, staff member and cycle are required.' })
    return
  }
  try {
    const { _measures, staff, cycle, framework, ...payload } = editingObjective.value as any
    const saved = await saveObjective(payload)
    if (!saved) throw new Error('Could not save objective')

    const existing = payload.id ? await loadMeasures(saved.id) : []
    const existingIds = new Set(existing.map(m => m.id))
    const keptIds = new Set<string>()
    for (const m of (_measures ?? [])) {
      const rec: Partial<PerformanceMeasure> = { ...m, objective_id: saved.id }
      if (!rec.label) continue
      const savedM = await saveMeasure(rec)
      if (savedM?.id) keptIds.add(savedM.id)
    }
    for (const m of existing) {
      if (!keptIds.has(m.id)) await deleteMeasure(m.id)
    }

    auditLog({ action: payload.id ? 'update' : 'create', target_type: 'performance_objective', target_id: saved.id, target_label: saved.title })
    toast.push({ type: 'success', title: 'Objective saved', message: saved.title })
    editingObjective.value = null
    await reloadObjectives()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}

async function removeObjective(o: any) {
  const ok = await toast.confirm({ title: 'Delete objective?', message: `"${o.title}" will be removed.`, confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deleteObjective(o.id)
    auditLog({ action: 'delete', target_type: 'performance_objective', target_id: o.id, target_label: o.title })
    toast.push({ type: 'success', title: 'Objective deleted', message: o.title })
    await reloadObjectives()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}

function statusBadge(status: string) {
  const map: Record<string, string> = {
    draft: 'badge-slate',
    planning: 'badge-blue',
    active: 'badge-green',
    on_track: 'badge-green',
    in_review: 'badge-amber',
    at_risk: 'badge-amber',
    off_track: 'badge-rose',
    completed: 'badge-blue',
    dropped: 'badge-slate',
    closed: 'badge-slate'
  }
  return map[status] ?? 'badge-slate'
}

const objectivesByStaff = computed(() => {
  const groups = new Map<string, any[]>()
  for (const o of objectives.value) {
    const key = o.staff_id
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key)!.push(o)
  }
  return [...groups.entries()].map(([staffId, items]) => ({
    staffId,
    staff: items[0]?.staff,
    items,
    totalWeight: items.reduce((sum, o) => sum + Number(o.weight || 0), 0)
  }))
})

const selectedCycle = computed(() => cycles.value.find(c => c.id === selectedCycleId.value) ?? null)

// --- objective bulk import / export ---
function csvEscape(v: any): string {
  const s = v == null ? '' : String(v)
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

function exportObjectivesCsv() {
  const headers = ['Staff email', 'Staff name', 'Title', 'Description', 'Category', 'Kind', 'Weight', 'Target', 'Progress', 'Status', 'Manager notes']
  const staffIndex = new Map(staffMembers.value.map(s => [s.id, s]))
  const rows = objectives.value.map((o: any) => {
    const s = staffIndex.get(o.staff_id) ?? {}
    return [s.email, s.full_name, o.title, o.description, o.category, o.kind, o.weight, o.target_value, o.progress, o.status, o.manager_notes]
  })
  const csv = [headers, ...rows].map(r => r.map(csvEscape).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `objectives-${selectedCycleId.value || 'all'}-${new Date().toISOString().slice(0, 10)}.csv`
  document.body.appendChild(a); a.click(); a.remove()
  URL.revokeObjectURL(url)
}

function parseCsv(text: string): string[][] {
  const rows: string[][] = []
  let cur: string[] = []
  let field = ''
  let inQuotes = false
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (inQuotes) {
      if (ch === '"' && text[i + 1] === '"') { field += '"'; i++ }
      else if (ch === '"') inQuotes = false
      else field += ch
    } else {
      if (ch === '"') inQuotes = true
      else if (ch === ',') { cur.push(field); field = '' }
      else if (ch === '\n') { cur.push(field); rows.push(cur); cur = []; field = '' }
      else if (ch === '\r') { /* ignore */ }
      else field += ch
    }
  }
  if (field.length || cur.length) { cur.push(field); rows.push(cur) }
  return rows.filter(r => r.some(c => c.length))
}

function normaliseObjectiveStatus(raw: string): string {
  const v = (raw || '').trim().toLowerCase()
  if (!v) return 'draft'
  if (v === 'on track') return 'on_track'
  if (v === 'at risk') return 'at_risk'
  if (v === 'off track') return 'off_track'
  if (['draft','active','on_track','at_risk','off_track','completed','dropped'].includes(v)) return v
  return 'active'
}

function normaliseMeasureStatus(raw: string): string {
  const v = (raw || '').trim().toLowerCase()
  if (v === 'on track') return 'on_track'
  if (v === 'at risk') return 'at_risk'
  if (v === 'off track') return 'off_track'
  if (['pending','on_track','at_risk','off_track','done','dropped'].includes(v)) return v
  return 'pending'
}

async function bulkUploadObjectives() {
  if (!selectedCycleId.value) {
    toast.push({ type: 'error', title: 'Pick a cycle first', message: 'Select the cycle these objectives belong to.' })
    return
  }
  const text = bulkObjectivesText.value.trim()
  if (!text) return
  bulkUploading.value = true
  try {
    const rows = parseCsv(text)
    if (rows.length < 2) throw new Error('Need a header row and at least one data row')
    const headers = rows[0].map(h => h.trim().replace(/^\uFEFF/, '').toLowerCase())
    const idx = (...names: string[]) => {
      for (const n of names) {
        const ix = headers.indexOf(n.toLowerCase())
        if (ix >= 0) return ix
      }
      return -1
    }
    const emailIx = idx('staff email', 'employee email', 'email')
    const nameIx = idx('employee name', 'staff name', 'full name', 'name')
    const codeIx = idx('employee code', 'staff code')
    const titleIx = idx('objective title', 'title')
    const descIx = idx('objective description', 'description')
    const catIx = idx('category')
    const kindIx = idx('performance type', 'kind')
    const objStatusIx = idx('objective status', 'status')
    const objProgressIx = idx('objective progress', 'progress')
    const targetIx = idx('target')
    const notesIx = idx('reviewer comment', 'manager notes')
    const krTitleIx = idx('key result title')
    const krDescIx = idx('key result description')
    const krUnitIx = idx('key result unit', 'unit')
    const krStartIx = idx('key result start value')
    const krEndIx = idx('key result end value')
    const krWeightIx = idx('weight')
    const krProgressIx = idx('key result progress')
    const krStatusIx = idx('key result status')

    if (titleIx < 0) throw new Error('Missing required column: Objective Title')
    if (emailIx < 0 && nameIx < 0) throw new Error('Need either an Email or Employee Name column')

    const staffByEmail = new Map(staffMembers.value.map(s => [(s.email ?? '').toLowerCase(), s]))
    const staffByName = new Map(staffMembers.value.map(s => [(s.full_name ?? '').toLowerCase().trim(), s]))

    type Group = { staff: any; title: string; description: string; category: string; kind: string; status: string; progress: number; target: string; notes: string; rows: string[][] }
    const groups = new Map<string, Group>()
    const errors: string[] = []

    for (let i = 1; i < rows.length; i++) {
      const row = rows[i]
      const title = (row[titleIx] ?? '').trim()
      if (!title) continue
      const email = emailIx >= 0 ? (row[emailIx] ?? '').trim().toLowerCase() : ''
      const name = nameIx >= 0 ? (row[nameIx] ?? '').trim().toLowerCase() : ''
      const staff = (email && staffByEmail.get(email)) || (name && staffByName.get(name)) || null
      if (!staff) {
        errors.push(`Row ${i + 1}: unknown staff "${row[emailIx] ?? row[nameIx] ?? ''}"`)
        continue
      }
      const key = `${staff.id}::${title.toLowerCase()}`
      let g = groups.get(key)
      if (!g) {
        const kindRaw = (kindIx >= 0 ? row[kindIx] ?? '' : '').trim().toLowerCase()
        const kind = ['okr', 'kpi', 'competency'].includes(kindRaw) ? kindRaw : 'okr'
        g = {
          staff,
          title,
          description: descIx >= 0 ? row[descIx] ?? '' : '',
          category: ((catIx >= 0 ? row[catIx]?.trim().toLowerCase() : '') as string) || 'business',
          kind,
          status: normaliseObjectiveStatus(objStatusIx >= 0 ? row[objStatusIx] ?? '' : ''),
          progress: objProgressIx >= 0 ? Number(row[objProgressIx] || 0) : 0,
          target: targetIx >= 0 ? row[targetIx] ?? '' : '',
          notes: notesIx >= 0 ? row[notesIx] ?? '' : '',
          rows: []
        }
        groups.set(key, g)
      }
      g.rows.push(row)
    }

    let createdObjectives = 0
    let createdMeasures = 0
    let order = 0
    for (const g of groups.values()) {
      try {
        const framework = frameworks.value.find(f => f.kind === g.kind && f.is_active) ?? null
        const saved = await saveObjective({
          cycle_id: selectedCycleId.value,
          staff_id: g.staff.id,
          framework_id: framework?.id ?? null,
          kind: g.kind as any,
          title: g.title,
          description: g.description,
          category: g.category as any,
          weight: 0,
          target_value: g.target,
          progress: Math.round(g.progress),
          status: g.status as any,
          manager_notes: g.notes,
          sort_order: order++
        } as any)
        if (!saved?.id) throw new Error('save returned no id')
        createdObjectives++

        let totalWeight = 0
        let mIdx = 0
        for (const r of g.rows) {
          const krTitle = krTitleIx >= 0 ? (r[krTitleIx] ?? '').trim() : ''
          if (!krTitle) continue
          const w = krWeightIx >= 0 ? Number(r[krWeightIx] || 0) : 0
          totalWeight += w
          const m = await saveMeasure({
            objective_id: saved.id,
            label: krTitle,
            description: krDescIx >= 0 ? r[krDescIx] ?? '' : '',
            unit: krUnitIx >= 0 ? r[krUnitIx] ?? '' : '',
            baseline_value: krStartIx >= 0 ? r[krStartIx] ?? '' : '',
            target_value: krEndIx >= 0 ? r[krEndIx] ?? '' : '',
            current_value: '',
            weight: w,
            progress: krProgressIx >= 0 ? Number(r[krProgressIx] || 0) : 0,
            status: normaliseMeasureStatus(krStatusIx >= 0 ? r[krStatusIx] ?? '' : '') as any,
            sort_order: mIdx++ * 10
          } as any)
          if (m?.id) createdMeasures++
        }
        if (totalWeight > 0) {
          await saveObjective({ id: saved.id, weight: Math.round(totalWeight) } as any)
        }
      } catch (e: any) {
        errors.push(`${g.staff.full_name} / ${g.title}: ${e?.message ?? 'failed'}`)
      }
    }

    if (createdObjectives) {
      auditLog({ action: 'bulk_import', target_type: 'performance_objective', target_label: `${createdObjectives} objectives, ${createdMeasures} key results` })
    }
    toast.push({
      type: errors.length && !createdObjectives ? 'error' : 'success',
      title: `Imported ${createdObjectives} objective${createdObjectives === 1 ? '' : 's'} (${createdMeasures} key results)`,
      message: errors.length ? errors.slice(0, 3).join(' | ') : 'Bulk upload complete.'
    })
    if (createdObjectives) {
      showBulkUpload.value = false
      bulkObjectivesText.value = ''
      await reloadObjectives()
    }
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not import', message: e?.message ?? 'Unexpected error' })
  } finally {
    bulkUploading.value = false
  }
}

// --- recognitions ---
function startNewRecognition() {
  editingRecognition.value = {
    subject_staff_id: selectedStaffId.value || '',
    cycle_id: selectedCycleId.value || null,
    objective_id: null,
    kind: 'commendation',
    title: '',
    summary: '',
    impact: '',
    points: 0,
    awarded_at: new Date().toISOString().slice(0, 10),
    visible_to_staff: true
  }
}
function editRecognition(r: any) { editingRecognition.value = { ...r } }
async function submitRecognition() {
  if (!editingRecognition.value?.subject_staff_id || !editingRecognition.value.title) {
    toast.push({ type: 'error', title: 'Missing fields', message: 'Subject and title are required.' })
    return
  }
  try {
    const isNewRec = !editingRecognition.value.id
    await saveRecognition(editingRecognition.value)
    auditLog({ action: isNewRec ? 'create' : 'update', target_type: 'performance_recognition', target_label: editingRecognition.value.title ?? '' })
    toast.push({ type: 'success', title: 'Recognition saved', message: editingRecognition.value.title ?? '' })
    editingRecognition.value = null
    await reloadRecognitions()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}
async function removeRecognition(r: any) {
  const ok = await toast.confirm({ title: 'Delete recognition?', message: `"${r.title}" will be removed.`, confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deleteRecognition(r.id)
    auditLog({ action: 'delete', target_type: 'performance_recognition', target_id: r.id, target_label: r.title })
    toast.push({ type: 'success', title: 'Recognition deleted', message: r.title })
    await reloadRecognitions()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}

// --- PIPs ---
function startNewPip() {
  const today = new Date()
  const end = new Date(today); end.setDate(end.getDate() + 60)
  editingPip.value = {
    subject_staff_id: selectedStaffId.value || '',
    cycle_id: selectedCycleId.value || null,
    owner_staff_id: null,
    title: '',
    reason: '',
    expected_outcomes: '',
    support_plan: '',
    consequences: '',
    status: 'draft',
    start_date: today.toISOString().slice(0, 10),
    end_date: end.toISOString().slice(0, 10),
    review_frequency_days: 14
  }
}
function editPip(p: any) { editingPip.value = { ...p } }
async function submitPip() {
  if (!editingPip.value?.subject_staff_id || !editingPip.value.title) {
    toast.push({ type: 'error', title: 'Missing fields', message: 'Subject and title are required.' })
    return
  }
  try {
    const payload = { ...editingPip.value } as any
    delete payload.subject; delete payload.owner; delete payload.cycle
    if (payload.status !== 'draft' && ['succeeded','failed','cancelled'].includes(payload.status)) {
      payload.closed_at = payload.closed_at ?? new Date().toISOString()
      payload.closed_outcome = payload.closed_outcome || payload.status
    }
    const isNewPip = !payload.id
    await savePip(payload)
    auditLog({ action: isNewPip ? 'create' : 'update', target_type: 'pip', target_label: editingPip.value.title ?? '' })
    toast.push({ type: 'success', title: 'Plan saved', message: editingPip.value.title ?? '' })
    editingPip.value = null
    await reloadPips()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}
async function removePip(p: any) {
  const ok = await toast.confirm({ title: 'Delete improvement plan?', message: `"${p.title}" and all check-ins will be removed.`, confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deletePip(p.id)
    auditLog({ action: 'delete', target_type: 'pip', target_id: p.id, target_label: p.title })
    toast.push({ type: 'success', title: 'Plan deleted', message: p.title })
    if (expandedPipId.value === p.id) expandedPipId.value = ''
    await reloadPips()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}
async function togglePipDetails(p: any) {
  if (expandedPipId.value === p.id) {
    expandedPipId.value = ''
    return
  }
  expandedPipId.value = p.id
  pipCheckins.value = await loadPipCheckins(p.id)
}
function startNewCheckin(p: any) {
  editingCheckin.value = {
    pip_id: p.id,
    checkin_date: new Date().toISOString().slice(0, 10),
    status: 'on_track',
    manager_notes: '',
    evidence: ''
  }
}
async function submitCheckin() {
  if (!editingCheckin.value?.pip_id) return
  try {
    const isNewCheckin = !editingCheckin.value.id
    await saveCheckin(editingCheckin.value)
    auditLog({ action: isNewCheckin ? 'create' : 'update', target_type: 'pip_checkin', target_label: `PIP ${editingCheckin.value.pip_id} check-in` })
    toast.push({ type: 'success', title: 'Check-in saved', message: '' })
    const pipId = editingCheckin.value.pip_id
    editingCheckin.value = null
    pipCheckins.value = await loadPipCheckins(pipId)
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}
async function removeCheckin(c: PerformanceImprovementCheckin) {
  const ok = await toast.confirm({ title: 'Delete check-in?', message: 'This entry will be removed.', confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  try {
    await deleteCheckin(c.id)
    auditLog({ action: 'delete', target_type: 'pip_checkin', target_id: c.id, target_label: `PIP ${c.pip_id} check-in` })
    pipCheckins.value = await loadPipCheckins(c.pip_id)
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not delete', message: e?.message ?? 'Unexpected error' })
  }
}

// --- dashboard metrics ---
const dashboard = computed(() => {
  const objCount = objectives.value.length
  const onTrack = objectives.value.filter((o: any) => ['on_track', 'active'].includes(o.status)).length
  const atRisk = objectives.value.filter((o: any) => o.status === 'at_risk').length
  const offTrack = objectives.value.filter((o: any) => o.status === 'off_track').length
  const completed = objectives.value.filter((o: any) => o.status === 'completed').length
  const avgProgress = objCount ? Math.round(objectives.value.reduce((s, o: any) => s + Number(o.progress || 0), 0) / objCount) : 0
  const reviewsByStatus: Record<string, number> = {}
  for (const r of reviews.value) reviewsByStatus[r.status] = (reviewsByStatus[r.status] ?? 0) + 1
  const submittedReviews = reviews.value.filter((r: any) => r.status === 'submitted')
  const avgRating = submittedReviews.length
    ? (submittedReviews.reduce((s, r: any) => s + Number(r.overall_rating || 0), 0) / submittedReviews.filter((r: any) => r.overall_rating).length)
    : 0
  const activePips = pips.value.filter((p: any) => !['draft', 'succeeded', 'failed', 'cancelled'].includes(p.status)).length
  const recognitionCount = recognitions.value.length
  return { objCount, onTrack, atRisk, offTrack, completed, avgProgress, reviewsByStatus, avgRating, activePips, recognitionCount }
})

const ratingDistribution = computed(() => {
  const buckets: Record<number, number> = { 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 }
  for (const r of reviews.value) {
    if (r.status === 'submitted' && r.overall_rating != null) {
      const b = Math.max(1, Math.min(5, Math.round(Number(r.overall_rating))))
      buckets[b] += 1
    }
  }
  const max = Math.max(1, ...Object.values(buckets))
  return Object.entries(buckets).map(([score, count]) => ({ score: Number(score), count, pct: Math.round((count / max) * 100) }))
})
</script>

<template>
  <div class="space-y-6">
    <header class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
      <div>
        <h1 class="section-title">Performance</h1>
        <p class="section-subtitle">Run performance cycles, define scoring frameworks and set objectives for every team member.</p>
      </div>
    </header>

    <nav class="border-b border-slate-200 -mx-4 sm:mx-0">
      <div class="flex overflow-x-auto px-4 sm:px-0 gap-6 scrollbar-thin">
        <button
          v-for="t in [
            { id: 'dashboard', label: 'Dashboard' },
            { id: 'cycles', label: 'Cycles' },
            { id: 'frameworks', label: 'Frameworks' },
            { id: 'objectives', label: 'Objectives' },
            { id: 'appraisals', label: 'Appraisals' },
            { id: 'calibration', label: 'Calibration' },
            { id: 'templates', label: 'Templates' },
            { id: 'values', label: 'Core values' },
            { id: 'reviews', label: 'Reviews' },
            { id: 'recognitions', label: 'Recognition' },
            { id: 'pips', label: 'Plans' }
          ]"
          :key="t.id"
          type="button"
          class="relative whitespace-nowrap py-2.5 text-sm font-medium transition-colors border-b-2 -mb-px"
          :class="tab === t.id ? 'text-sycamore-700 border-sycamore-600' : 'text-slate-500 hover:text-slate-800 border-transparent'"
          @click="tab = t.id as any"
        >
          {{ t.label }}
        </button>
      </div>
    </nav>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading performance data...</div>

    <!-- Dashboard ---------------------------------------------------------- -->
    <section v-else-if="tab === 'dashboard'" class="space-y-4">
      <div class="card p-4 sm:p-5">
        <div class="grid md:grid-cols-3 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="selectedCycleId" class="input">
              <option value="">All cycles</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }} ({{ c.status }})</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject</span>
            <select v-model="selectedStaffId" class="input">
              <option value="">All staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
        </div>
      </div>

      <div class="grid md:grid-cols-2 lg:grid-cols-4 gap-3">
        <div class="card p-4">
          <div class="text-xs uppercase tracking-wide text-slate-500">Objectives</div>
          <div class="text-2xl font-bold text-slate-900 mt-1">{{ dashboard.objCount }}</div>
          <div class="text-xs text-slate-500 mt-1">Average progress {{ dashboard.avgProgress }}%</div>
        </div>
        <div class="card p-4">
          <div class="text-xs uppercase tracking-wide text-slate-500">On track / completed</div>
          <div class="text-2xl font-bold text-leaf-700 mt-1">{{ dashboard.onTrack + dashboard.completed }}</div>
          <div class="text-xs text-slate-500 mt-1">At risk {{ dashboard.atRisk }} &middot; Off track {{ dashboard.offTrack }}</div>
        </div>
        <div class="card p-4">
          <div class="text-xs uppercase tracking-wide text-slate-500">Reviews submitted</div>
          <div class="text-2xl font-bold text-slate-900 mt-1">{{ dashboard.reviewsByStatus.submitted ?? 0 }}</div>
          <div class="text-xs text-slate-500 mt-1">Invited {{ dashboard.reviewsByStatus.invited ?? 0 }} &middot; In progress {{ dashboard.reviewsByStatus.in_progress ?? 0 }}</div>
        </div>
        <div class="card p-4">
          <div class="text-xs uppercase tracking-wide text-slate-500">Active PIPs</div>
          <div class="text-2xl font-bold text-amber-700 mt-1">{{ dashboard.activePips }}</div>
          <div class="text-xs text-slate-500 mt-1">Recognitions this view {{ dashboard.recognitionCount }}</div>
        </div>
      </div>

      <div class="card p-5 space-y-3">
        <header class="flex items-center justify-between gap-3">
          <div>
            <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Rating distribution</h2>
            <p class="text-xs text-slate-500 mt-1">Overall rating from submitted reviews for this cycle view.</p>
          </div>
          <div class="text-xs text-slate-500">Avg {{ dashboard.avgRating ? dashboard.avgRating.toFixed(2) : '—' }}</div>
        </header>
        <ul class="space-y-2">
          <li v-for="row in ratingDistribution" :key="row.score" class="flex items-center gap-3">
            <span class="text-xs w-12 text-slate-500">Score {{ row.score }}</span>
            <div class="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
              <div class="h-full bg-sycamore-500" :style="{ width: `${row.pct}%` }" />
            </div>
            <span class="text-xs w-10 text-right text-slate-600">{{ row.count }}</span>
          </li>
        </ul>
      </div>

      <div class="grid md:grid-cols-2 gap-4">
        <div class="card p-5">
          <h3 class="text-sm font-semibold text-slate-900">Calibration check</h3>
          <p class="text-xs text-slate-500 mt-1">Quickly spot teams whose objective weights or review completion lag behind.</p>
          <ul class="mt-3 space-y-2">
            <li v-for="group in objectivesByStaff" :key="group.staffId" class="flex items-center justify-between gap-3 text-sm">
              <span class="truncate">{{ group.staff?.full_name }}</span>
              <span :class="Math.abs(group.totalWeight - 100) < 0.01 ? 'text-leaf-700' : 'text-amber-700'" class="text-xs">
                {{ group.totalWeight.toFixed(0) }}% weight
              </span>
            </li>
            <li v-if="!objectivesByStaff.length" class="text-xs text-slate-400 italic">No objectives in view.</li>
          </ul>
        </div>
        <div class="card p-5">
          <h3 class="text-sm font-semibold text-slate-900">Recent recognition</h3>
          <ul class="mt-3 space-y-2">
            <li v-for="r in recognitions.slice(0, 6)" :key="r.id" class="text-sm">
              <div class="flex items-center justify-between gap-2">
                <span class="font-medium text-slate-900 truncate">{{ r.subject?.full_name }}</span>
                <span class="badge badge-blue text-[10px]">{{ RECOGNITION_KIND_LABELS[r.kind as RecognitionKind] }}</span>
              </div>
              <div class="text-xs text-slate-500">{{ r.title }} &middot; {{ new Date(r.awarded_at).toLocaleDateString('en-GB') }}</div>
            </li>
            <li v-if="!recognitions.length" class="text-xs text-slate-400 italic">Nothing logged yet.</li>
          </ul>
        </div>
      </div>
    </section>

    <!-- Cycles ------------------------------------------------------------ -->
    <section v-else-if="tab === 'cycles'" class="space-y-4">
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Review cycles</h2>
        <button class="btn-primary" @click="startNewCycle">New cycle</button>
      </div>

      <div v-if="!cycles.length" class="card p-8 text-center text-sm text-slate-500">
        No cycles yet. Create your first cycle to start setting objectives.
      </div>

      <div v-else class="grid gap-3">
        <article v-for="c in cycles" :key="c.id" class="card p-5 flex flex-col sm:flex-row gap-4 sm:items-start">
          <div class="flex-1 min-w-0 space-y-2">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="text-base font-semibold text-slate-900 truncate">{{ c.name }}</h3>
              <span class="badge" :class="statusBadge(c.status)">{{ c.status }}</span>
              <span v-if="c.is_primary" class="badge badge-green">Primary</span>
              <span class="badge badge-slate uppercase text-[10px]">{{ c.default_framework }}</span>
            </div>
            <div class="text-xs text-slate-500">
              {{ new Date(c.period_start).toLocaleDateString('en-GB') }} — {{ new Date(c.period_end).toLocaleDateString('en-GB') }}
            </div>
            <p v-if="c.description" class="text-sm text-slate-600 line-clamp-2">{{ c.description }}</p>
          </div>
          <div class="flex flex-wrap gap-2 shrink-0">
            <button v-if="!c.is_primary" class="btn-secondary text-xs" @click="markPrimary(c)">Make primary</button>
            <button class="btn-secondary text-xs" @click="editCycle(c)">Edit</button>
            <button class="btn-secondary text-xs" @click="removeCycle(c)">Delete</button>
          </div>
        </article>
      </div>
    </section>

    <!-- Frameworks ------------------------------------------------------- -->
    <section v-else-if="tab === 'frameworks'" class="space-y-4">
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Scoring frameworks</h2>
        <button class="btn-primary" @click="startNewFramework">New framework</button>
      </div>

      <div v-if="!frameworks.length" class="card p-8 text-center text-sm text-slate-500">
        No frameworks yet. The seed data should have created defaults — reload or add one.
      </div>

      <div v-else class="grid md:grid-cols-2 gap-3">
        <article v-for="f in frameworks" :key="f.id" class="card p-5 space-y-2">
          <div class="flex items-center justify-between gap-3">
            <div>
              <h3 class="text-base font-semibold text-slate-900">{{ f.name }}</h3>
              <div class="text-xs text-slate-500 uppercase tracking-wide">{{ f.kind }}</div>
            </div>
            <span v-if="!f.is_active" class="badge badge-slate">Inactive</span>
          </div>
          <p v-if="f.description" class="text-sm text-slate-600">{{ f.description }}</p>
          <div v-if="f.scoring_scale?.labels?.length" class="flex flex-wrap gap-1.5">
            <span v-for="(l, i) in f.scoring_scale.labels" :key="i" class="badge badge-slate text-[10px]">
              {{ i + 1 }} — {{ l }}
            </span>
          </div>
          <div class="flex gap-2 pt-2">
            <button class="btn-secondary text-xs" @click="editFramework(f)">Edit</button>
            <button class="btn-secondary text-xs" @click="removeFramework(f)">Delete</button>
          </div>
        </article>
      </div>
    </section>

    <!-- Objectives ------------------------------------------------------- -->
    <section v-else-if="tab === 'objectives'" class="space-y-4">
      <div class="card p-4 sm:p-5 space-y-3">
        <div class="grid md:grid-cols-2 lg:grid-cols-4 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="selectedCycleId" class="input">
              <option value="">Select cycle</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }} ({{ c.status }})</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Department</span>
            <select v-model="selectedDepartmentId" class="input">
              <option value="">All departments</option>
              <option v-for="d in departments" :key="d.id" :value="d.id">{{ d.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Paygroup</span>
            <select v-model="selectedPaygroup" class="input">
              <option value="">All paygroups</option>
              <option v-for="p in paygroupOptions" :key="p" :value="p">{{ p }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Employee</span>
            <select v-model="selectedStaffId" class="input">
              <option value="">All staff</option>
              <option v-for="s in filteredStaff" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
        </div>
        <div class="flex flex-wrap items-center justify-between gap-2 pt-1">
          <div v-if="selectedCycle" class="text-xs text-slate-500">
            Selected cycle is <span class="font-semibold">{{ selectedCycle.status }}</span>. Staff can edit their own progress when status is planning, active, or in_review.
          </div>
          <div class="flex flex-wrap gap-2 ml-auto">
            <button class="btn-secondary text-xs" :disabled="!objectives.length" @click="exportObjectivesCsv">Export CSV</button>
            <button class="btn-secondary text-xs" :disabled="!selectedCycleId" @click="showBulkUpload = true">Bulk upload</button>
            <button class="btn-primary text-xs" :disabled="!selectedCycleId" @click="startNewObjective">New objective</button>
          </div>
        </div>
      </div>

      <div v-if="!objectives.length" class="card p-8 text-center text-sm text-slate-500">
        {{ selectedCycleId ? 'No objectives for this selection yet.' : 'Select a cycle to view its objectives.' }}
      </div>

      <div v-else class="space-y-4">
        <article v-for="group in objectivesByStaff" :key="group.staffId" class="card overflow-hidden">
          <header class="px-5 py-3 border-b border-slate-100 bg-slate-50/60 flex flex-wrap items-center justify-between gap-2">
            <div>
              <div class="text-sm font-semibold text-slate-900">{{ group.staff?.full_name ?? 'Unknown' }}</div>
              <div class="text-xs text-slate-500">{{ group.staff?.role ?? '' }}</div>
            </div>
            <div class="text-xs" :class="Math.abs(group.totalWeight - 100) < 0.01 ? 'text-leaf-700' : 'text-amber-700'">
              Total weight: {{ group.totalWeight.toFixed(0) }}%
              <span v-if="Math.abs(group.totalWeight - 100) > 0.01"> (should be 100%)</span>
            </div>
          </header>
          <ul class="divide-y divide-slate-100">
            <li v-for="o in group.items" :key="o.id" class="p-5 flex flex-col gap-3">
              <div class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0 flex-1 space-y-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <h4 class="text-sm font-semibold text-slate-900">{{ o.title }}</h4>
                    <span class="badge badge-slate uppercase text-[10px]">{{ o.kind }}</span>
                    <span class="badge" :class="statusBadge(o.status)">{{ o.status.replaceAll('_', ' ') }}</span>
                    <span class="badge badge-slate">{{ o.category }}</span>
                    <span v-if="o.framework?.name" class="badge badge-blue text-[10px]">{{ o.framework.name }}</span>
                  </div>
                  <p v-if="o.description" class="text-sm text-slate-600">{{ o.description }}</p>
                  <div class="flex items-center gap-3 text-xs text-slate-500">
                    <span>Weight {{ Number(o.weight).toFixed(0) }}%</span>
                    <span>Progress {{ Number(o.progress).toFixed(0) }}%</span>
                    <span v-if="o.rating !== null">Rating {{ Number(o.rating).toFixed(1) }}</span>
                  </div>
                  <div class="w-full h-1.5 rounded-full bg-slate-100 overflow-hidden">
                    <div class="h-full bg-sycamore-500" :style="{ width: `${Math.min(100, Number(o.progress) || 0)}%` }" />
                  </div>
                </div>
                <div class="flex gap-2 shrink-0">
                  <button class="btn-secondary text-xs" @click="editObjective(o)">Edit</button>
                  <button class="btn-secondary text-xs" @click="removeObjective(o)">Delete</button>
                </div>
              </div>
            </li>
          </ul>
        </article>
      </div>
    </section>

    <!-- Appraisals ------------------------------------------------------- -->
    <section v-if="tab === 'appraisals' && !loading" class="space-y-4">
      <div class="card p-4 sm:p-5">
        <div class="grid md:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="selectedCycleId" class="input">
              <option value="" disabled>Select a cycle</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </label>
        </div>
      </div>
      <AppraisalsAdminTable
        :cycles="cycles"
        :staff-members="staffMembers"
        :selected-cycle-id="selectedCycleId"
      />
    </section>

    <!-- Calibration ------------------------------------------------------ -->
    <section v-if="tab === 'calibration' && !loading" class="space-y-4">
      <div class="card p-4 sm:p-5">
        <label class="block max-w-sm">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
          <select v-model="selectedCycleId" class="input">
            <option value="" disabled>Select a cycle</option>
            <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
          </select>
        </label>
      </div>
      <CalibrationGrid :cycle-id="selectedCycleId" />
    </section>

    <!-- Templates -------------------------------------------------------- -->
    <section v-if="tab === 'templates' && !loading" class="space-y-4">
      <ObjectiveTemplatesEditor :cycles="cycles" :frameworks="frameworks" />
    </section>

    <!-- Core values ------------------------------------------------------ -->
    <section v-if="tab === 'values' && !loading" class="space-y-4">
      <CoreValuesEditor />
    </section>

    <!-- Reviews ---------------------------------------------------------- -->
    <section v-if="tab === 'reviews' && !loading" class="space-y-4">
      <div class="card p-4 sm:p-5 space-y-3">
        <div class="grid md:grid-cols-4 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="selectedCycleId" class="input">
              <option value="">Select cycle</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }} ({{ c.status }})</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject</span>
            <select v-model="selectedStaffId" class="input">
              <option value="">All staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Type</span>
            <select v-model="reviewTypeFilter" class="input">
              <option value="">All types</option>
              <option v-for="t in REVIEWER_TYPES" :key="t" :value="t">{{ REVIEWER_TYPE_LABELS[t] }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Status</span>
            <select v-model="reviewStatusFilter" class="input">
              <option value="">All</option>
              <option value="invited">Invited</option>
              <option value="in_progress">In progress</option>
              <option value="submitted">Submitted</option>
              <option value="declined">Declined</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </label>
        </div>
        <div class="flex justify-end">
          <button class="btn-primary" :disabled="!selectedCycleId" @click="startNewReview">Invite reviewers</button>
        </div>
      </div>

      <div v-if="!reviews.length" class="card p-8 text-center text-sm text-slate-500">
        {{ selectedCycleId ? 'No review invitations for this selection yet.' : 'Select a cycle to view its reviews.' }}
      </div>

      <div v-else class="card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
            <tr>
              <th class="text-left px-4 py-2.5">Subject</th>
              <th class="text-left px-4 py-2.5">Type</th>
              <th class="text-left px-4 py-2.5">Reviewer</th>
              <th class="text-left px-4 py-2.5">Status</th>
              <th class="text-left px-4 py-2.5">Due</th>
              <th class="text-left px-4 py-2.5">Submitted</th>
              <th class="text-right px-4 py-2.5">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            <tr v-for="r in reviews" :key="r.id" class="hover:bg-slate-50/50">
              <td class="px-4 py-3">
                <div class="font-medium text-slate-900">{{ r.subject?.full_name ?? '—' }}</div>
                <div class="text-xs text-slate-500">{{ r.subject?.role ?? '' }}</div>
              </td>
              <td class="px-4 py-3">
                <span class="badge badge-slate">{{ REVIEWER_TYPE_LABELS[r.reviewer_type as ReviewerType] }}</span>
                <span v-if="r.anonymous" class="badge badge-blue ml-1">Anonymous</span>
              </td>
              <td class="px-4 py-3">
                <div class="text-sm text-slate-900">{{ r.reviewer?.full_name ?? '—' }}</div>
                <div class="text-xs text-slate-500">{{ r.reviewer?.role ?? '' }}</div>
              </td>
              <td class="px-4 py-3">
                <span class="badge" :class="statusBadge(r.status)">{{ r.status.replaceAll('_', ' ') }}</span>
              </td>
              <td class="px-4 py-3 text-xs text-slate-600">{{ r.due_at ? new Date(r.due_at).toLocaleDateString('en-GB') : '—' }}</td>
              <td class="px-4 py-3 text-xs text-slate-600">{{ r.submitted_at ? new Date(r.submitted_at).toLocaleDateString('en-GB') : '—' }}</td>
              <td class="px-4 py-3 text-right whitespace-nowrap">
                <button v-if="['invited','in_progress'].includes(r.status)" class="btn-secondary text-xs" @click="cancelReview(r)">Cancel</button>
                <button class="btn-secondary text-xs ml-1" @click="removeReview(r)">Delete</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Recognitions ----------------------------------------------------- -->
    <section v-if="tab === 'recognitions' && !loading" class="space-y-4">
      <div class="card p-4 sm:p-5">
        <div class="grid md:grid-cols-3 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="selectedCycleId" class="input">
              <option value="">All cycles</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject</span>
            <select v-model="selectedStaffId" class="input">
              <option value="">All staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <div class="flex items-end">
            <button class="btn-primary" @click="startNewRecognition">Log recognition</button>
          </div>
        </div>
      </div>

      <div v-if="!recognitions.length" class="card p-8 text-center text-sm text-slate-500">
        No recognitions recorded yet. Log commendations, spot awards, or promotions to celebrate exceptional work.
      </div>

      <ul v-else class="space-y-2">
        <li v-for="r in recognitions" :key="r.id" class="card p-5 flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0 flex-1 space-y-1">
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm font-semibold text-slate-900">{{ r.subject?.full_name }}</span>
              <span class="badge badge-blue">{{ RECOGNITION_KIND_LABELS[r.kind as RecognitionKind] }}</span>
              <span v-if="r.points" class="badge badge-green">+{{ r.points }} pts</span>
              <span v-if="!r.visible_to_staff" class="badge badge-slate">Hidden</span>
            </div>
            <div class="text-sm font-medium text-slate-900">{{ r.title }}</div>
            <p v-if="r.summary" class="text-sm text-slate-600">{{ r.summary }}</p>
            <div class="text-xs text-slate-500">
              Awarded {{ new Date(r.awarded_at).toLocaleDateString('en-GB') }}
              <span v-if="r.awarder"> &middot; by {{ r.awarder.full_name }}</span>
              <span v-if="r.cycle"> &middot; Cycle {{ r.cycle.name }}</span>
            </div>
          </div>
          <div class="flex gap-2 shrink-0">
            <button class="btn-secondary text-xs" @click="editRecognition(r)">Edit</button>
            <button class="btn-secondary text-xs" @click="removeRecognition(r)">Delete</button>
          </div>
        </li>
      </ul>
    </section>

    <!-- PIPs ------------------------------------------------------------- -->
    <section v-if="tab === 'pips' && !loading" class="space-y-4">
      <div class="card p-4 sm:p-5">
        <div class="grid md:grid-cols-3 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject</span>
            <select v-model="selectedStaffId" class="input">
              <option value="">All staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <div class="md:col-span-2 flex items-end justify-end">
            <button class="btn-primary" @click="startNewPip">Start new plan</button>
          </div>
        </div>
      </div>

      <div v-if="!pips.length" class="card p-8 text-center text-sm text-slate-500">
        No performance improvement plans on file. Start one for a staff member needing extra support and clear goals.
      </div>

      <div v-else class="space-y-3">
        <article v-for="p in pips" :key="p.id" class="card overflow-hidden">
          <header class="p-5 flex flex-wrap items-start justify-between gap-3 cursor-pointer" @click="togglePipDetails(p)">
            <div class="min-w-0 flex-1 space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="text-sm font-semibold text-slate-900">{{ p.subject?.full_name }}</span>
                <span class="badge" :class="statusBadge(p.status)">{{ p.status.replaceAll('_', ' ') }}</span>
                <span v-if="p.cycle?.name" class="badge badge-slate">{{ p.cycle.name }}</span>
              </div>
              <div class="text-sm font-medium text-slate-900">{{ p.title }}</div>
              <div class="text-xs text-slate-500">
                {{ p.start_date ? new Date(p.start_date).toLocaleDateString('en-GB') : '—' }}
                —
                {{ p.end_date ? new Date(p.end_date).toLocaleDateString('en-GB') : '—' }}
                <span v-if="p.owner"> &middot; Owner {{ p.owner.full_name }}</span>
              </div>
            </div>
            <div class="flex gap-2 shrink-0" @click.stop>
              <button class="btn-secondary text-xs" @click="editPip(p)">Edit</button>
              <button class="btn-secondary text-xs" @click="removePip(p)">Delete</button>
            </div>
          </header>
          <div v-if="expandedPipId === p.id" class="px-5 pb-5 border-t border-slate-100 pt-4 space-y-3">
            <div v-if="p.reason" class="text-sm"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500 block mb-1">Reason</span>{{ p.reason }}</div>
            <div v-if="p.expected_outcomes" class="text-sm"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500 block mb-1">Expected outcomes</span>{{ p.expected_outcomes }}</div>
            <div v-if="p.support_plan" class="text-sm"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500 block mb-1">Support plan</span>{{ p.support_plan }}</div>
            <div v-if="p.consequences" class="text-sm"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500 block mb-1">Consequences if unmet</span>{{ p.consequences }}</div>

            <div class="flex items-center justify-between gap-2 pt-2 border-t border-slate-100">
              <h4 class="text-sm font-semibold text-slate-900">Check-ins</h4>
              <button class="btn-secondary text-xs" @click="startNewCheckin(p)">New check-in</button>
            </div>
            <ul class="space-y-2">
              <li v-for="c in pipCheckins" :key="c.id" class="border border-slate-200 rounded-lg p-3 space-y-1">
                <div class="flex items-center justify-between gap-2">
                  <div class="text-xs text-slate-500">{{ new Date(c.checkin_date).toLocaleDateString('en-GB') }}</div>
                  <div class="flex items-center gap-2">
                    <span class="badge" :class="statusBadge(c.status)">{{ c.status.replaceAll('_', ' ') }}</span>
                    <button class="btn-secondary text-xs" @click="removeCheckin(c)">Delete</button>
                  </div>
                </div>
                <div v-if="c.manager_notes" class="text-sm text-slate-700">{{ c.manager_notes }}</div>
                <div v-if="c.staff_response" class="text-sm text-slate-600 italic">Staff: {{ c.staff_response }}</div>
                <div v-if="c.evidence" class="text-xs text-slate-500">Evidence: {{ c.evidence }}</div>
              </li>
              <li v-if="!pipCheckins.length" class="text-xs text-slate-400 italic">No check-ins logged yet.</li>
            </ul>
          </div>
        </article>
      </div>
    </section>

    <!-- Recognition modal ----------------------------------------------- -->
    <div v-if="editingRecognition" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingRecognition = null">
      <div class="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">{{ editingRecognition.id ? 'Edit recognition' : 'Log recognition' }}</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingRecognition = null">Close</button>
        </div>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject</span>
            <select v-model="editingRecognition.subject_staff_id" class="input">
              <option value="">Select staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Kind</span>
            <select v-model="editingRecognition.kind" class="input">
              <option v-for="k in RECOGNITION_KINDS" :key="k" :value="k">{{ RECOGNITION_KIND_LABELS[k] }}</option>
            </select>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Title</span>
            <input v-model="editingRecognition.title" class="input" placeholder="Short headline, e.g. Pulled off the Q2 launch" />
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Summary</span>
            <textarea v-model="editingRecognition.summary" rows="2" class="input"></textarea>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Impact</span>
            <textarea v-model="editingRecognition.impact" rows="2" class="input" placeholder="Business outcome or behaviour this recognised"></textarea>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle (optional)</span>
            <select v-model="editingRecognition.cycle_id" class="input">
              <option :value="null">—</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Award date</span>
            <input type="date" v-model="editingRecognition.awarded_at" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Points</span>
            <input type="number" min="0" v-model.number="editingRecognition.points" class="input" />
          </label>
          <label class="flex items-end gap-2 text-sm">
            <input type="checkbox" v-model="editingRecognition.visible_to_staff" /> Visible to subject
          </label>
        </div>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingRecognition = null">Cancel</button>
          <button class="btn-primary" @click="submitRecognition">Save</button>
        </div>
      </div>
    </div>

    <!-- PIP editor modal ------------------------------------------------ -->
    <div v-if="editingPip" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingPip = null">
      <div class="bg-white rounded-xl max-w-3xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">{{ editingPip.id ? 'Edit plan' : 'New improvement plan' }}</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingPip = null">Close</button>
        </div>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject</span>
            <select v-model="editingPip.subject_staff_id" class="input">
              <option value="">Select staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Owner (manager/HR)</span>
            <select v-model="editingPip.owner_staff_id" class="input">
              <option :value="null">—</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Title</span>
            <input v-model="editingPip.title" class="input" placeholder="e.g. Ramp up response times" />
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Reason for plan</span>
            <textarea v-model="editingPip.reason" rows="2" class="input"></textarea>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Expected outcomes</span>
            <textarea v-model="editingPip.expected_outcomes" rows="3" class="input" placeholder="What success looks like at the end of the plan"></textarea>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Support plan</span>
            <textarea v-model="editingPip.support_plan" rows="3" class="input" placeholder="Coaching, training, tools, and schedule"></textarea>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Consequences if unmet</span>
            <textarea v-model="editingPip.consequences" rows="2" class="input"></textarea>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle (optional)</span>
            <select v-model="editingPip.cycle_id" class="input">
              <option :value="null">—</option>
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Status</span>
            <select v-model="editingPip.status" class="input">
              <option v-for="s in PIP_STATUSES" :key="s" :value="s">{{ s.replaceAll('_', ' ') }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Start date</span>
            <input type="date" v-model="editingPip.start_date" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">End date</span>
            <input type="date" v-model="editingPip.end_date" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Check-in cadence (days)</span>
            <input type="number" min="1" v-model.number="editingPip.review_frequency_days" class="input" />
          </label>
          <label v-if="['succeeded','failed','cancelled'].includes(editingPip.status as string)" class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Closing summary</span>
            <textarea v-model="editingPip.closed_summary" rows="2" class="input"></textarea>
          </label>
        </div>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingPip = null">Cancel</button>
          <button class="btn-primary" @click="submitPip">Save plan</button>
        </div>
      </div>
    </div>

    <!-- Check-in modal -------------------------------------------------- -->
    <div v-if="editingCheckin" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingCheckin = null">
      <div class="bg-white rounded-xl max-w-xl w-full p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">Log check-in</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingCheckin = null">Close</button>
        </div>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Date</span>
            <input type="date" v-model="editingCheckin.checkin_date" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Status</span>
            <select v-model="editingCheckin.status" class="input">
              <option value="on_track">On track</option>
              <option value="at_risk">At risk</option>
              <option value="off_track">Off track</option>
            </select>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Manager notes</span>
            <textarea v-model="editingCheckin.manager_notes" rows="3" class="input"></textarea>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Evidence / observations</span>
            <textarea v-model="editingCheckin.evidence" rows="2" class="input"></textarea>
          </label>
        </div>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingCheckin = null">Cancel</button>
          <button class="btn-primary" @click="submitCheckin">Save</button>
        </div>
      </div>
    </div>

    <!-- Review invitation modal ---------------------------------------- -->
    <div v-if="editingReview" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingReview = null">
      <div class="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">Invite reviewers</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingReview = null">Close</button>
        </div>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="editingReview.cycle_id" class="input">
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Subject (person being reviewed)</span>
            <select v-model="editingReview.subject_staff_id" class="input">
              <option value="">Select staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Reviewer type</span>
            <select v-model="editingReview.reviewer_type" class="input">
              <option v-for="t in REVIEWER_TYPES" :key="t" :value="t">{{ REVIEWER_TYPE_LABELS[t] }}</option>
            </select>
          </label>
          <label class="block sm:col-span-2" v-if="editingReview.reviewer_type !== 'self'">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Reviewers (Ctrl/Cmd click for multiple)</span>
            <select multiple v-model="editingReview.reviewer_ids" class="input h-40">
              <option v-for="s in staffMembers.filter(s => s.id !== editingReview!.subject_staff_id)" :key="s.id" :value="s.id">{{ s.full_name }} — {{ s.role }}</option>
            </select>
            <span class="text-xs text-slate-500">One invitation is created per reviewer.</span>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Due date</span>
            <input type="date" v-model="editingReview.due_at" class="input" />
          </label>
          <label class="flex items-end gap-2 text-sm" v-if="['peer','upward','downward'].includes(editingReview.reviewer_type as string)">
            <input type="checkbox" v-model="editingReview.anonymous" />
            <span>Hide reviewer identity from subject</span>
          </label>
        </div>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingReview = null">Cancel</button>
          <button class="btn-primary" @click="submitReviewInvitations">Send invitations</button>
        </div>
      </div>
    </div>

    <!-- Cycle editor modal ---------------------------------------------- -->
    <div v-if="editingCycle" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingCycle = null">
      <div class="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">{{ editingCycle.id ? 'Edit cycle' : 'New cycle' }}</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingCycle = null">Close</button>
        </div>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Name</span>
            <input v-model="editingCycle.name" class="input" placeholder="e.g. 2026 H1 Review" />
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Description</span>
            <textarea v-model="editingCycle.description" rows="2" class="input" placeholder="Context and focus areas for this cycle"></textarea>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Period start</span>
            <input type="date" v-model="editingCycle.period_start" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Period end</span>
            <input type="date" v-model="editingCycle.period_end" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Status</span>
            <select v-model="editingCycle.status" class="input">
              <option v-for="s in CYCLE_STATUSES" :key="s" :value="s">{{ s }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Default framework</span>
            <select v-model="editingCycle.default_framework" class="input">
              <option value="okr">OKR</option>
              <option value="kpi">KPI</option>
              <option value="competency">Competency</option>
              <option value="mixed">Mixed</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Objective setting opens</span>
            <input type="date" v-model="editingCycle.objective_setting_start" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Objective setting closes</span>
            <input type="date" v-model="editingCycle.objective_setting_end" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Self-eval opens</span>
            <input type="date" v-model="editingCycle.self_eval_start" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Self-eval closes</span>
            <input type="date" v-model="editingCycle.self_eval_end" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Manager eval opens</span>
            <input type="date" v-model="editingCycle.manager_eval_start" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Manager eval closes</span>
            <input type="date" v-model="editingCycle.manager_eval_end" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">360 opens</span>
            <input type="date" v-model="editingCycle.peer_review_start" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">360 closes</span>
            <input type="date" v-model="editingCycle.peer_review_end" class="input" />
          </label>
        </div>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingCycle = null">Cancel</button>
          <button class="btn-primary" @click="submitCycle">Save</button>
        </div>
      </div>
    </div>

    <!-- Framework editor modal ----------------------------------------- -->
    <div v-if="editingFramework" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingFramework = null">
      <div class="bg-white rounded-xl max-w-xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">{{ editingFramework.id ? 'Edit framework' : 'New framework' }}</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingFramework = null">Close</button>
        </div>
        <label class="block">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Name</span>
          <input v-model="editingFramework.name" class="input" />
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Kind</span>
          <select v-model="editingFramework.kind" class="input">
            <option v-for="k in FRAMEWORK_KINDS" :key="k" :value="k">{{ k.toUpperCase() }}</option>
          </select>
        </label>
        <label class="block">
          <span class="text-xs font-medium text-slate-600 mb-1 block">Description</span>
          <textarea v-model="editingFramework.description" rows="2" class="input"></textarea>
        </label>
        <div>
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-medium text-slate-600">Scale labels (1 = lowest)</span>
            <button class="btn-secondary text-xs" @click="addScaleLabel">Add level</button>
          </div>
          <ul class="space-y-2">
            <li v-for="(label, i) in editingFramework.scoring_scale?.labels ?? []" :key="i" class="flex gap-2 items-center">
              <span class="text-xs text-slate-500 w-6 text-right">{{ i + 1 }}</span>
              <input v-model="editingFramework.scoring_scale!.labels[i]" class="input flex-1" />
              <button class="btn-secondary text-xs" @click="removeScaleLabel(i)">Remove</button>
            </li>
          </ul>
        </div>
        <label class="flex items-center gap-2 text-sm">
          <input type="checkbox" v-model="editingFramework.is_active" /> Active
        </label>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingFramework = null">Cancel</button>
          <button class="btn-primary" @click="submitFramework">Save</button>
        </div>
      </div>
    </div>

    <!-- Bulk objective upload modal ------------------------------------ -->
    <div v-if="showBulkUpload" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="showBulkUpload = false">
      <div class="bg-white rounded-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">Bulk upload objectives</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="showBulkUpload = false">Close</button>
        </div>
        <div class="text-xs text-slate-500 leading-relaxed space-y-1">
          <p>Upload a CSV file or paste contents below. The importer matches staff by <span class="font-semibold">Email</span> first, then by <span class="font-semibold">Employee Name</span>.</p>
          <p>It accepts both the simple template and the appraisal export shape (one row per Key Result, grouped automatically by Objective Title). Recognised columns include: Performance Type, Objective Title, Objective Description, Objective Status, Objective Progress, Reviewer Comment, Key Result Title/Description/Unit/Start Value/End Value, Weight, Key Result Progress.</p>
        </div>
        <div>
          <input type="file" accept=".csv,text/csv" class="block text-xs text-slate-600 file:mr-3 file:px-3 file:py-1.5 file:border-0 file:rounded-md file:bg-sycamore-50 file:text-sycamore-700 file:text-xs file:font-medium hover:file:bg-sycamore-100" @change="async (e) => { const f = (e.target as HTMLInputElement).files?.[0]; if (f) bulkObjectivesText = await f.text() }" />
        </div>
        <textarea v-model="bulkObjectivesText" rows="12" class="input font-mono text-xs" placeholder="Paste CSV contents here, or pick a file above"></textarea>
        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="showBulkUpload = false">Cancel</button>
          <button class="btn-primary" :disabled="bulkUploading || !bulkObjectivesText.trim()" @click="bulkUploadObjectives">
            {{ bulkUploading ? 'Uploading…' : 'Upload' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Objective editor modal ---------------------------------------- -->
    <div v-if="editingObjective" class="fixed inset-0 bg-slate-900/40 z-40 flex items-center justify-center p-4" @click.self="editingObjective = null">
      <div class="bg-white rounded-xl max-w-3xl w-full max-h-[90vh] overflow-y-auto p-6 space-y-4">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-semibold text-slate-900">{{ editingObjective.id ? 'Edit objective' : 'New objective' }}</h3>
          <button class="text-slate-400 hover:text-slate-600" @click="editingObjective = null">Close</button>
        </div>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Title</span>
            <input v-model="editingObjective.title" class="input" />
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Description</span>
            <textarea v-model="editingObjective.description" rows="2" class="input"></textarea>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Staff member</span>
            <select v-model="editingObjective.staff_id" class="input">
              <option value="">Select staff</option>
              <option v-for="s in staffMembers" :key="s.id" :value="s.id">{{ s.full_name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="editingObjective.cycle_id" class="input">
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Framework</span>
            <select v-model="editingObjective.framework_id" class="input">
              <option :value="null">— None —</option>
              <option v-for="f in frameworks" :key="f.id" :value="f.id">{{ f.name }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Kind</span>
            <select v-model="editingObjective.kind" class="input">
              <option v-for="k in FRAMEWORK_KINDS" :key="k" :value="k">{{ k.toUpperCase() }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Category</span>
            <select v-model="editingObjective.category" class="input">
              <option v-for="c in OBJECTIVE_CATEGORIES" :key="c" :value="c">{{ c }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Status</span>
            <select v-model="editingObjective.status" class="input">
              <option v-for="s in OBJECTIVE_STATUSES" :key="s" :value="s">{{ s.replaceAll('_', ' ') }}</option>
            </select>
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Weight (%)</span>
            <input type="number" min="0" max="100" step="1" v-model.number="editingObjective.weight" class="input" />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Progress (%)</span>
            <input type="number" min="0" max="100" step="1" v-model.number="editingObjective.progress" class="input" />
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Target</span>
            <input v-model="editingObjective.target_value" class="input" placeholder="e.g. Launch v2 with 90% on-time delivery" />
          </label>
          <label class="block sm:col-span-2">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Manager notes</span>
            <textarea v-model="editingObjective.manager_notes" rows="2" class="input"></textarea>
          </label>
        </div>

        <div class="pt-2 border-t border-slate-100">
          <div class="flex items-center justify-between mb-2">
            <div>
              <div class="text-sm font-semibold text-slate-900">Key results / metrics</div>
              <div class="text-xs text-slate-500">Add the measurable items that will determine whether this objective was achieved.</div>
            </div>
            <button class="btn-secondary text-xs" @click="addMeasure">Add measure</button>
          </div>
          <div v-if="!editingObjective._measures?.length" class="text-xs text-slate-400 italic">No measures yet.</div>
          <ul v-else class="space-y-2">
            <li v-for="(m, i) in editingObjective._measures" :key="i" class="border border-slate-200 rounded-lg p-3 space-y-2">
              <div class="grid sm:grid-cols-6 gap-2">
                <input v-model="m.label" placeholder="Label (e.g. Reduce cycle time)" class="input sm:col-span-3" />
                <input v-model="m.unit" placeholder="Unit (%, hrs, NGN)" class="input" />
                <input v-model="m.target_value" placeholder="Target" class="input" />
                <input v-model="m.current_value" placeholder="Current" class="input" />
              </div>
              <div class="grid sm:grid-cols-5 gap-2 items-center">
                <label class="text-xs text-slate-600">
                  Weight %
                  <input type="number" min="0" max="100" v-model.number="m.weight" class="input mt-0.5" />
                </label>
                <label class="text-xs text-slate-600">
                  Progress %
                  <input type="number" min="0" max="100" v-model.number="m.progress" class="input mt-0.5" />
                </label>
                <label class="text-xs text-slate-600 sm:col-span-2">
                  Status
                  <select v-model="m.status" class="input mt-0.5">
                    <option v-for="s in ['pending','on_track','at_risk','off_track','done','dropped']" :key="s" :value="s">{{ s.replaceAll('_', ' ') }}</option>
                  </select>
                </label>
                <div class="flex justify-end">
                  <button class="btn-secondary text-xs" @click="removeLocalMeasure(i)">Remove</button>
                </div>
              </div>
            </li>
          </ul>
        </div>

        <div class="flex justify-end gap-2 pt-2 border-t border-slate-100">
          <button class="btn-secondary" @click="editingObjective = null">Cancel</button>
          <button class="btn-primary" @click="submitObjective">Save objective</button>
        </div>
      </div>
    </div>
  </div>
</template>
