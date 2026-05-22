<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'
import {
  usePerformance,
  REVIEWER_TYPE_LABELS,
  REVIEWER_TYPES,
  REVIEW_STATUSES,
  RECOGNITION_KIND_LABELS,
  OBJECTIVE_CATEGORIES,
  FRAMEWORK_KINDS,
  type PerformanceCycle,
  type PerformanceMeasure,
  type PerformanceObjective,
  type ReviewerType,
  type ReviewStatus,
  type RecognitionKind,
  type FrameworkKind
} from '~/composables/usePerformance'

const supabase = useSupabase()
const toast = useToast()
const { user } = useAuth()
const { loadCycles, loadPrimaryCycle, loadObjectives, loadMeasures, saveObjective, deleteObjective, saveMeasure, loadReviews, saveReview, loadRecognitions, saveRecognition, loadPips, loadPipCheckins, saveCheckin, loadAppraisalForSubject, loadObjectiveTemplates, adoptObjectiveTemplate } = usePerformance()

type Tab = 'objectives' | 'reviews' | 'team' | 'recognition'

const loading = ref(true)
const tab = ref<Tab>('objectives')
const cycles = ref<PerformanceCycle[]>([])
const selectedCycleId = ref<string>('')
const staffRow = ref<any>(null)
const objectives = ref<any[]>([])
const measuresByObjective = ref<Record<string, PerformanceMeasure[]>>({})
const saving = ref<Record<string, boolean>>({})
const reviewsAssigned = ref<any[]>([])
const reviewsAboutMe = ref<any[]>([])
const myRecognitions = ref<any[]>([])
const myPips = ref<any[]>([])
const expandedPipId = ref<string>('')
const myPipCheckins = ref<any[]>([])
const myAppraisal = ref<any>(null)
const objectiveTemplates = ref<any[]>([])
const adoptingTemplateId = ref<string>('')

const adoptedTemplateTitles = computed(() => new Set(objectives.value.map((o: any) => (o.title ?? '').toLowerCase())))
const availableTemplates = computed(() => {
  const deptId = staffRow.value?.department_id ?? null
  return objectiveTemplates.value.filter((t: any) => {
    if (!t.is_active) return false
    if (t.scope === 'department' && t.department_id && t.department_id !== deptId) return false
    if (adoptedTemplateTitles.value.has((t.title ?? '').toLowerCase())) return false
    return true
  })
})

async function reloadTemplates() {
  if (!selectedCycleId.value) { objectiveTemplates.value = []; return }
  const all = await loadObjectiveTemplates({ cycleId: selectedCycleId.value })
  const cycleless = await loadObjectiveTemplates({})
  const merged = [...all, ...cycleless.filter((t: any) => !t.cycle_id)]
  const seen = new Set<string>()
  objectiveTemplates.value = merged.filter((t: any) => {
    if (seen.has(t.id)) return false
    seen.add(t.id)
    return true
  })
}

async function adoptTemplate(t: any) {
  if (!staffRow.value || !selectedCycleId.value) return
  adoptingTemplateId.value = t.id
  try {
    await adoptObjectiveTemplate(t.id, staffRow.value.id, selectedCycleId.value)
    toast.success(`Adopted "${t.title}"`)
    await reloadObjectives()
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not adopt')
  } finally {
    adoptingTemplateId.value = ''
  }
}
const responseDraft = ref<Record<string, string>>({})

const DRAFT_STORAGE_KEY = 'performance:drafts:v1'
type DraftPayload = {
  responseDraft?: Record<string, string>
  objectiveForm?: any
  objectiveOpen?: boolean
  inviteForm?: any
  inviteOpen?: boolean
  recogniseForm?: any
  recogniseOpen?: boolean
  tab?: Tab
  selectedCycleId?: string
  expandedReportId?: string
  savedAt?: string
}
const hasUnsavedDrafts = computed(() => {
  const hasTypedResponse = Object.values(responseDraft.value).some(v => (v ?? '').trim().length > 0)
  const o = objectiveForm.value
  const hasObjectiveDraft = objectiveOpen.value || !!(o?.title || o?.description || o?.target_value)
  const i = inviteForm.value
  const hasInviteDraft = inviteOpen.value || !!(i?.subject_staff_id || i?.reviewer_staff_id || i?.due_at)
  const r = recogniseForm.value
  const hasRecogniseDraft = recogniseOpen.value || !!(r?.subject_staff_id || r?.title || r?.summary || r?.impact)
  return hasTypedResponse || hasObjectiveDraft || hasInviteDraft || hasRecogniseDraft
})

function saveDraftsToStorage() {
  if (typeof window === 'undefined') return
  const payload: DraftPayload = {
    responseDraft: responseDraft.value,
    objectiveForm: objectiveForm.value,
    objectiveOpen: objectiveOpen.value,
    inviteForm: inviteForm.value,
    inviteOpen: inviteOpen.value,
    recogniseForm: recogniseForm.value,
    recogniseOpen: recogniseOpen.value,
    tab: tab.value,
    selectedCycleId: selectedCycleId.value,
    expandedReportId: expandedReportId.value,
    savedAt: new Date().toISOString()
  }
  try { window.localStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(payload)) } catch {}
}

function restoreDraftsFromStorage() {
  if (typeof window === 'undefined') return
  try {
    const raw = window.localStorage.getItem(DRAFT_STORAGE_KEY)
    if (!raw) return
    const d = JSON.parse(raw) as DraftPayload
    if (d.responseDraft) responseDraft.value = d.responseDraft
    if (d.objectiveForm) objectiveForm.value = { ...objectiveForm.value, ...d.objectiveForm }
    if (d.objectiveOpen) objectiveOpen.value = d.objectiveOpen
    if (d.inviteForm) inviteForm.value = { ...inviteForm.value, ...d.inviteForm }
    if (d.inviteOpen) inviteOpen.value = d.inviteOpen
    if (d.recogniseForm) recogniseForm.value = { ...recogniseForm.value, ...d.recogniseForm }
    if (d.recogniseOpen) recogniseOpen.value = d.recogniseOpen
    if (d.tab) tab.value = d.tab
    if (d.selectedCycleId) selectedCycleId.value = d.selectedCycleId
    if (d.expandedReportId) expandedReportId.value = d.expandedReportId
    if (hasUnsavedDrafts.value) {
      toast.push({ type: 'info', title: 'Drafts restored', message: 'Picked up where you left off.' })
    }
  } catch {}
}

function clearDraftStorage() {
  if (typeof window === 'undefined') return
  try { window.localStorage.removeItem(DRAFT_STORAGE_KEY) } catch {}
}

// Team (manager) view
const directReports = ref<any[]>([])
const teamObjectives = ref<any[]>([])
const teamReviews = ref<any[]>([])
const teamSelectedStaffId = ref<string>('')

// Manager actions modals
const inviteOpen = ref(false)
const inviteForm = ref<{ subject_staff_id: string; reviewer_type: ReviewerType; reviewer_staff_id: string; due_at: string; anonymous: boolean }>({
  subject_staff_id: '', reviewer_type: 'manager', reviewer_staff_id: '', due_at: '', anonymous: false
})
const inviteSaving = ref(false)
const colleagueOptions = ref<any[]>([])

const recogniseOpen = ref(false)
const recogniseForm = ref<{ subject_staff_id: string; kind: RecognitionKind; title: string; summary: string; impact: string; points: number; visible_to_staff: boolean }>({
  subject_staff_id: '', kind: 'commendation', title: '', summary: '', impact: '', points: 0, visible_to_staff: true
})
const recogniseSaving = ref(false)

// Team member expansion + objective editor
const expandedReportId = ref<string>('')
const objectiveOpen = ref(false)
const objectiveForm = ref<{ id?: string; staff_id: string; title: string; description: string; kind: FrameworkKind; category: 'business' | 'personal' | 'team' | 'company' | 'stretch'; weight: number; target_value: string }>({
  staff_id: '', title: '', description: '', kind: 'okr', category: 'business', weight: 25, target_value: ''
})
const objectiveSaving = ref(false)

