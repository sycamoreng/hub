import { useSupabase } from '~/utils/supabase'

export type FrameworkKind = 'okr' | 'kpi' | 'competency'
export type CycleStatus = 'draft' | 'planning' | 'active' | 'in_review' | 'closed'
export type ObjectiveStatus = 'draft' | 'active' | 'on_track' | 'at_risk' | 'off_track' | 'completed' | 'dropped'
export type MeasureStatus = 'pending' | 'on_track' | 'at_risk' | 'off_track' | 'done' | 'dropped'

export interface PerformanceCycle {
  id: string
  name: string
  description: string
  period_start: string
  period_end: string
  status: CycleStatus
  default_framework: FrameworkKind | 'mixed'
  objective_setting_start: string | null
  objective_setting_end: string | null
  self_eval_start: string | null
  self_eval_end: string | null
  manager_eval_start: string | null
  manager_eval_end: string | null
  peer_review_start: string | null
  peer_review_end: string | null
  is_primary: boolean
  created_at: string
  updated_at: string
}

export interface PerformanceFramework {
  id: string
  name: string
  kind: FrameworkKind
  description: string
  scoring_scale: { min: number; max: number; labels: string[] }
  is_active: boolean
  sort_order: number
}

export interface PerformanceObjective {
  id: string
  cycle_id: string
  staff_id: string
  framework_id: string | null
  kind: FrameworkKind
  title: string
  description: string
  category: 'business' | 'personal' | 'team' | 'company' | 'stretch'
  weight: number
  target_value: string
  status: ObjectiveStatus
  progress: number
  rating: number | null
  manager_notes: string
  staff_notes: string
  sort_order: number
  created_at: string
  updated_at: string
}

export interface PerformanceMeasure {
  id: string
  objective_id: string
  label: string
  description: string
  unit: string
  baseline_value: string
  target_value: string
  current_value: string
  weight: number
  progress: number
  status: MeasureStatus
  sort_order: number
}

export const CYCLE_STATUSES: CycleStatus[] = ['draft', 'planning', 'active', 'in_review', 'closed']
export const OBJECTIVE_STATUSES: ObjectiveStatus[] = ['draft', 'active', 'on_track', 'at_risk', 'off_track', 'completed', 'dropped']
export const OBJECTIVE_CATEGORIES = ['business', 'personal', 'team', 'company', 'stretch'] as const
export const FRAMEWORK_KINDS: FrameworkKind[] = ['okr', 'kpi', 'competency']

export type ReviewerType = 'self' | 'manager' | 'peer' | 'upward' | 'downward'
export type ReviewStatus = 'invited' | 'in_progress' | 'submitted' | 'declined' | 'cancelled'
export const REVIEWER_TYPES: ReviewerType[] = ['self', 'manager', 'peer', 'upward', 'downward']
export const REVIEW_STATUSES: ReviewStatus[] = ['invited', 'in_progress', 'submitted', 'declined', 'cancelled']

export const REVIEWER_TYPE_LABELS: Record<ReviewerType, string> = {
  self: 'Self evaluation',
  manager: 'Manager appraisal',
  peer: 'Peer review',
  upward: 'Upward review',
  downward: 'Downward review'
}

export interface PerformanceReview {
  id: string
  cycle_id: string
  subject_staff_id: string
  reviewer_staff_id: string
  reviewer_type: ReviewerType
  status: ReviewStatus
  anonymous: boolean
  invited_by: string | null
  invited_at: string
  due_at: string | null
  submitted_at: string | null
  declined_reason: string
  overall_rating: number | null
  overall_comment: string
  strengths: string
  improvements: string
  created_at: string
  updated_at: string
}

export interface PerformanceReviewRating {
  id: string
  review_id: string
  objective_id: string | null
  competency_label: string
  question: string
  score: number | null
  comment: string
  sort_order: number
}

export type RecognitionKind = 'commendation' | 'spot_award' | 'promotion' | 'bonus' | 'milestone'
export const RECOGNITION_KINDS: RecognitionKind[] = ['commendation', 'spot_award', 'promotion', 'bonus', 'milestone']
export const RECOGNITION_KIND_LABELS: Record<RecognitionKind, string> = {
  commendation: 'Commendation',
  spot_award: 'Spot award',
  promotion: 'Promotion',
  bonus: 'Bonus',
  milestone: 'Milestone'
}

