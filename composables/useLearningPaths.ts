import { useSupabase } from '~/utils/supabase'

export interface LearningPath {
  id: string
  name: string
  description: string
  is_sequential: boolean
  badge_id: string | null
  sort_order: number
  is_active: boolean
}

export interface QuizQuestion {
  id: string
  step_id: string
  question: string
  options: string[]
  correct_index: number
  sort_order: number
}

export interface QuizAttempt {
  id: string
  step_id: string
  user_id: string
  answers: number[]
  score: number
  total: number
  passed: boolean
  created_at: string
}

export function useLearningPaths() {
  const supabase = useSupabase()

  async function fetchPaths(): Promise<LearningPath[]> {
    const { data } = await supabase
      .from('learning_paths')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
    return (data ?? []) as LearningPath[]
  }

  async function fetchQuizQuestions(stepId: string): Promise<QuizQuestion[]> {
    const { data } = await supabase
      .from('step_quiz_questions')
      .select('*')
      .eq('step_id', stepId)
      .order('sort_order')
    return (data ?? []).map((q: any) => ({
      ...q,
      options: Array.isArray(q.options) ? q.options : JSON.parse(q.options || '[]')
    }))
  }

  async function fetchMyAttempts(stepIds: string[]): Promise<QuizAttempt[]> {
    const { user } = useAuth()
    if (!user.value || stepIds.length === 0) return []
    const { data } = await supabase
      .from('step_quiz_attempts')
      .select('*')
      .eq('user_id', user.value.id)
      .in('step_id', stepIds)
      .order('created_at', { ascending: false })
    return (data ?? []) as QuizAttempt[]
  }

  async function submitQuiz(stepId: string, answers: number[]): Promise<QuizAttempt> {
    const { user } = useAuth()
    if (!user.value) throw new Error('Not authenticated')

    const questions = await fetchQuizQuestions(stepId)
    if (questions.length === 0) throw new Error('No quiz questions found')

    let score = 0
    for (let i = 0; i < questions.length; i++) {
      if (answers[i] === questions[i].correct_index) score++
    }

    const { data: step } = await supabase
      .from('onboarding_steps')
      .select('quiz_pass_threshold')
      .eq('id', stepId)
      .maybeSingle()

    const threshold = (step as any)?.quiz_pass_threshold ?? 80
    const percentage = Math.round((score / questions.length) * 100)
    const passed = percentage >= threshold

    const { data, error } = await supabase
      .from('step_quiz_attempts')
      .insert({
        step_id: stepId,
        user_id: user.value.id,
        answers,
        score,
        total: questions.length,
        passed
      })
      .select('*')
      .maybeSingle()

    if (error) throw error
    return data as QuizAttempt
  }

  function isStepUnlocked(
    stepId: string,
    path: LearningPath | null,
    stepsInPath: { id: string; display_order: number }[],
    completedIds: Set<string>,
    passedQuizStepIds: Set<string>,
    quizStepIds: Set<string>
  ): boolean {
    if (!path || !path.is_sequential) return true

    const sorted = [...stepsInPath].sort((a, b) => a.display_order - b.display_order)
    const idx = sorted.findIndex(s => s.id === stepId)
    if (idx <= 0) return true

    const prevStep = sorted[idx - 1]
    const prevCompleted = completedIds.has(prevStep.id)
    const prevHasQuiz = quizStepIds.has(prevStep.id)
    const prevPassed = passedQuizStepIds.has(prevStep.id)

    if (!prevCompleted) return false
    if (prevHasQuiz && !prevPassed) return false
    return true
  }

  return {
    fetchPaths,
    fetchQuizQuestions,
    fetchMyAttempts,
    submitQuiz,
    isStepUnlocked
  }
}