// Filters
const assignedStatusFilter = ref<ReviewStatus | ''>('')
const assignedTypeFilter = ref<ReviewerType | ''>('')
const aboutMeTypeFilter = ref<ReviewerType | ''>('')
const teamStatusFilter = ref<ReviewStatus | ''>('')

async function resolveStaff() {
  if (!user.value) return
  const { data } = await supabase
    .from('staff_members')
    .select('id, full_name, email, role')
    .eq('auth_user_id', user.value.id)
    .maybeSingle()
  staffRow.value = data
}

async function loadDirectReports() {
  if (!staffRow.value) { directReports.value = []; return }
  const { data, error } = await supabase
    .from('staff_members')
    .select('id, full_name, email, role, auth_user_id')
    .eq('manager_id', staffRow.value.id)
    .order('full_name')
  if (error) {
    directReports.value = []
    toast.push({ type: 'error', title: 'Could not load your team', message: error.message })
    return
  }
  const rows = data ?? []
  const authIds = rows.map(r => r.auth_user_id).filter(Boolean) as string[]
  let avatars: Record<string, string> = {}
  if (authIds.length) {
    const { data: profiles } = await supabase
      .from('user_profiles')
      .select('user_id, avatar_url')
      .in('user_id', authIds)
    for (const p of profiles ?? []) {
      if (p.avatar_url) avatars[p.user_id] = p.avatar_url
    }
  }
  directReports.value = rows.map(r => ({ ...r, avatar_url: r.auth_user_id ? avatars[r.auth_user_id] ?? '' : '' }))
}

async function loadAll() {
  loading.value = true
  try {
    await resolveStaff()
    if (!staffRow.value) {
      objectives.value = []
      return
    }
    const allCycles = await loadCycles()
    cycles.value = allCycles.filter(c => c.status !== 'draft')
    if (!selectedCycleId.value) {
      const primary = await loadPrimaryCycle()
      selectedCycleId.value = primary?.id ?? cycles.value[0]?.id ?? ''
    }
    await Promise.all([
      reloadObjectives(),
      reloadReviews(),
      reloadAppraisal(),
      reloadTemplates(),
      loadDirectReports()
    ])
  } finally {
    loading.value = false
  }
}

async function reloadReviews() {
  if (!staffRow.value) return
  const [assigned, about, recs, pips] = await Promise.all([
    loadReviews({ reviewerStaffId: staffRow.value.id }),
    loadReviews({ subjectStaffId: staffRow.value.id, status: 'submitted' }),
    loadRecognitions({ subjectStaffId: staffRow.value.id }),
    loadPips({ subjectStaffId: staffRow.value.id })
  ])
  reviewsAssigned.value = assigned.filter((r: any) => r.status !== 'cancelled')
  reviewsAboutMe.value = about.filter((r: any) => r.reviewer_staff_id !== staffRow.value.id)
  myRecognitions.value = recs.filter((r: any) => r.visible_to_staff)
  myPips.value = pips.filter((p: any) => p.status !== 'draft')
}

async function reloadTeam() {
  if (!directReports.value.length) {
    teamObjectives.value = []
    teamReviews.value = []
    return
  }
  const reportIds = directReports.value.map(r => r.id)
  const tObjectives: any[] = []
  for (const id of reportIds) {
    const rows = await loadObjectives({ cycleId: selectedCycleId.value, staffId: id })
    tObjectives.push(...rows)
  }
  teamObjectives.value = tObjectives

  const { data: tReviews } = await supabase
    .from('performance_reviews')
    .select('*, subject:staff_members!performance_reviews_subject_staff_id_fkey(id, full_name), reviewer:staff_members!performance_reviews_reviewer_staff_id_fkey(id, full_name), cycle:performance_cycles(id, name)')
    .in('subject_staff_id', reportIds)
    .eq('cycle_id', selectedCycleId.value)
    .order('invited_at', { ascending: false })
  teamReviews.value = tReviews ?? []
}

watch(tab, async (t) => {
  if (t === 'team' && selectedCycleId.value) await reloadTeam()
})

async function togglePip(p: any) {
  if (expandedPipId.value === p.id) {
    expandedPipId.value = ''
    return
  }
  expandedPipId.value = p.id
  myPipCheckins.value = await loadPipCheckins(p.id)
}

