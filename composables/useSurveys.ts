import { useSupabase } from '~/utils/supabase'

export type SurveyStatus = 'draft' | 'open' | 'closed'
export type QuestionType = 'rating' | 'single_choice' | 'multiple_choice' | 'text' | 'department_rating'
export type AudienceType = 'all' | 'departments' | 'staff'

export interface Survey {
  id: string
  title: string
  description: string
  status: SurveyStatus
  is_anonymous: boolean
  created_by: string | null
  opens_at: string | null
  closes_at: string | null
  created_at: string
  audience_type: AudienceType
  audience_department_ids: string[]
  audience_staff_ids: string[]
}

export interface SurveyQuestion {
  id: string
  survey_id: string
  prompt: string
  type: QuestionType
  options: string[]
  scale_max: number
  required: boolean
  sort_order: number
  excluded_department_ids: string[]
}

export interface StaffOption {
  auth_user_id: string
  full_name: string
  department_id: string | null
}

export interface SurveyAnswerInput {
  question_id: string
  subject_department_id?: string | null
  rating?: number | null
  choice?: string | null
  choices?: string[] | null
  text_answer?: string | null
}

export interface DepartmentOption {
  id: string
  name: string
}

export function useSurveys() {
  const supabase = useSupabase()

  async function loadDepartments(): Promise<DepartmentOption[]> {
    const { data } = await supabase.from('departments').select('id, name').order('name')
    return (data as DepartmentOption[]) ?? []
  }

  async function getMyDepartmentId(): Promise<string | null> {
    const { data: session } = await supabase.auth.getSession()
    const uid = session.session?.user?.id
    if (!uid) return null
    const { data } = await supabase
      .from('staff_members')
      .select('department_id')
      .eq('auth_user_id', uid)
      .maybeSingle()
    return (data as any)?.department_id ?? null
  }

  function normalizeSurvey(s: any): Survey {
    return {
      ...s,
      audience_department_ids: Array.isArray(s.audience_department_ids) ? s.audience_department_ids : [],
      audience_staff_ids: Array.isArray(s.audience_staff_ids) ? s.audience_staff_ids : []
    } as Survey
  }

  async function loadSurveys(): Promise<Survey[]> {
    const { data, error } = await supabase
      .from('surveys')
      .select('*')
      .order('created_at', { ascending: false })
    if (error) throw error
    return ((data as any[]) ?? []).map(normalizeSurvey)
  }

  async function loadSurvey(id: string): Promise<Survey | null> {
    const { data } = await supabase.from('surveys').select('*').eq('id', id).maybeSingle()
    return data ? normalizeSurvey(data) : null
  }

  async function loadQuestions(surveyId: string): Promise<SurveyQuestion[]> {
    const { data, error } = await supabase
      .from('survey_questions')
      .select('*')
      .eq('survey_id', surveyId)
      .order('sort_order')
    if (error) throw error
    return ((data as any[]) ?? []).map(q => ({
      ...q,
      options: Array.isArray(q.options) ? q.options : [],
      excluded_department_ids: Array.isArray(q.excluded_department_ids) ? q.excluded_department_ids : []
    })) as SurveyQuestion[]
  }

  async function loadStaff(): Promise<StaffOption[]> {
    const { data } = await supabase
      .from('staff_members')
      .select('auth_user_id, full_name, department_id')
      .eq('is_active', true)
      .not('auth_user_id', 'is', null)
      .order('full_name')
    return (data as StaffOption[]) ?? []
  }

  async function loadMyResponses(): Promise<Set<string>> {
    const { data: session } = await supabase.auth.getSession()
    const uid = session.session?.user?.id
    if (!uid) return new Set()
    const { data } = await supabase
      .from('survey_responses')
      .select('survey_id')
      .eq('respondent_id', uid)
    return new Set(((data as any[]) ?? []).map(r => r.survey_id))
  }

  async function submitResponse(surveyId: string, answers: SurveyAnswerInput[]): Promise<void> {
    const { data: response, error: respErr } = await supabase
      .from('survey_responses')
      .insert({ survey_id: surveyId })
      .select('id')
      .maybeSingle()
    if (respErr) throw respErr
    if (!response) throw new Error('Could not record your response')
    const rows = answers.map(a => ({
      response_id: (response as any).id,
      question_id: a.question_id,
      subject_department_id: a.subject_department_id ?? null,
      rating: a.rating ?? null,
      choice: a.choice ?? null,
      choices: a.choices ?? null,
      text_answer: a.text_answer ?? null
    }))
    if (rows.length) {
      const { error: ansErr } = await supabase.from('survey_answers').insert(rows)
      if (ansErr) throw ansErr
    }
  }

  async function createSurvey(payload: Partial<Survey>): Promise<Survey> {
    const { data, error } = await supabase.from('surveys').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as Survey
  }

  async function updateSurvey(id: string, payload: Partial<Survey>): Promise<void> {
    const { error } = await supabase.from('surveys').update(payload).eq('id', id)
    if (error) throw error
  }

  async function deleteSurvey(id: string): Promise<void> {
    const { error } = await supabase.from('surveys').delete().eq('id', id)
    if (error) throw error
  }

  async function addQuestion(payload: Partial<SurveyQuestion>): Promise<SurveyQuestion> {
    const { data, error } = await supabase.from('survey_questions').insert(payload).select('*').maybeSingle()
    if (error) throw error
    return data as SurveyQuestion
  }

  async function updateQuestion(id: string, payload: Partial<SurveyQuestion>): Promise<void> {
    const { error } = await supabase.from('survey_questions').update(payload).eq('id', id)
    if (error) throw error
  }

  async function deleteQuestion(id: string): Promise<void> {
    const { error } = await supabase.from('survey_questions').delete().eq('id', id)
    if (error) throw error
  }

  async function loadResults(surveyId: string) {
    const { data: responses, error: respErr } = await supabase
      .from('survey_responses')
      .select('id, respondent_id, submitted_at')
      .eq('survey_id', surveyId)
    if (respErr) throw respErr
    const responseIds = ((responses as any[]) ?? []).map(r => r.id)
    let answers: any[] = []
    if (responseIds.length) {
      const { data, error } = await supabase
        .from('survey_answers')
        .select('question_id, subject_department_id, rating, choice, choices, text_answer')
        .in('response_id', responseIds)
      if (error) throw error
      answers = data ?? []
    }
    return { responseCount: responseIds.length, answers }
  }

  return {
    loadDepartments,
    loadStaff,
    getMyDepartmentId,
    loadSurveys,
    loadSurvey,
    loadQuestions,
    loadMyResponses,
    submitResponse,
    createSurvey,
    updateSurvey,
    deleteSurvey,
    addQuestion,
    updateQuestion,
    deleteQuestion,
    loadResults
  }
}
