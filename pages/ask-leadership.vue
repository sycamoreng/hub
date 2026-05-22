<script setup lang="ts">
definePageMeta({ title: 'Ask Leadership Anything' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface Question {
  id: string
  author_id: string
  question: string
  is_anonymous: boolean
  upvotes: number
  status: 'pending' | 'answered' | 'archived'
  answer: string | null
  answered_by: string | null
  answered_at: string | null
  created_at: string
  author_name?: string
  answerer_name?: string
  voted?: boolean
}

const questions = ref<Question[]>([])
const myVotes = ref<Set<string>>(new Set())
const loading = ref(true)
const tab = ref<'pending' | 'answered'>('pending')
const showAskModal = ref(false)
const newQuestion = ref('')
const isAnonymous = ref(false)
const submitting = ref(false)

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('leadership_questions')
    .select('*')
    .order('upvotes', { ascending: false })

  if (data) {
    questions.value = data as Question[]
    await loadProfiles()
  }

  if (user.value) {
    const { data: votes } = await supabase
      .from('leadership_question_votes')
      .select('question_id')
      .eq('user_id', user.value.id)
    if (votes) myVotes.value = new Set(votes.map((v: any) => v.question_id))
  }
  loading.value = false
}

async function loadProfiles() {
  const authorIds = [...new Set(questions.value.map(q => q.author_id))]
  const answerIds = [...new Set(questions.value.filter(q => q.answered_by).map(q => q.answered_by!))]
  const allIds = [...new Set([...authorIds, ...answerIds])]
  if (allIds.length === 0) return

  const { data: staff } = await supabase
    .from('staff_members')
    .select('auth_user_id, full_name')
    .in('auth_user_id', allIds)

  const nameMap = new Map<string, string>()
  if (staff) staff.forEach((s: any) => nameMap.set(s.auth_user_id, s.full_name))

  questions.value = questions.value.map(q => ({
    ...q,
    author_name: q.is_anonymous ? 'Anonymous' : (nameMap.get(q.author_id) ?? 'Unknown'),
    answerer_name: q.answered_by ? (nameMap.get(q.answered_by) ?? 'Leadership') : undefined
  }))
}

const filtered = computed(() => questions.value.filter(q => q.status === tab.value))

async function askQuestion() {
  if (!newQuestion.value.trim() || !user.value) return
  submitting.value = true
  const { error } = await supabase.from('leadership_questions').insert({
    author_id: user.value.id,
    question: newQuestion.value.trim(),
    is_anonymous: isAnonymous.value
  })
  if (error) toastError('Failed to submit question')
  else {
    success('Question submitted!')
    newQuestion.value = ''
    isAnonymous.value = false
    showAskModal.value = false
    await load()
  }
  submitting.value = false
}

async function toggleVote(questionId: string) {
  if (!user.value) return
  if (myVotes.value.has(questionId)) {
    await supabase.from('leadership_question_votes')
      .delete()
      .eq('question_id', questionId)
      .eq('user_id', user.value.id)
    myVotes.value.delete(questionId)
    const q = questions.value.find(q => q.id === questionId)
    if (q) q.upvotes--
  } else {
    await supabase.from('leadership_question_votes').insert({
      question_id: questionId,
      user_id: user.value.id
    })
    myVotes.value.add(questionId)
    const q = questions.value.find(q => q.id === questionId)
    if (q) q.upvotes++
  }
}

async function deleteQuestion(id: string) {
  const { error } = await supabase.from('leadership_questions').delete().eq('id', id)
  if (error) toastError('Failed to delete')
  else { success('Question removed'); await load() }
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-3xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Ask Leadership Anything</h1>
        <p class="section-subtitle">Submit questions anonymously and upvote the ones you want answered</p>
      </div>
      <button @click="showAskModal = true" class="btn-primary">Ask a Question</button>
    </div>

    <div class="flex gap-2 mb-6">
      <button
        v-for="t in (['pending', 'answered'] as const)"
        :key="t"
        @click="tab = t"
        class="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
        :class="tab === t ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >{{ t === 'pending' ? 'Pending' : 'Answered' }}</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">
      {{ tab === 'pending' ? 'No pending questions. Be the first to ask!' : 'No answered questions yet.' }}
    </div>
    <div v-else class="space-y-3">
      <div v-for="q in filtered" :key="q.id" class="card p-4">
        <div class="flex gap-3">
          <div class="flex flex-col items-center gap-1">
            <button
              @click="toggleVote(q.id)"
              class="w-10 h-10 rounded-lg flex items-center justify-center transition-colors"
              :class="myVotes.has(q.id) ? 'bg-sycamore-100 text-sycamore-700' : 'bg-slate-100 text-slate-500 hover:bg-slate-200'"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5">
                <path fill-rule="evenodd" d="M10 15a.75.75 0 0 1-.75-.75V7.612L7.29 9.77a.75.75 0 0 1-1.08-1.04l3.25-3.5a.75.75 0 0 1 1.08 0l3.25 3.5a.75.75 0 1 1-1.08 1.04l-1.96-2.158v6.638A.75.75 0 0 1 10 15Z" clip-rule="evenodd" />
              </svg>
            </button>
            <span class="text-sm font-bold" :class="myVotes.has(q.id) ? 'text-sycamore-700' : 'text-slate-600'">{{ q.upvotes }}</span>
          </div>
          <div class="flex-1">
            <p class="text-slate-900 font-medium">{{ q.question }}</p>
            <div class="flex items-center gap-2 mt-2 text-xs text-slate-500">
              <span>{{ q.author_name }}</span>
              <span>{{ new Date(q.created_at).toLocaleDateString() }}</span>
              <button
                v-if="q.author_id === user?.id && q.status === 'pending'"
                @click="deleteQuestion(q.id)"
                class="text-red-500 hover:text-red-700"
              >Delete</button>
            </div>
            <div v-if="q.answer" class="mt-3 p-3 bg-sycamore-50 rounded-lg border border-sycamore-100">
              <div class="text-xs font-medium text-sycamore-700 mb-1">
                {{ q.answerer_name ?? 'Leadership' }} answered on {{ q.answered_at ? new Date(q.answered_at).toLocaleDateString() : '' }}
              </div>
              <p class="text-sm text-slate-800">{{ q.answer }}</p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Ask Modal -->
    <div v-if="showAskModal" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showAskModal = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-lg p-6">
        <h2 class="text-lg font-bold text-slate-900 mb-4">Ask a Question</h2>
        <textarea
          v-model="newQuestion"
          class="input min-h-[120px]"
          placeholder="What would you like to ask leadership?"
          maxlength="1000"
        />
        <label class="flex items-center gap-2 mt-3 text-sm text-slate-600">
          <input type="checkbox" v-model="isAnonymous" class="rounded border-slate-300">
          Submit anonymously
        </label>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showAskModal = false" class="btn-secondary">Cancel</button>
          <button @click="askQuestion" :disabled="!newQuestion.trim() || submitting" class="btn-primary">
            {{ submitting ? 'Submitting...' : 'Submit' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
