<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'Leadership Q&A' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface Question {
  id: string
  author_id: string
  question: string
  is_anonymous: boolean
  upvotes: number
  status: string
  answer: string | null
  answered_by: string | null
  answered_at: string | null
  created_at: string
}

const questions = ref<Question[]>([])
const loading = ref(true)
const tab = ref<'pending' | 'answered' | 'archived'>('pending')
const answeringId = ref<string | null>(null)
const answerText = ref('')

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('leadership_questions')
    .select('*')
    .order('upvotes', { ascending: false })
  questions.value = (data ?? []) as Question[]
  loading.value = false
}

const filtered = computed(() => questions.value.filter(q => q.status === tab.value))

async function answer(id: string) {
  if (!answerText.value.trim() || !user.value) return
  const { error } = await supabase
    .from('leadership_questions')
    .update({
      answer: answerText.value.trim(),
      answered_by: user.value.id,
      answered_at: new Date().toISOString(),
      status: 'answered'
    })
    .eq('id', id)
  if (error) toastError('Failed to answer')
  else {
    success('Answer published!')
    answeringId.value = null
    answerText.value = ''
    await load()
  }
}

async function archive(id: string) {
  const { error } = await supabase.from('leadership_questions').update({ status: 'archived' }).eq('id', id)
  if (error) toastError('Failed to archive'); else { success('Archived'); await load() }
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-8">
    <div class="mb-6">
      <h1 class="section-title">Leadership Q&A</h1>
      <p class="section-subtitle">Answer staff questions and manage the Q&A board</p>
    </div>

    <div class="flex gap-2 mb-6">
      <button
        v-for="t in (['pending', 'answered', 'archived'] as const)"
        :key="t"
        @click="tab = t"
        class="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
        :class="tab === t ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >{{ t.charAt(0).toUpperCase() + t.slice(1) }} ({{ questions.filter(q => q.status === t).length }})</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">No {{ tab }} questions.</div>
    <div v-else class="space-y-3">
      <div v-for="q in filtered" :key="q.id" class="card p-4">
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1">
            <div class="flex items-center gap-2 mb-1">
              <span class="badge badge-blue">{{ q.upvotes }} votes</span>
              <span v-if="q.is_anonymous" class="text-xs text-slate-400">Anonymous</span>
            </div>
            <p class="text-slate-900 font-medium">{{ q.question }}</p>
            <div class="text-xs text-slate-500 mt-1">Asked {{ new Date(q.created_at).toLocaleDateString() }}</div>
            <div v-if="q.answer" class="mt-3 p-3 bg-sycamore-50 rounded-lg">
              <p class="text-sm text-slate-800">{{ q.answer }}</p>
            </div>
            <div v-if="answeringId === q.id" class="mt-3">
              <textarea v-model="answerText" class="input min-h-[100px]" placeholder="Write your answer..." />
              <div class="flex gap-2 mt-2">
                <button @click="answer(q.id)" :disabled="!answerText.trim()" class="btn-primary text-xs">Publish Answer</button>
                <button @click="answeringId = null" class="btn-secondary text-xs">Cancel</button>
              </div>
            </div>
          </div>
          <div v-if="tab === 'pending'" class="flex gap-2">
            <button @click="answeringId = q.id; answerText = ''" class="btn-primary text-xs">Answer</button>
            <button @click="archive(q.id)" class="btn-secondary text-xs">Archive</button>
          </div>
          <button v-else-if="tab === 'answered'" @click="archive(q.id)" class="btn-secondary text-xs">Archive</button>
        </div>
      </div>
    </div>
  </div>
</template>