export interface PerformanceRecognition {
  id: string
  subject_staff_id: string
  cycle_id: string | null
  objective_id: string | null
  kind: RecognitionKind
  title: string
  summary: string
  impact: string
  points: number
  awarded_at: string
  awarded_by: string | null
  visible_to_staff: boolean
  created_at: string
  updated_at: string
}

export type PipStatus = 'draft' | 'active' | 'on_track' | 'at_risk' | 'off_track' | 'succeeded' | 'failed' | 'cancelled'
export const PIP_STATUSES: PipStatus[] = ['draft', 'active', 'on_track', 'at_risk', 'off_track', 'succeeded', 'failed', 'cancelled']
export type PipOutcome = '' | 'succeeded' | 'extended' | 'failed' | 'cancelled'

export interface PerformanceImprovementPlan {
  id: string
  subject_staff_id: string
  cycle_id: string | null
  owner_staff_id: string | null
  title: string
  reason: string
  expected_outcomes: string
  support_plan: string
  consequences: string
  status: PipStatus
  start_date: string | null
  end_date: string | null
  review_frequency_days: number
  closed_outcome: PipOutcome
  closed_summary: string
  closed_at: string | null
  closed_by: string | null
  created_at: string
  updated_at: string
}

export type AppraisalStatus = 'not_started' | 'in_progress' | 'submitted' | 'finalized' | 'reopened'
export const APPRAISAL_STATUSES: AppraisalStatus[] = ['not_started', 'in_progress', 'submitted', 'finalized', 'reopened']
export const APPRAISAL_STATUS_LABELS: Record<AppraisalStatus, string> = {
  not_started: 'Not started',
  in_progress: 'In progress',
  submitted: 'Submitted',
  finalized: 'Finalized',
  reopened: 'Reopened'
}

export interface PerformanceAppraisal {
  id: string
  cycle_id: string
  subject_staff_id: string
  appraiser_staff_id: string | null
  status: AppraisalStatus
  objective_score: number
  behavioural_score: number
  objective_weight: number
  behavioural_weight: number
  final_score: number
  rating_label: string
  rating_tag: string
  nine_box_position: string
  notes: string
  submitted_at: string | null
  finalized_at: string | null
  finalized_by: string | null
  created_at: string
  updated_at: string
}

export type ObjectiveTemplateScope = 'company' | 'department'
export interface PerformanceObjectiveTemplate {
  id: string
  cycle_id: string | null
  scope: ObjectiveTemplateScope
  department_id: string | null
  framework_id: string | null
  kind: FrameworkKind
  category: PerformanceObjective['category']
  title: string
  description: string
  default_weight: number
  target_value: string
  sort_order: number
  is_active: boolean
}

export interface PerformanceCoreValue {
  id: string
  name: string
  description: string
  behaviour_anchors: string
  weight: number
  sort_order: number
  is_active: boolean
}

export type PipCheckinStatus = 'on_track' | 'at_risk' | 'off_track'

export interface PerformanceImprovementCheckin {
  id: string
  pip_id: string
  checkin_date: string
  status: PipCheckinStatus
  manager_notes: string
  staff_response: string
  evidence: string
  author_staff_id: string | null
  created_at: string
  updated_at: string
}