async function saveStaffResponse(c: any) {
  const text = responseDraft.value[c.id] ?? c.staff_response ?? ''
  try {
    await saveCheckin({ id: c.id, staff_response: text })
    toast.push({ type: 'success', title: 'Response saved', message: '' })
    delete responseDraft.value[c.id]
    myPipCheckins.value = await loadPipCheckins(c.pip_id)
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}

async function reloadObjectives() {
  if (!staffRow.value || !selectedCycleId.value) { objectives.value = []; return }
  objectives.value = await loadObjectives({ cycleId: selectedCycleId.value, staffId: staffRow.value.id })
  const map: Record<string, PerformanceMeasure[]> = {}
  await Promise.all(objectives.value.map(async (o: any) => {
    map[o.id] = await loadMeasures(o.id)
  }))
  measuresByObjective.value = map
}

async function reloadAppraisal() {
  if (!staffRow.value || !selectedCycleId.value) { myAppraisal.value = null; return }
  myAppraisal.value = await loadAppraisalForSubject(selectedCycleId.value, staffRow.value.id)
}

watch(selectedCycleId, async () => {
  await reloadObjectives()
  await reloadAppraisal()
  await reloadTemplates()
  if (tab.value === 'team') await reloadTeam()
})

onMounted(async () => {
  await loadAll()
  restoreDraftsFromStorage()
})

watch([responseDraft, objectiveForm, objectiveOpen, inviteForm, inviteOpen, recogniseForm, recogniseOpen, tab, selectedCycleId, expandedReportId], () => {
  saveDraftsToStorage()
}, { deep: true })

if (typeof window !== 'undefined') {
  const beforeUnload = (e: BeforeUnloadEvent) => {
    saveDraftsToStorage()
    if (hasUnsavedDrafts.value) {
      e.preventDefault()
      e.returnValue = ''
    }
  }
  window.addEventListener('beforeunload', beforeUnload)
  onBeforeUnmount(() => {
    saveDraftsToStorage()
    window.removeEventListener('beforeunload', beforeUnload)
  })
}

onBeforeRouteLeave((_to, _from, next) => {
  saveDraftsToStorage()
  if (hasUnsavedDrafts.value) {
    const ok = typeof window !== 'undefined'
      ? window.confirm('You have unsaved drafts on this page. They will be kept locally and restored when you return. Leave now?')
      : true
    if (!ok) return next(false)
  }
  next()
})

const selectedCycle = computed(() => cycles.value.find(c => c.id === selectedCycleId.value) ?? null)
const canUpdate = computed(() => {
  const status = selectedCycle.value?.status
  return status === 'planning' || status === 'active' || status === 'in_review'
})

const totalWeight = computed(() => objectives.value.reduce((sum, o: any) => sum + Number(o.weight || 0), 0))
const overallProgress = computed(() => {
  if (!objectives.value.length) return 0
  const weighted = objectives.value.reduce((sum, o: any) => sum + (Number(o.weight || 0) * Number(o.progress || 0)) / 100, 0)
  const totalW = totalWeight.value || 100
  return Math.round((weighted / totalW) * 100)
})

const filteredAssigned = computed(() => {
  return reviewsAssigned.value.filter(r => {
    if (assignedStatusFilter.value && r.status !== assignedStatusFilter.value) return false
    if (assignedTypeFilter.value && r.reviewer_type !== assignedTypeFilter.value) return false
    if (selectedCycleId.value && r.cycle_id !== selectedCycleId.value) return false
    return true
  })
})

const filteredAboutMe = computed(() => {
  return reviewsAboutMe.value.filter(r => {
    if (aboutMeTypeFilter.value && r.reviewer_type !== aboutMeTypeFilter.value) return false
    if (selectedCycleId.value && r.cycle_id !== selectedCycleId.value) return false
    return true
  })
})

const filteredTeamReviews = computed(() => {
  return teamReviews.value.filter(r => {
    if (teamSelectedStaffId.value && r.subject_staff_id !== teamSelectedStaffId.value) return false
    if (teamStatusFilter.value && r.status !== teamStatusFilter.value) return false
    return true
  })
})

const filteredTeamObjectives = computed(() => {
  return teamObjectives.value.filter(o => {
    if (teamSelectedStaffId.value && o.staff_id !== teamSelectedStaffId.value) return false
    return true
  })
})

const teamReviewStats = computed(() => {
  const out: Record<string, { invited: number; in_progress: number; submitted: number; declined: number; total: number }> = {}
  for (const r of directReports.value) {
    out[r.id] = { invited: 0, in_progress: 0, submitted: 0, declined: 0, total: 0 }
  }
  for (const rv of teamReviews.value) {
    const bucket = out[rv.subject_staff_id]
    if (!bucket) continue
    bucket.total += 1
    if (rv.status === 'invited') bucket.invited += 1
    else if (rv.status === 'in_progress') bucket.in_progress += 1
    else if (rv.status === 'submitted') bucket.submitted += 1
    else if (rv.status === 'declined') bucket.declined += 1
  }
  return out
})

const hasTeam = computed(() => directReports.value.length > 0)

async function updateObjectiveProgress(o: PerformanceObjective, newProgress: number) {
  if (!canUpdate.value) return
  saving.value[o.id] = true
  try {
    await saveObjective({ id: o.id, progress: newProgress })
    toast.push({ type: 'success', title: 'Progress saved', message: o.title })
    await reloadObjectives()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  } finally {
    saving.value[o.id] = false
  }
}

async function updateObjectiveNotes(o: PerformanceObjective, notes: string) {
  if (!canUpdate.value) return
  saving.value[o.id] = true
  try {
    await saveObjective({ id: o.id, staff_notes: notes })
    toast.push({ type: 'success', title: 'Notes saved', message: o.title })
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  } finally {
    saving.value[o.id] = false
  }
}

async function updateMeasure(m: PerformanceMeasure, patch: Partial<PerformanceMeasure>) {
  if (!canUpdate.value) return
  saving.value[m.id] = true
  try {
    await saveMeasure({ id: m.id, ...patch })
    toast.push({ type: 'success', title: 'Measure updated', message: m.label })
    await reloadObjectives()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  } finally {
    saving.value[m.id] = false
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
    closed: 'badge-slate',
    pending: 'badge-slate',
    done: 'badge-blue',
    invited: 'badge-blue',
    in_progress: 'badge-amber',
    submitted: 'badge-green',
    declined: 'badge-rose',
    cancelled: 'badge-slate'
  }
  return map[status] ?? 'badge-slate'
}

function categoryStyle(cat: string) {
  const styles: Record<string, { border: string; bg: string; text: string; dot: string }> = {
    company: { border: 'border-l-sycamore-500', bg: 'bg-sycamore-50/30', text: 'text-sycamore-700', dot: 'bg-sycamore-500' },
    team: { border: 'border-l-amber-400', bg: 'bg-amber-50/30', text: 'text-amber-700', dot: 'bg-amber-400' },
    business: { border: 'border-l-sky-400', bg: 'bg-sky-50/30', text: 'text-sky-700', dot: 'bg-sky-400' },
    personal: { border: 'border-l-leaf-400', bg: 'bg-leaf-50/30', text: 'text-leaf-700', dot: 'bg-leaf-400' },
    stretch: { border: 'border-l-rose-400', bg: 'bg-rose-50/30', text: 'text-rose-700', dot: 'bg-rose-400' }
  }
  return styles[cat] ?? styles.business
}

function progressColor(progress: number) {
  if (progress >= 75) return 'bg-leaf-500'
  if (progress >= 50) return 'bg-sycamore-500'
  if (progress >= 25) return 'bg-amber-400'
  return 'bg-slate-300'
}

async function ensureColleagues() {
  if (colleagueOptions.value.length) return
  const { data } = await supabase
    .from('staff_members')
    .select('id, full_name, role')
    .order('full_name')
  colleagueOptions.value = (data ?? []).filter((r: any) => r.id !== staffRow.value?.id)
}

async function openInvite(reportId: string) {
  await ensureColleagues()
  inviteForm.value = {
    subject_staff_id: reportId,
    reviewer_type: 'manager',
    reviewer_staff_id: staffRow.value?.id ?? '',
    due_at: '',
    anonymous: false
  }
  inviteOpen.value = true
}

async function submitInvite() {
  if (!selectedCycleId.value) return
  const f = inviteForm.value
  if (!f.subject_staff_id || !f.reviewer_staff_id) {
    toast.push({ type: 'error', title: 'Missing details', message: 'Pick a reviewer.' })
    return
  }
  if (f.reviewer_type === 'self' && f.reviewer_staff_id !== f.subject_staff_id) {
    toast.push({ type: 'error', title: 'Self review', message: 'A self review must have the subject as reviewer.' })
    return
  }
  inviteSaving.value = true
  try {
    await saveReview({
      cycle_id: selectedCycleId.value,
      subject_staff_id: f.subject_staff_id,
      reviewer_staff_id: f.reviewer_staff_id,
      reviewer_type: f.reviewer_type,
      status: 'invited',
      anonymous: f.anonymous,
      invited_by: staffRow.value?.id ?? null,
      invited_at: new Date().toISOString(),
      due_at: f.due_at || null
    })
    toast.push({ type: 'success', title: 'Review invited', message: REVIEWER_TYPE_LABELS[f.reviewer_type] })
    inviteOpen.value = false
    await reloadTeam()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not invite', message: e?.message ?? 'Unexpected error' })
  } finally {
    inviteSaving.value = false
  }
}

function openRecognise(reportId: string) {
  recogniseForm.value = {
    subject_staff_id: reportId,
    kind: 'commendation',
    title: '',
    summary: '',
    impact: '',
    points: 0,
    visible_to_staff: true
  }
  recogniseOpen.value = true
}

async function submitRecognition() {
  const f = recogniseForm.value
  if (!f.subject_staff_id || !f.title.trim()) {
    toast.push({ type: 'error', title: 'Missing details', message: 'Recognition title is required.' })
    return
  }
  recogniseSaving.value = true
  try {
    await saveRecognition({
      subject_staff_id: f.subject_staff_id,
      cycle_id: selectedCycleId.value || null,
      kind: f.kind,
      title: f.title.trim(),
      summary: f.summary.trim(),
      impact: f.impact.trim(),
      points: Number(f.points) || 0,
      awarded_at: new Date().toISOString(),
      awarded_by: staffRow.value?.id ?? null,
      visible_to_staff: f.visible_to_staff
    })
    toast.push({ type: 'success', title: 'Recognition sent', message: f.title })
    recogniseOpen.value = false
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  } finally {
    recogniseSaving.value = false
  }
}

function openNewObjective(reportId: string) {
  objectiveForm.value = {
    staff_id: reportId,
    title: '',
    description: '',
    kind: 'okr',
    category: 'business',
    weight: 25,
    target_value: ''
  }
  objectiveOpen.value = true
}

function openEditObjective(o: any) {
  objectiveForm.value = {
    id: o.id,
    staff_id: o.staff_id,
    title: o.title ?? '',
    description: o.description ?? '',
    kind: o.kind ?? 'okr',
    category: o.category ?? 'business',
    weight: Number(o.weight ?? 0),
    target_value: o.target_value ?? ''
  }
  objectiveOpen.value = true
}

async function submitObjective() {
  const f = objectiveForm.value
  if (!f.title.trim()) {
    toast.push({ type: 'error', title: 'Missing title', message: 'Objective title is required.' })
    return
  }
  if (!selectedCycleId.value) return
  objectiveSaving.value = true
  try {
    await saveObjective({
      id: f.id,
      cycle_id: selectedCycleId.value,
      staff_id: f.staff_id,
      kind: f.kind,
      title: f.title.trim(),
      description: f.description.trim(),
      category: f.category,
      weight: Number(f.weight) || 0,
      target_value: f.target_value.trim(),
      status: f.id ? undefined : 'active'
    })
    toast.push({ type: 'success', title: f.id ? 'Objective updated' : 'Objective created', message: f.title })
    objectiveOpen.value = false
    await reloadTeam()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  } finally {
    objectiveSaving.value = false
  }
}

async function removeObjective(o: any) {
  const ok = await toast.confirm({
    title: 'Remove this objective?',
    message: `"${o.title}" will be removed from ${o.staff?.full_name ?? 'this report'}.`,
    confirmLabel: 'Remove',
    variant: 'danger'
  })
  if (!ok) return
  try {
    await deleteObjective(o.id)
    toast.push({ type: 'success', title: 'Objective removed', message: o.title })
    await reloadTeam()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not remove', message: e?.message ?? 'Unexpected error' })
  }
}

async function updateReportObjectiveProgress(o: any, patch: Partial<PerformanceObjective>) {
  try {
    await saveObjective({ id: o.id, ...patch })
    toast.push({ type: 'success', title: 'Saved', message: o.title })
    await reloadTeam()
  } catch (e: any) {
    toast.push({ type: 'error', title: 'Could not save', message: e?.message ?? 'Unexpected error' })
  }
}

function toggleReport(reportId: string) {
  expandedReportId.value = expandedReportId.value === reportId ? '' : reportId
}

function reportObjectives(staffId: string) {
  return teamObjectives.value.filter(o => o.staff_id === staffId)
}

function reportReviews(staffId: string) {
  return teamReviews.value.filter(r => r.subject_staff_id === staffId)
}

function cycleObjectiveProgress(staffId: string) {
  const objs = teamObjectives.value.filter(o => o.staff_id === staffId)
  if (!objs.length) return null
  const totalW = objs.reduce((s, o: any) => s + Number(o.weight || 0), 0) || 100
  const weighted = objs.reduce((s, o: any) => s + (Number(o.weight || 0) * Number(o.progress || 0)) / 100, 0)
  return Math.round((weighted / totalW) * 100)
}
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-10 space-y-6">
    <header>
      <h1 class="text-3xl font-bold text-slate-900">Performance</h1>
      <p class="text-sm text-slate-500 mt-1">Track objectives, complete appraisals, and support your team's growth.</p>
    </header>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading your performance data...</div>

    <div v-else-if="!staffRow" class="card p-8 text-center text-sm text-slate-500">
      Your staff profile isn't set up yet. Contact HR to be added.
    </div>

    <template v-else>
      <div v-if="!cycles.length" class="card p-8 text-center text-sm text-slate-500">
        No performance cycles have been opened yet.
      </div>

      <template v-else>
        <div class="card p-5 flex flex-col sm:flex-row gap-4 sm:items-center sm:justify-between">
          <label class="flex-1 min-w-0">
            <span class="text-xs font-medium text-slate-600 mb-1 block">Cycle</span>
            <select v-model="selectedCycleId" class="input">
              <option v-for="c in cycles" :key="c.id" :value="c.id">{{ c.name }} — {{ c.status }}</option>
            </select>
          </label>
          <div v-if="selectedCycle" class="text-xs text-slate-500 flex flex-wrap gap-3">
            <span class="badge" :class="statusBadge(selectedCycle.status)">{{ selectedCycle.status }}</span>
            <span>{{ new Date(selectedCycle.period_start).toLocaleDateString('en-GB') }} — {{ new Date(selectedCycle.period_end).toLocaleDateString('en-GB') }}</span>
          </div>
        </div>

        <article v-if="myAppraisal" class="card overflow-hidden">
          <div class="h-1.5 bg-gradient-to-r from-sycamore-500 via-leaf-400 to-amber-400" />
          <div class="p-5 sm:p-6">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <h3 class="text-base font-semibold text-slate-900">Your appraisal</h3>
                <p class="text-xs text-slate-500 mt-0.5">
                  Status:
                  <span class="font-medium text-slate-700">{{ myAppraisal.status.replace('_', ' ') }}</span>
                  <template v-if="myAppraisal.appraiser">
                    · Appraiser: <span class="font-medium text-slate-700">{{ myAppraisal.appraiser.full_name }}</span>
                  </template>
                </p>
              </div>
              <div v-if="myAppraisal.rating_label" class="text-right">
                <div class="text-[11px] uppercase tracking-wide text-slate-400">Rating</div>
                <div class="text-lg font-bold text-sycamore-700">{{ myAppraisal.rating_label }}</div>
                <div v-if="myAppraisal.rating_tag" class="text-xs text-slate-500">{{ myAppraisal.rating_tag }}</div>
              </div>
            </div>
            <div class="grid grid-cols-3 gap-3 mt-4">
              <div class="rounded-xl border border-sycamore-200 bg-sycamore-50/50 p-3">
                <div class="text-[11px] uppercase tracking-wide text-sycamore-600 font-semibold">Objective</div>
                <div class="text-xl font-bold text-sycamore-900 mt-0.5">{{ Number(myAppraisal.objective_score).toFixed(2) }}</div>
                <div class="text-[11px] text-sycamore-600/70">weight {{ Number(myAppraisal.objective_weight).toFixed(0) }}%</div>
              </div>
              <div class="rounded-xl border border-amber-200 bg-amber-50/50 p-3">
                <div class="text-[11px] uppercase tracking-wide text-amber-600 font-semibold">Behavioural</div>
                <div class="text-xl font-bold text-amber-900 mt-0.5">{{ Number(myAppraisal.behavioural_score).toFixed(2) }}</div>
                <div class="text-[11px] text-amber-600/70">weight {{ Number(myAppraisal.behavioural_weight).toFixed(0) }}%</div>
              </div>
              <div class="rounded-xl border border-leaf-200 bg-leaf-50/50 p-3">
                <div class="text-[11px] uppercase tracking-wide text-leaf-600 font-semibold">Final</div>
                <div class="text-xl font-bold text-leaf-900 mt-0.5">{{ Number(myAppraisal.final_score).toFixed(2) }}</div>
                <div class="text-[11px] text-leaf-600/70">out of 5.00</div>
              </div>
            </div>
            <div v-if="myAppraisal.nine_box_position" class="mt-3 text-xs text-slate-500">
              9-Box: <span class="font-medium text-slate-700">{{ myAppraisal.nine_box_position }}</span>
            </div>
            <p v-if="myAppraisal.notes" class="mt-3 text-sm text-slate-600 whitespace-pre-line border-t border-slate-100 pt-3">{{ myAppraisal.notes }}</p>
          </div>
        </article>

        <nav class="flex flex-wrap gap-1 border-b border-slate-200">
          <button
            v-for="t in [
              { id: 'objectives', label: 'My objectives' },
              { id: 'reviews', label: 'Appraisals' },
              ...(hasTeam ? [{ id: 'team', label: 'My team' }] : []),
              { id: 'recognition', label: 'Recognition & PIP' }
            ] as { id: Tab; label: string }[]"
            :key="t.id"
            type="button"
            class="px-3 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
            :class="tab === t.id ? 'border-sycamore-600 text-sycamore-800' : 'border-transparent text-slate-500 hover:text-slate-800'"
            @click="tab = t.id"
          >
            {{ t.label }}
          </button>
        </nav>

        <!-- OBJECTIVES TAB -->
        <template v-if="tab === 'objectives'">
          <div v-if="objectives.length" class="card p-5 space-y-2">
            <div class="flex items-center justify-between text-sm">
              <div class="font-semibold text-slate-900">Overall weighted progress</div>
              <div class="text-slate-600">{{ overallProgress }}%</div>
            </div>
            <div class="w-full h-2 rounded-full bg-slate-100 overflow-hidden">
              <div class="h-full bg-sycamore-500 transition-all" :style="{ width: `${overallProgress}%` }" />
            </div>
            <div class="text-xs" :class="Math.abs(totalWeight - 100) < 0.01 ? 'text-leaf-700' : 'text-amber-700'">
              Total weight {{ totalWeight.toFixed(0) }}%<span v-if="Math.abs(totalWeight - 100) > 0.01"> · should sum to 100% — ask your manager to rebalance</span>
            </div>
          </div>

          <article v-if="availableTemplates.length" class="card overflow-hidden">
            <div class="bg-gradient-to-r from-sycamore-50 to-leaf-50 border-b border-sycamore-100 px-5 py-4">
              <h3 class="text-sm font-bold text-sycamore-900">Cascading objectives</h3>
              <p class="text-xs text-sycamore-700/70">Adopt company and department-level objectives into your cycle.</p>
            </div>
            <ul class="divide-y divide-slate-100 p-0">
              <li
                v-for="t in availableTemplates"
                :key="t.id"
                class="flex flex-wrap items-start justify-between gap-3 p-4 sm:p-5"
              >
                <div class="min-w-0 flex-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="w-2 h-2 rounded-full" :class="t.scope === 'company' ? 'bg-sycamore-500' : 'bg-leaf-500'" />
                    <span class="font-semibold text-sm text-slate-900">{{ t.title }}</span>
                    <span class="badge" :class="t.scope === 'company' ? 'badge-blue' : 'badge-green'">{{ t.scope }}</span>
                    <span class="badge badge-slate text-[10px] uppercase">{{ t.kind }}</span>
                    <span class="badge badge-slate">Weight {{ Number(t.default_weight).toFixed(0) }}%</span>
                  </div>
                  <p v-if="t.description" class="text-xs text-slate-600 mt-1 ml-4">{{ t.description }}</p>
                </div>
                <button
                  type="button"
                  class="btn-primary text-xs !bg-leaf-600 hover:!bg-leaf-700"
                  :disabled="adoptingTemplateId === t.id"
                  @click="adoptTemplate(t)"
                >
                  {{ adoptingTemplateId === t.id ? 'Adopting...' : 'Adopt' }}
                </button>
              </li>
            </ul>
          </article>

          <div v-if="!objectives.length" class="card p-8 text-center text-sm text-slate-500">
            No objectives assigned to you in this cycle yet.
          </div>

          <!-- Category legend -->
          <div v-if="objectives.length" class="flex flex-wrap gap-3 text-xs">
            <span class="inline-flex items-center gap-1.5 text-slate-500">
              <span class="w-2.5 h-2.5 rounded-full bg-sycamore-500" /> Company
            </span>
            <span class="inline-flex items-center gap-1.5 text-slate-500">
              <span class="w-2.5 h-2.5 rounded-full bg-amber-400" /> Team
            </span>
            <span class="inline-flex items-center gap-1.5 text-slate-500">
              <span class="w-2.5 h-2.5 rounded-full bg-sky-400" /> Business
            </span>
            <span class="inline-flex items-center gap-1.5 text-slate-500">
              <span class="w-2.5 h-2.5 rounded-full bg-leaf-400" /> Personal
            </span>
            <span class="inline-flex items-center gap-1.5 text-slate-500">
              <span class="w-2.5 h-2.5 rounded-full bg-rose-400" /> Stretch
            </span>
          </div>

          <article
            v-for="o in objectives"
            :key="o.id"
            class="card overflow-hidden border-l-4 space-y-0"
            :class="categoryStyle(o.category).border"
          >
            <div class="p-5 space-y-4" :class="categoryStyle(o.category).bg">
              <header class="flex flex-wrap items-start justify-between gap-3">
                <div class="min-w-0 flex-1 space-y-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="w-2 h-2 rounded-full" :class="categoryStyle(o.category).dot" />
                    <h3 class="text-base font-semibold text-slate-900">{{ o.title }}</h3>
                  </div>
                  <div class="flex flex-wrap items-center gap-2 ml-4">
                    <span class="badge badge-slate uppercase text-[10px]">{{ o.kind }}</span>
                    <span class="badge" :class="statusBadge(o.status)">{{ o.status.replaceAll('_', ' ') }}</span>
                    <span class="text-[11px] font-semibold capitalize" :class="categoryStyle(o.category).text">{{ o.category }}</span>
                  </div>
                  <p v-if="o.description" class="text-sm text-slate-600 ml-4">{{ o.description }}</p>
                  <div v-if="o.target_value" class="text-xs text-slate-500 ml-4"><span class="font-semibold">Target:</span> {{ o.target_value }}</div>
                  <div class="flex gap-3 text-xs text-slate-500 ml-4">
                    <span>Weight {{ Number(o.weight).toFixed(0) }}%</span>
                    <span v-if="o.rating !== null">Manager rating {{ Number(o.rating).toFixed(1) }}</span>
                  </div>
                </div>
                <div class="text-right shrink-0">
                  <div class="text-2xl font-bold text-slate-900">{{ Number(o.progress).toFixed(0) }}%</div>
                  <div class="text-[10px] text-slate-400 uppercase tracking-wide">progress</div>
                </div>
              </header>

              <div class="space-y-1.5">
                <input
                  type="range" min="0" max="100" step="5"
                  :value="o.progress"
                  :disabled="!canUpdate || saving[o.id]"
                  class="w-full accent-sycamore-600"
                  @change="(e) => updateObjectiveProgress(o, Number((e.target as HTMLInputElement).value))"
                />
                <div class="w-full h-2 rounded-full bg-slate-100 overflow-hidden">
                  <div class="h-full transition-all rounded-full" :class="progressColor(Number(o.progress) || 0)" :style="{ width: `${Math.min(100, Number(o.progress) || 0)}%` }" />
                </div>
              </div>
            </div>

            <div v-if="measuresByObjective[o.id]?.length" class="border-t border-slate-100 px-5 py-4 space-y-3">
              <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Measures</div>
              <ul class="space-y-3">
                <li v-for="m in measuresByObjective[o.id]" :key="m.id" class="space-y-2">
                  <div class="flex flex-wrap items-center gap-2 text-sm">
                    <span class="font-medium text-slate-900">{{ m.label }}</span>
                    <span class="badge badge-slate">{{ m.unit || '—' }}</span>
                    <span class="badge" :class="statusBadge(m.status)">{{ m.status.replaceAll('_', ' ') }}</span>
                    <span v-if="m.target_value" class="text-xs text-slate-500">Target: {{ m.target_value }}</span>
                  </div>
                  <div class="grid sm:grid-cols-3 gap-2 items-end text-xs">
                    <label>
                      Current
                      <input
                        :value="m.current_value"
                        :disabled="!canUpdate || saving[m.id]"
                        class="input mt-0.5"
                        @change="(e) => updateMeasure(m, { current_value: (e.target as HTMLInputElement).value })"
                      />
                    </label>
                    <label>
                      Progress %
                      <input
                        type="number" min="0" max="100" step="5"
                        :value="m.progress"
                        :disabled="!canUpdate || saving[m.id]"
                        class="input mt-0.5"
                        @change="(e) => updateMeasure(m, { progress: Number((e.target as HTMLInputElement).value) })"
                      />
                    </label>
                    <label>
                      Status
                      <select
                        :value="m.status"
                        :disabled="!canUpdate || saving[m.id]"
                        class="input mt-0.5"
                        @change="(e) => updateMeasure(m, { status: (e.target as HTMLSelectElement).value as any })"
                      >
                        <option v-for="s in ['pending','on_track','at_risk','off_track','done','dropped']" :key="s" :value="s">{{ s.replaceAll('_', ' ') }}</option>
                      </select>
                    </label>
                  </div>
                </li>
              </ul>
            </div>

            <div class="border-t border-slate-100 px-5 py-4 space-y-3">
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">My notes to my manager</span>
                <textarea
                  :value="o.staff_notes"
                  rows="3"
                  :disabled="!canUpdate"
                  class="input"
                  placeholder="What progress have you made? What do you need support on?"
                  @change="(e) => updateObjectiveNotes(o, (e.target as HTMLTextAreaElement).value)"
                ></textarea>
              </label>

              <div v-if="o.manager_notes" class="bg-slate-50 border border-slate-200 rounded-lg p-3">
                <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">Manager notes</div>
                <p class="text-sm text-slate-700 whitespace-pre-wrap">{{ o.manager_notes }}</p>
              </div>
            </div>
          </article>
        </template>

        <!-- REVIEWS TAB -->
        <template v-if="tab === 'reviews'">
          <section class="card overflow-hidden">
            <div class="bg-sycamore-50 border-b border-sycamore-100 px-5 py-3.5">
              <h2 class="text-sm font-bold text-sycamore-900">Reviews to complete</h2>
              <p class="text-xs text-sycamore-700/70 mt-0.5">Self-evaluations, manager appraisals, peer and upward reviews assigned to you.</p>
            </div>
            <div class="p-5 space-y-3">
            <header class="flex flex-wrap items-end justify-between gap-3">
              <div></div>
              <div class="flex flex-wrap gap-2">
                <select v-model="assignedTypeFilter" class="input text-xs w-auto">
                  <option value="">All types</option>
                  <option v-for="t in REVIEWER_TYPES" :key="t" :value="t">{{ REVIEWER_TYPE_LABELS[t] }}</option>
                </select>
                <select v-model="assignedStatusFilter" class="input text-xs w-auto">
                  <option value="">All statuses</option>
                  <option v-for="s in REVIEW_STATUSES" :key="s" :value="s">{{ s.replaceAll('_', ' ') }}</option>
                </select>
              </div>
            </header>
            <ul v-if="filteredAssigned.length" class="divide-y divide-slate-100">
              <li v-for="r in filteredAssigned" :key="r.id" class="py-3 flex flex-wrap items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="text-sm font-semibold text-slate-900">
                      {{ r.reviewer_type === 'self' ? 'Your self-evaluation' : `Reviewing ${r.subject?.full_name ?? 'colleague'}` }}
                    </span>
                    <span class="badge badge-slate">{{ REVIEWER_TYPE_LABELS[r.reviewer_type as ReviewerType] }}</span>
                    <span class="badge" :class="statusBadge(r.status)">{{ r.status.replaceAll('_', ' ') }}</span>
                    <span v-if="r.anonymous" class="badge badge-blue">Anonymous</span>
                  </div>
                  <div class="text-xs text-slate-500 mt-1">
                    Cycle: {{ r.cycle?.name }}<span v-if="r.due_at"> · Due {{ new Date(r.due_at).toLocaleDateString('en-GB') }}</span>
                  </div>
                </div>
                <NuxtLink :to="`/performance/review/${r.id}`" class="btn-primary text-xs">
                  {{ r.status === 'submitted' ? 'View' : 'Open' }}
                </NuxtLink>
              </li>
            </ul>
            <p v-else class="text-sm text-slate-400 italic">Nothing matches these filters.</p>
            </div>
          </section>

          <section class="card overflow-hidden">
            <div class="bg-leaf-50 border-b border-leaf-100 px-5 py-3.5">
              <h2 class="text-sm font-bold text-leaf-900">Feedback about me</h2>
              <p class="text-xs text-leaf-700/70 mt-0.5">Reviews others have submitted. Anonymous feedback hides reviewer identity.</p>
            </div>
            <div class="p-5 space-y-3">
            <header class="flex flex-wrap items-end justify-between gap-3">
              <div></div>
              <select v-model="aboutMeTypeFilter" class="input text-xs w-auto">
                <option value="">All types</option>
                <option v-for="t in REVIEWER_TYPES" :key="t" :value="t">{{ REVIEWER_TYPE_LABELS[t] }}</option>
              </select>
            </header>
            <ul v-if="filteredAboutMe.length" class="divide-y divide-slate-100">
              <li v-for="r in filteredAboutMe" :key="r.id" class="py-3 flex flex-wrap items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="text-sm font-semibold text-slate-900">
                      {{ r.anonymous ? 'Anonymous reviewer' : (r.reviewer?.full_name ?? 'Reviewer') }}
                    </span>
                    <span class="badge badge-slate">{{ REVIEWER_TYPE_LABELS[r.reviewer_type as ReviewerType] }}</span>
                  </div>
                  <div class="text-xs text-slate-500 mt-1">
                    Cycle: {{ r.cycle?.name }} · Submitted {{ r.submitted_at ? new Date(r.submitted_at).toLocaleDateString('en-GB') : '' }}
                  </div>
                </div>
                <NuxtLink :to="`/performance/review/${r.id}`" class="btn-secondary text-xs">View</NuxtLink>
              </li>
            </ul>
            <p v-else class="text-sm text-slate-400 italic">No feedback yet in this cycle.</p>
            </div>
          </section>
        </template>

        <!-- TEAM (MANAGER) TAB -->
        <template v-if="tab === 'team' && hasTeam">
          <section class="card p-5 space-y-4">
            <header class="flex flex-wrap items-end justify-between gap-3">
              <div>
                <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Your team</h2>
                <p class="text-xs text-slate-500 mt-1">Click a report to set objectives, invite reviews, and give recognition.</p>
              </div>
              <select v-model="teamSelectedStaffId" class="input text-xs w-auto">
                <option value="">All reports</option>
                <option v-for="r in directReports" :key="r.id" :value="r.id">{{ r.full_name }}</option>
              </select>
            </header>

            <div class="space-y-3">
              <article
                v-for="r in directReports"
                v-show="!teamSelectedStaffId || teamSelectedStaffId === r.id"
                :key="r.id"
                class="border border-slate-200 rounded-xl overflow-hidden transition-shadow"
                :class="expandedReportId === r.id ? 'shadow-md' : 'hover:shadow-sm'"
              >
                <button
                  type="button"
                  class="w-full p-4 flex flex-wrap items-center gap-3 text-left hover:bg-slate-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-sycamore-400 transition-colors"
                  :aria-expanded="expandedReportId === r.id"
                  @click="toggleReport(r.id)"
                >
                  <div class="w-11 h-11 rounded-full bg-sycamore-100 text-sycamore-800 flex items-center justify-center text-sm font-semibold overflow-hidden shrink-0">
                    <img v-if="r.avatar_url" :src="r.avatar_url" :alt="r.full_name" class="w-full h-full object-cover" />
                    <span v-else>{{ r.full_name?.[0] ?? '?' }}</span>
                  </div>
                  <div class="min-w-0 flex-1">
                    <div class="text-sm font-semibold text-slate-900 flex items-center gap-2">
                      {{ r.full_name }}
                      <span class="text-[11px] font-normal text-sycamore-700">{{ expandedReportId === r.id ? 'Tap to close' : 'Tap to manage' }}</span>
                    </div>
                    <div class="text-xs text-slate-500">{{ r.role }}</div>
                  </div>
                  <div class="flex items-center gap-2 text-xs text-slate-600">
                    <span v-if="cycleObjectiveProgress(r.id) !== null" class="hidden sm:inline-flex items-center gap-2">
                      <span class="w-20 h-1.5 rounded-full bg-slate-100 overflow-hidden">
                        <span class="block h-full bg-sycamore-500" :style="{ width: `${cycleObjectiveProgress(r.id)}%` }" />
                      </span>
                      <span>{{ cycleObjectiveProgress(r.id) }}%</span>
                    </span>
                    <span class="badge badge-slate">{{ reportObjectives(r.id).length }} obj</span>
                    <span v-if="teamReviewStats[r.id]?.submitted" class="badge badge-green">{{ teamReviewStats[r.id].submitted }} submitted</span>
                    <span v-if="teamReviewStats[r.id]?.in_progress" class="badge badge-amber">{{ teamReviewStats[r.id].in_progress }} in progress</span>
                    <span v-if="teamReviewStats[r.id]?.invited" class="badge badge-blue">{{ teamReviewStats[r.id].invited }} invited</span>
                  </div>
                  <svg
                    xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
                    stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
                    class="w-5 h-5 text-slate-400 transition-transform duration-200 shrink-0"
                    :class="expandedReportId === r.id ? 'rotate-180' : ''"
                  >
                    <polyline points="6 9 12 15 18 9" />
                  </svg>
                </button>

                <div v-if="expandedReportId === r.id" class="border-t border-slate-100 bg-slate-50/60 p-4 space-y-5">
                  <div class="flex flex-wrap gap-2">
                    <button type="button" class="btn-primary text-xs" @click.stop="openNewObjective(r.id)">
                      + New objective
                    </button>
                    <button type="button" class="btn-secondary text-xs" @click.stop="openInvite(r.id)">
                      Invite review
                    </button>
                    <button type="button" class="btn-secondary text-xs" @click.stop="openRecognise(r.id)">
                      Give recognition
                    </button>
                  </div>

                  <div>
                    <div class="flex items-center justify-between mb-2">
                      <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Objectives in this cycle</div>
                      <div class="text-xs text-slate-500">
                        Weight total: {{ reportObjectives(r.id).reduce((s, o: any) => s + Number(o.weight || 0), 0).toFixed(0) }}%
                      </div>
                    </div>
                    <ul v-if="reportObjectives(r.id).length" class="space-y-2">
                      <li
                        v-for="o in reportObjectives(r.id)"
                        :key="o.id"
                        class="bg-white border border-slate-200 rounded-lg p-3 space-y-2"
                      >
                        <div class="flex flex-wrap items-start justify-between gap-2">
                          <div class="min-w-0 flex-1">
                            <div class="flex flex-wrap items-center gap-2">
                              <span class="text-sm font-semibold text-slate-900">{{ o.title }}</span>
                              <span class="badge badge-slate uppercase text-[10px]">{{ o.kind }}</span>
                              <span class="badge" :class="statusBadge(o.status)">{{ o.status.replaceAll('_', ' ') }}</span>
                              <span class="badge badge-slate">{{ o.category }}</span>
                            </div>
                            <p v-if="o.description" class="text-xs text-slate-600 mt-1">{{ o.description }}</p>
                            <div class="text-xs text-slate-500 mt-1">Weight {{ Number(o.weight).toFixed(0) }}% · Progress {{ Number(o.progress).toFixed(0) }}%</div>
                          </div>
                          <div class="flex gap-1 shrink-0">
                            <button type="button" class="text-xs text-slate-600 hover:text-sycamore-700 underline underline-offset-2" @click.stop="openEditObjective(o)">Edit</button>
                            <span class="text-slate-300">·</span>
                            <button type="button" class="text-xs text-rose-600 hover:text-rose-800 underline underline-offset-2" @click.stop="removeObjective(o)">Remove</button>
                          </div>
                        </div>
                        <div class="grid sm:grid-cols-2 gap-3 items-end">
                          <label class="block">
                            <span class="text-[11px] text-slate-500 mb-0.5 block">Status</span>
                            <select
                              :value="o.status" class="input text-xs"
                              @change="(e) => updateReportObjectiveProgress(o, { status: (e.target as HTMLSelectElement).value as any })"
                            >
                              <option v-for="s in ['draft','active','on_track','at_risk','off_track','completed','dropped']" :key="s" :value="s">{{ s.replaceAll('_', ' ') }}</option>
                            </select>
                          </label>
                          <label class="block">
                            <span class="text-[11px] text-slate-500 mb-0.5 block">Manager notes</span>
                            <input
                              :value="o.manager_notes" class="input text-xs"
                              placeholder="Quick note for this report"
                              @change="(e) => updateReportObjectiveProgress(o, { manager_notes: (e.target as HTMLInputElement).value })"
                            />
                          </label>
                        </div>
                      </li>
                    </ul>
                    <p v-else class="text-xs text-slate-400 italic">
                      No objectives yet. Use "New objective" above to set one.
                    </p>
                  </div>

                  <div>
                    <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-2">Appraisals</div>
                    <ul v-if="reportReviews(r.id).length" class="space-y-2">
                      <li
                        v-for="rv in reportReviews(r.id)"
                        :key="rv.id"
                        class="bg-white border border-slate-200 rounded-lg p-3 flex flex-wrap items-center justify-between gap-2"
                      >
                        <div class="min-w-0">
                          <div class="flex flex-wrap items-center gap-2">
                            <span class="text-sm text-slate-700">
                              {{ rv.anonymous ? 'Anonymous reviewer' : rv.reviewer?.full_name }}
                            </span>
                            <span class="badge badge-slate">{{ REVIEWER_TYPE_LABELS[rv.reviewer_type as ReviewerType] }}</span>
                            <span class="badge" :class="statusBadge(rv.status)">{{ rv.status.replaceAll('_', ' ') }}</span>
                          </div>
                          <div class="text-[11px] text-slate-500 mt-0.5">
                            <span v-if="rv.due_at">Due {{ new Date(rv.due_at).toLocaleDateString('en-GB') }}</span>
                            <span v-if="rv.submitted_at"> · Submitted {{ new Date(rv.submitted_at).toLocaleDateString('en-GB') }}</span>
                          </div>
                        </div>
                        <NuxtLink
                          v-if="rv.status === 'submitted' && !rv.anonymous"
                          :to="`/performance/review/${rv.id}`"
                          class="btn-secondary text-xs"
                        >
                          View
                        </NuxtLink>
                      </li>
                    </ul>
                    <p v-else class="text-xs text-slate-400 italic">
                      No appraisals yet. Use "Invite review" above to request one.
                    </p>
                  </div>
                </div>
              </article>
            </div>
          </section>
        </template>

        <!-- RECOGNITION & PIP TAB -->
        <template v-if="tab === 'recognition'">
          <section v-if="myRecognitions.length" class="card p-5 space-y-3">
            <header>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Recognition you've earned</h2>
              <p class="text-xs text-slate-500 mt-1">Moments your managers and peers have celebrated.</p>
            </header>
            <ul class="space-y-2">
              <li v-for="r in myRecognitions" :key="r.id" class="border border-slate-200 rounded-lg p-3 space-y-1">
                <div class="flex flex-wrap items-center gap-2">
                  <span class="text-sm font-semibold text-slate-900">{{ r.title }}</span>
                  <span class="badge badge-blue">{{ RECOGNITION_KIND_LABELS[r.kind as RecognitionKind] }}</span>
                  <span v-if="r.points" class="badge badge-green">+{{ r.points }} pts</span>
                </div>
                <p v-if="r.summary" class="text-sm text-slate-700">{{ r.summary }}</p>
                <p v-if="r.impact" class="text-xs text-slate-500">Impact: {{ r.impact }}</p>
                <div class="text-xs text-slate-500">
                  {{ new Date(r.awarded_at).toLocaleDateString('en-GB') }}
                  <span v-if="r.awarder"> &middot; from {{ r.awarder.full_name }}</span>
                </div>
              </li>
            </ul>
          </section>

          <section v-if="myPips.length" class="card p-5 space-y-3">
            <header>
              <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-500">Improvement plan</h2>
              <p class="text-xs text-slate-500 mt-1">Focus areas your manager has set up to help you succeed. Respond to each check-in.</p>
            </header>
            <article v-for="p in myPips" :key="p.id" class="border border-slate-200 rounded-lg overflow-hidden">
              <header class="p-3 flex flex-wrap items-start justify-between gap-2 cursor-pointer" @click="togglePip(p)">
                <div class="min-w-0 flex-1 space-y-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <span class="text-sm font-semibold text-slate-900">{{ p.title }}</span>
                    <span class="badge" :class="statusBadge(p.status)">{{ p.status.replaceAll('_', ' ') }}</span>
                  </div>
                  <div class="text-xs text-slate-500">
                    {{ p.start_date ? new Date(p.start_date).toLocaleDateString('en-GB') : '—' }}
                    —
                    {{ p.end_date ? new Date(p.end_date).toLocaleDateString('en-GB') : '—' }}
                  </div>
                </div>
              </header>
              <div v-if="expandedPipId === p.id" class="border-t border-slate-100 p-3 space-y-3 text-sm">
                <div v-if="p.expected_outcomes"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500 block mb-1">Expected outcomes</span>{{ p.expected_outcomes }}</div>
                <div v-if="p.support_plan"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500 block mb-1">Support</span>{{ p.support_plan }}</div>
                <div>
                  <div class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-1">Check-ins</div>
                  <ul class="space-y-2">
                    <li v-for="c in myPipCheckins" :key="c.id" class="border border-slate-200 rounded-lg p-3 space-y-2">
                      <div class="flex items-center justify-between gap-2">
                        <div class="text-xs text-slate-500">{{ new Date(c.checkin_date).toLocaleDateString('en-GB') }}</div>
                        <span class="badge" :class="statusBadge(c.status)">{{ c.status.replaceAll('_', ' ') }}</span>
                      </div>
                      <div v-if="c.manager_notes" class="text-sm text-slate-700">{{ c.manager_notes }}</div>
                      <label class="block">
                        <span class="text-xs text-slate-500 mb-1 block">Your response</span>
                        <textarea
                          :value="responseDraft[c.id] ?? c.staff_response"
                          rows="2" class="input"
                          @input="(e) => responseDraft[c.id] = (e.target as HTMLTextAreaElement).value"
                          @change="saveStaffResponse(c)"
                        ></textarea>
                      </label>
                    </li>
                    <li v-if="!myPipCheckins.length" class="text-xs text-slate-400 italic">No check-ins logged yet.</li>
                  </ul>
                </div>
              </div>
            </article>
          </section>

          <div v-if="!myRecognitions.length && !myPips.length" class="card p-8 text-center text-sm text-slate-500">
            No recognition or improvement plans for you right now.
          </div>
        </template>
      </template>
    </template>

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="inviteOpen" class="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm" @click.self="inviteOpen = false">
          <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
            <div class="p-6 space-y-3">
              <h3 class="text-base font-semibold text-slate-900">Invite a review</h3>
              <p class="text-sm text-slate-600">Assign an appraisal for this cycle. The reviewer will be notified.</p>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Review type</span>
                <select v-model="inviteForm.reviewer_type" class="input">
                  <option v-for="t in REVIEWER_TYPES" :key="t" :value="t">{{ REVIEWER_TYPE_LABELS[t] }}</option>
                </select>
              </label>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Reviewer</span>
                <select v-model="inviteForm.reviewer_staff_id" class="input">
                  <option value="" disabled>Pick a colleague</option>
                  <option v-if="inviteForm.reviewer_type === 'self'" :value="inviteForm.subject_staff_id">The staff member (self)</option>
                  <template v-else>
                    <option :value="staffRow?.id">{{ staffRow?.full_name }} (me)</option>
                    <option v-for="c in colleagueOptions" :key="c.id" :value="c.id">{{ c.full_name }}<span v-if="c.role"> — {{ c.role }}</span></option>
                  </template>
                </select>
              </label>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Due date (optional)</span>
                <input type="date" v-model="inviteForm.due_at" class="input" />
              </label>
              <label class="flex items-center gap-2 text-sm text-slate-700">
                <input type="checkbox" v-model="inviteForm.anonymous" />
                Keep reviewer identity anonymous from subject
              </label>
            </div>
            <div class="bg-slate-50 px-6 py-3.5 flex items-center justify-end gap-2 border-t border-slate-100">
              <button type="button" class="btn-secondary" @click="inviteOpen = false">Cancel</button>
              <button type="button" class="btn-primary" :disabled="inviteSaving" @click="submitInvite">
                {{ inviteSaving ? 'Sending...' : 'Send invite' }}
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="objectiveOpen" class="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm" @click.self="objectiveOpen = false">
          <div class="bg-white rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden">
            <div class="p-6 space-y-3 max-h-[80vh] overflow-y-auto">
              <h3 class="text-base font-semibold text-slate-900">{{ objectiveForm.id ? 'Edit objective' : 'Set a new objective' }}</h3>
              <p class="text-sm text-slate-600">Objectives shape how this report is measured in the current cycle.</p>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Title</span>
                <input v-model="objectiveForm.title" class="input" placeholder="e.g. Ship Q3 reporting dashboard" />
              </label>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Description</span>
                <textarea v-model="objectiveForm.description" rows="3" class="input" placeholder="Why it matters and what success looks like"></textarea>
              </label>
              <div class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs font-medium text-slate-600 mb-1 block">Framework</span>
                  <select v-model="objectiveForm.kind" class="input">
                    <option v-for="k in FRAMEWORK_KINDS" :key="k" :value="k">{{ k.toUpperCase() }}</option>
                  </select>
                </label>
                <label class="block">
                  <span class="text-xs font-medium text-slate-600 mb-1 block">Category</span>
                  <select v-model="objectiveForm.category" class="input">
                    <option v-for="c in OBJECTIVE_CATEGORIES" :key="c" :value="c">{{ c }}</option>
                  </select>
                </label>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs font-medium text-slate-600 mb-1 block">Weight (%)</span>
                  <input type="number" min="0" max="100" step="5" v-model="objectiveForm.weight" class="input" />
                </label>
                <label class="block">
                  <span class="text-xs font-medium text-slate-600 mb-1 block">Target</span>
                  <input v-model="objectiveForm.target_value" class="input" placeholder="e.g. 20 new customers" />
                </label>
              </div>
            </div>
            <div class="bg-slate-50 px-6 py-3.5 flex items-center justify-end gap-2 border-t border-slate-100">
              <button type="button" class="btn-secondary" @click="objectiveOpen = false">Cancel</button>
              <button type="button" class="btn-primary" :disabled="objectiveSaving" @click="submitObjective">
                {{ objectiveSaving ? 'Saving...' : (objectiveForm.id ? 'Save changes' : 'Create objective') }}
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>

    <Teleport to="body">
      <Transition name="fade">
        <div v-if="recogniseOpen" class="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm" @click.self="recogniseOpen = false">
          <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
            <div class="p-6 space-y-3">
              <h3 class="text-base font-semibold text-slate-900">Give recognition</h3>
              <p class="text-sm text-slate-600">Celebrate a win. Visible on the staff member's performance page when shared.</p>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Kind</span>
                <select v-model="recogniseForm.kind" class="input">
                  <option v-for="[k, lbl] in Object.entries(RECOGNITION_KIND_LABELS)" :key="k" :value="k">{{ lbl }}</option>
                </select>
              </label>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Title</span>
                <input v-model="recogniseForm.title" class="input" placeholder="e.g. Delivered the Q2 migration ahead of schedule" />
              </label>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Summary</span>
                <textarea v-model="recogniseForm.summary" rows="2" class="input" placeholder="What they did"></textarea>
              </label>
              <label class="block">
                <span class="text-xs font-medium text-slate-600 mb-1 block">Impact</span>
                <textarea v-model="recogniseForm.impact" rows="2" class="input" placeholder="Why it mattered"></textarea>
              </label>
              <div class="grid grid-cols-2 gap-3">
                <label class="block">
                  <span class="text-xs font-medium text-slate-600 mb-1 block">Points</span>
                  <input type="number" min="0" step="5" v-model="recogniseForm.points" class="input" />
                </label>
                <label class="flex items-end gap-2 text-sm text-slate-700 pb-2">
                  <input type="checkbox" v-model="recogniseForm.visible_to_staff" />
                  Share with staff
                </label>
              </div>
            </div>
            <div class="bg-slate-50 px-6 py-3.5 flex items-center justify-end gap-2 border-t border-slate-100">
              <button type="button" class="btn-secondary" @click="recogniseOpen = false">Cancel</button>
              <button type="button" class="btn-primary" :disabled="recogniseSaving" @click="submitRecognition">
                {{ recogniseSaving ? 'Saving...' : 'Send recognition' }}
              </button>
            </div>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.fade-enter-active, .fade-leave-active { transition: opacity 0.2s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