export function usePerformance() {
  const supabase = useSupabase()

  async function loadCycles(): Promise<PerformanceCycle[]> {
    const { data } = await supabase
      .from('performance_cycles')
      .select('*')
      .order('period_start', { ascending: false })
    return (data as PerformanceCycle[]) ?? []
  }

  async function loadPrimaryCycle(): Promise<PerformanceCycle | null> {
    const { data } = await supabase
      .from('performance_cycles')
      .select('*')
      .eq('is_primary', true)
      .maybeSingle()
    return (data as PerformanceCycle) ?? null
  }

  async function saveCycle(payload: Partial<PerformanceCycle>): Promise<PerformanceCycle | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_cycles')
        .update(payload)
        .eq('id', id)
        .select('*')
        .maybeSingle()
      if (error) throw error
      return data as PerformanceCycle | null
    }
    const { data, error } = await supabase
      .from('performance_cycles')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PerformanceCycle | null
  }

  async function deleteCycle(id: string) {
    const { error } = await supabase.from('performance_cycles').delete().eq('id', id)
    if (error) throw error
  }

  async function setPrimaryCycle(id: string) {
    // Clear existing primary (partial unique index requires serialised updates)
    await supabase.from('performance_cycles').update({ is_primary: false }).eq('is_primary', true)
    const { error } = await supabase.from('performance_cycles').update({ is_primary: true }).eq('id', id)
    if (error) throw error
  }

  async function loadFrameworks(): Promise<PerformanceFramework[]> {
    const { data } = await supabase
      .from('performance_frameworks')
      .select('*')
      .order('sort_order')
    return (data as PerformanceFramework[]) ?? []
  }

  async function saveFramework(payload: Partial<PerformanceFramework>): Promise<PerformanceFramework | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_frameworks')
        .update(payload)
        .eq('id', id)
        .select('*')
        .maybeSingle()
      if (error) throw error
      return data as PerformanceFramework | null
    }
    const { data, error } = await supabase
      .from('performance_frameworks')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PerformanceFramework | null
  }

  async function deleteFramework(id: string) {
    const { error } = await supabase.from('performance_frameworks').delete().eq('id', id)
    if (error) throw error
  }

  async function loadObjectives(opts: { cycleId?: string; staffId?: string } = {}) {
    let q = supabase
      .from('performance_objectives')
      .select('*, staff:staff_members(id, full_name, email, role, auth_user_id), framework:performance_frameworks(id, name, kind, scoring_scale), cycle:performance_cycles(id, name, status)')
      .order('sort_order')
      .order('created_at', { ascending: true })
    if (opts.cycleId) q = q.eq('cycle_id', opts.cycleId)
    if (opts.staffId) q = q.eq('staff_id', opts.staffId)
    const { data } = await q
    return data ?? []
  }

  async function loadMeasures(objectiveId: string): Promise<PerformanceMeasure[]> {
    const { data } = await supabase
      .from('performance_measures')
      .select('*')
      .eq('objective_id', objectiveId)
      .order('sort_order')
    return (data as PerformanceMeasure[]) ?? []
  }

  async function saveObjective(payload: Partial<PerformanceObjective>): Promise<PerformanceObjective | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_objectives')
        .update(payload)
        .eq('id', id)
        .select('*')
        .maybeSingle()
      if (error) throw error
      return data as PerformanceObjective | null
    }
    const { data, error } = await supabase
      .from('performance_objectives')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PerformanceObjective | null
  }

  async function deleteObjective(id: string) {
    const { error } = await supabase.from('performance_objectives').delete().eq('id', id)
    if (error) throw error
  }

  async function saveMeasure(payload: Partial<PerformanceMeasure>): Promise<PerformanceMeasure | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_measures')
        .update(payload)
        .eq('id', id)
        .select('*')
        .maybeSingle()
      if (error) throw error
      return data as PerformanceMeasure | null
    }
    const { data, error } = await supabase
      .from('performance_measures')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PerformanceMeasure | null
  }

  async function deleteMeasure(id: string) {
    const { error } = await supabase.from('performance_measures').delete().eq('id', id)
    if (error) throw error
  }

  async function loadReviews(opts: { cycleId?: string; subjectStaffId?: string; reviewerStaffId?: string; status?: ReviewStatus } = {}) {
    let q = supabase
      .from('performance_reviews')
      .select('*, subject:staff_members!performance_reviews_subject_staff_id_fkey(id, full_name, email, role, auth_user_id), reviewer:staff_members!performance_reviews_reviewer_staff_id_fkey(id, full_name, email, role, auth_user_id), cycle:performance_cycles(id, name, status)')
      .order('invited_at', { ascending: false })
    if (opts.cycleId) q = q.eq('cycle_id', opts.cycleId)
    if (opts.subjectStaffId) q = q.eq('subject_staff_id', opts.subjectStaffId)
    if (opts.reviewerStaffId) q = q.eq('reviewer_staff_id', opts.reviewerStaffId)
    if (opts.status) q = q.eq('status', opts.status)
    const { data } = await q
    return data ?? []
  }

  async function loadReview(id: string) {
    const { data } = await supabase
      .from('performance_reviews')
      .select('*, subject:staff_members!performance_reviews_subject_staff_id_fkey(id, full_name, email, role, auth_user_id), reviewer:staff_members!performance_reviews_reviewer_staff_id_fkey(id, full_name, email, role, auth_user_id), cycle:performance_cycles(id, name, status)')
      .eq('id', id)
      .maybeSingle()
    return data
  }

  async function loadReviewRatings(reviewId: string): Promise<PerformanceReviewRating[]> {
    const { data } = await supabase
      .from('performance_review_ratings')
      .select('*')
      .eq('review_id', reviewId)
      .order('sort_order')
    return (data as PerformanceReviewRating[]) ?? []
  }

  async function saveReview(payload: Partial<PerformanceReview>): Promise<PerformanceReview | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_reviews')
        .update(payload)
        .eq('id', id)
        .select('*')
        .maybeSingle()
      if (error) throw error
      return data as PerformanceReview | null
    }
    const { data, error } = await supabase
      .from('performance_reviews')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PerformanceReview | null
  }

  async function deleteReview(id: string) {
    const { error } = await supabase.from('performance_reviews').delete().eq('id', id)
    if (error) throw error
  }

  async function saveRating(payload: Partial<PerformanceReviewRating>): Promise<PerformanceReviewRating | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_review_ratings')
        .update(payload)
        .eq('id', id)
        .select('*')
        .maybeSingle()
      if (error) throw error
      return data as PerformanceReviewRating | null
    }
    const { data, error } = await supabase
      .from('performance_review_ratings')
      .insert(payload)
      .select('*')
      .maybeSingle()
    if (error) throw error
    return data as PerformanceReviewRating | null
  }

  async function deleteRating(id: string) {
    const { error } = await supabase.from('performance_review_ratings').delete().eq('id', id)
    if (error) throw error
  }

  async function submitReview(reviewId: string) {
    const { error } = await supabase
      .from('performance_reviews')
      .update({ status: 'submitted', submitted_at: new Date().toISOString() })
      .eq('id', reviewId)
    if (error) throw error
  }

  // Recognitions ---------------------------------------------------
  async function loadRecognitions(opts: { subjectStaffId?: string; cycleId?: string } = {}) {
    let q = supabase
      .from('performance_recognitions')
      .select('*, subject:staff_members!performance_recognitions_subject_staff_id_fkey(id, full_name, role), awarder:staff_members!performance_recognitions_awarded_by_fkey(id, full_name), cycle:performance_cycles(id, name)')
      .order('awarded_at', { ascending: false })
    if (opts.subjectStaffId) q = q.eq('subject_staff_id', opts.subjectStaffId)
    if (opts.cycleId) q = q.eq('cycle_id', opts.cycleId)
    const { data } = await q
    return data ?? []
  }

  async function saveRecognition(payload: Partial<PerformanceRecognition>): Promise<PerformanceRecognition | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_recognitions').update(payload).eq('id', id).select('*').maybeSingle()
      if (error) throw error
      return data as PerformanceRecognition | null
    }
    const { data, error } = await supabase
      .from('performance_recognitions').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceRecognition | null
  }

  async function deleteRecognition(id: string) {
    const { error } = await supabase.from('performance_recognitions').delete().eq('id', id)
    if (error) throw error
  }

  // PIPs -----------------------------------------------------------
  async function loadPips(opts: { subjectStaffId?: string; status?: PipStatus } = {}) {
    let q = supabase
      .from('performance_improvement_plans')
      .select('*, subject:staff_members!performance_improvement_plans_subject_staff_id_fkey(id, full_name, role, auth_user_id), owner:staff_members!performance_improvement_plans_owner_staff_id_fkey(id, full_name), cycle:performance_cycles(id, name)')
      .order('created_at', { ascending: false })
    if (opts.subjectStaffId) q = q.eq('subject_staff_id', opts.subjectStaffId)
    if (opts.status) q = q.eq('status', opts.status)
    const { data } = await q
    return data ?? []
  }

  async function loadPip(id: string) {
    const { data } = await supabase
      .from('performance_improvement_plans')
      .select('*, subject:staff_members!performance_improvement_plans_subject_staff_id_fkey(id, full_name, role, auth_user_id), owner:staff_members!performance_improvement_plans_owner_staff_id_fkey(id, full_name), cycle:performance_cycles(id, name)')
      .eq('id', id).maybeSingle()
    return data
  }

  async function savePip(payload: Partial<PerformanceImprovementPlan>): Promise<PerformanceImprovementPlan | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_improvement_plans').update(payload).eq('id', id).select('*').maybeSingle()
      if (error) throw error
      return data as PerformanceImprovementPlan | null
    }
    const { data, error } = await supabase
      .from('performance_improvement_plans').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceImprovementPlan | null
  }

  async function deletePip(id: string) {
    const { error } = await supabase.from('performance_improvement_plans').delete().eq('id', id)
    if (error) throw error
  }

  async function loadPipCheckins(pipId: string): Promise<PerformanceImprovementCheckin[]> {
    const { data } = await supabase
      .from('performance_improvement_checkins')
      .select('*')
      .eq('pip_id', pipId)
      .order('checkin_date', { ascending: false })
    return (data as PerformanceImprovementCheckin[]) ?? []
  }

  async function saveCheckin(payload: Partial<PerformanceImprovementCheckin>): Promise<PerformanceImprovementCheckin | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_improvement_checkins').update(payload).eq('id', id).select('*').maybeSingle()
      if (error) throw error
      return data as PerformanceImprovementCheckin | null
    }
    const { data, error } = await supabase
      .from('performance_improvement_checkins').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceImprovementCheckin | null
  }

  async function deleteCheckin(id: string) {
    const { error } = await supabase.from('performance_improvement_checkins').delete().eq('id', id)
    if (error) throw error
  }

  // Objective templates -------------------------------------------
  async function loadObjectiveTemplates(opts: { cycleId?: string; scope?: ObjectiveTemplateScope; departmentId?: string } = {}) {
    let q = supabase
      .from('performance_objective_templates')
      .select('*, department:departments(id, name), cycle:performance_cycles(id, name)')
      .order('sort_order')
      .order('created_at', { ascending: true })
    if (opts.cycleId) q = q.eq('cycle_id', opts.cycleId)
    if (opts.scope) q = q.eq('scope', opts.scope)
    if (opts.departmentId) q = q.eq('department_id', opts.departmentId)
    const { data } = await q
    return data ?? []
  }

  async function saveObjectiveTemplate(payload: Partial<PerformanceObjectiveTemplate>): Promise<PerformanceObjectiveTemplate | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_objective_templates').update(payload).eq('id', id).select('*').maybeSingle()
      if (error) throw error
      return data as PerformanceObjectiveTemplate | null
    }
    const { data, error } = await supabase
      .from('performance_objective_templates').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceObjectiveTemplate | null
  }

  async function deleteObjectiveTemplate(id: string) {
    const { error } = await supabase.from('performance_objective_templates').delete().eq('id', id)
    if (error) throw error
  }

  async function adoptObjectiveTemplate(templateId: string, staffId: string, cycleId: string): Promise<PerformanceObjective | null> {
    const { data: t, error: e1 } = await supabase
      .from('performance_objective_templates').select('*').eq('id', templateId).maybeSingle()
    if (e1 || !t) throw (e1 ?? new Error('template missing'))
    const tpl = t as PerformanceObjectiveTemplate
    const { data, error } = await supabase
      .from('performance_objectives')
      .insert({
        cycle_id: cycleId,
        staff_id: staffId,
        framework_id: tpl.framework_id,
        kind: tpl.kind,
        title: tpl.title,
        description: tpl.description,
        category: tpl.category,
        weight: tpl.default_weight,
        target_value: tpl.target_value,
        status: 'active'
      })
      .select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceObjective | null
  }

  // Core values ----------------------------------------------------
  async function loadCoreValues(): Promise<PerformanceCoreValue[]> {
    const { data } = await supabase
      .from('performance_core_values').select('*').order('sort_order')
    return (data as PerformanceCoreValue[]) ?? []
  }

  async function saveCoreValue(payload: Partial<PerformanceCoreValue>): Promise<PerformanceCoreValue | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_core_values').update(payload).eq('id', id).select('*').maybeSingle()
      if (error) throw error
      return data as PerformanceCoreValue | null
    }
    const { data, error } = await supabase
      .from('performance_core_values').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceCoreValue | null
  }

  async function deleteCoreValue(id: string) {
    const { error } = await supabase.from('performance_core_values').delete().eq('id', id)
    if (error) throw error
  }

  // Appraisals ----------------------------------------------------
  async function loadAppraisals(opts: { cycleId?: string; subjectStaffId?: string; appraiserStaffId?: string; status?: AppraisalStatus } = {}) {
    let q = supabase
      .from('performance_appraisals')
      .select('*, subject:staff_members!performance_appraisals_subject_staff_id_fkey(id, full_name, email, role, department_id, auth_user_id), appraiser:staff_members!performance_appraisals_appraiser_staff_id_fkey(id, full_name, email, role), cycle:performance_cycles(id, name, status)')
      .order('updated_at', { ascending: false })
    if (opts.cycleId) q = q.eq('cycle_id', opts.cycleId)
    if (opts.subjectStaffId) q = q.eq('subject_staff_id', opts.subjectStaffId)
    if (opts.appraiserStaffId) q = q.eq('appraiser_staff_id', opts.appraiserStaffId)
    if (opts.status) q = q.eq('status', opts.status)
    const { data } = await q
    return data ?? []
  }

  async function loadAppraisalForSubject(cycleId: string, subjectStaffId: string) {
    const { data } = await supabase
      .from('performance_appraisals')
      .select('*, appraiser:staff_members!performance_appraisals_appraiser_staff_id_fkey(id, full_name, email, role)')
      .eq('cycle_id', cycleId)
      .eq('subject_staff_id', subjectStaffId)
      .maybeSingle()
    return data
  }

  async function saveAppraisal(payload: Partial<PerformanceAppraisal>): Promise<PerformanceAppraisal | null> {
    const id = payload.id
    if (id) {
      const { data, error } = await supabase
        .from('performance_appraisals').update(payload).eq('id', id).select('*').maybeSingle()
      if (error) throw error
      return data as PerformanceAppraisal | null
    }
    const { data, error } = await supabase
      .from('performance_appraisals').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as PerformanceAppraisal | null
  }

  async function deleteAppraisal(id: string) {
    const { error } = await supabase.from('performance_appraisals').delete().eq('id', id)
    if (error) throw error
  }

  async function recomputeAppraisal(id: string): Promise<PerformanceAppraisal | null> {
    const { data, error } = await supabase.rpc('compute_appraisal_score', { p_appraisal_id: id })
    if (error) throw error
    return (data as PerformanceAppraisal) ?? null
  }

  async function reassignAppraiser(appraisalId: string, newAppraiserStaffId: string | null): Promise<PerformanceAppraisal | null> {
    const { data, error } = await supabase.rpc('admin_reassign_appraiser', {
      p_appraisal_id: appraisalId,
      p_new_appraiser_staff_id: newAppraiserStaffId
    })
    if (error) throw error
    return (data as PerformanceAppraisal) ?? null
  }

  return {
    loadObjectiveTemplates,
    saveObjectiveTemplate,
    deleteObjectiveTemplate,
    adoptObjectiveTemplate,
    loadCoreValues,
    saveCoreValue,
    deleteCoreValue,
    loadAppraisals,
    loadAppraisalForSubject,
    saveAppraisal,
    deleteAppraisal,
    recomputeAppraisal,
    reassignAppraiser,
    loadReviews,
    loadReview,
    loadReviewRatings,
    saveReview,
    deleteReview,
    saveRating,
    deleteRating,
    submitReview,
    loadCycles,
    loadPrimaryCycle,
    saveCycle,
    deleteCycle,
    setPrimaryCycle,
    loadFrameworks,
    saveFramework,
    deleteFramework,
    loadObjectives,
    loadMeasures,
    saveObjective,
    deleteObjective,
    saveMeasure,
    deleteMeasure,
    loadRecognitions,
    saveRecognition,
    deleteRecognition,
    loadPips,
    loadPip,
    savePip,
    deletePip,
    loadPipCheckins,
    saveCheckin,
    deleteCheckin
  }
}
