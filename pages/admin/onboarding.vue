<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { items, loading, load, create, update, remove } = useCrud('onboarding_steps')
const toast = useToast()
const { log: auditLog } = useAuditLog()
const supabase = useSupabase()

const editorOpen = ref(false)
const editing = ref<any | null>(null)
const saving = ref(false)
const resourcesOpen = ref(false)
const resourcesStep = ref<any | null>(null)
const assignOpen = ref(false)
const assignStep = ref<any | null>(null)

// Paths
const pathsTab = ref<'lessons' | 'paths'>('lessons')
const learningPaths = ref<any[]>([])
const pathEditorOpen = ref(false)
const editingPath = ref<any | null>(null)
const savingPath = ref(false)

// Quiz
const quizOpen = ref(false)
const quizStepId = ref<string | null>(null)
const quizStepTitle = ref('')
const quizQuestions = ref<any[]>([])
const loadingQuiz = ref(false)
const savingQuiz = ref(false)
const newQuestion = ref({ question: '', options: ['', '', '', ''], correct_index: 0 })

async function loadPaths() {
  const { data } = await supabase
    .from('learning_paths')
    .select('*')
    .order('sort_order')
  learningPaths.value = data ?? []
}

const pathOptions = computed(() => [
  { value: '', label: 'None (standalone)' },
  ...learningPaths.value.map(p => ({ value: p.id, label: p.name }))
])

const fields = computed(() => [
  { key: 'title', label: 'Title', required: true },
  { key: 'description', label: 'Short description', type: 'textarea', hint: 'Shown under the title in the learning path.' },
  {
    key: 'content_type', label: 'Content type', type: 'select', required: true,
    options: [
      { value: 'task', label: 'Task / checklist item' },
      { value: 'video', label: 'Video' },
      { value: 'article', label: 'Article (long-form text)' },
      { value: 'module', label: 'Module (multiple resources)' }
    ],
    hint: 'Modules group several videos, articles or links into one lesson.'
  },
  {
    key: 'path_id', label: 'Learning Path', type: 'select',
    options: pathOptions.value,
    hint: 'Assign to a path for grouped progression. Sequential paths require steps in order.'
  },
  {
    key: 'category', label: 'Category', type: 'select', required: true,
    options: [
      { value: 'general', label: 'General' },
      { value: 'paperwork', label: 'Paperwork' },
      { value: 'systems', label: 'Systems & access' },
      { value: 'culture', label: 'Culture' },
      { value: 'training', label: 'Training' },
      { value: 'product', label: 'Product knowledge' },
      { value: 'compliance', label: 'Compliance' }
    ]
  },
  { key: 'video_url', label: 'Video URL', placeholder: 'https://youtu.be/... or vimeo.com/...', hint: 'For content type "video". YouTube, Vimeo, and Loom auto-embed.' },
  { key: 'body', label: 'Long-form body', type: 'textarea', hint: 'For content type "article", or as an intro for a module.' },
  { key: 'cover_image_url', label: 'Cover image URL', placeholder: 'https://...' },
  { key: 'resource_url', label: 'Primary resource URL', placeholder: 'https://...', hint: 'Optional fallback link shown for any content type.' },
  { key: 'estimated_minutes', label: 'Estimated minutes', type: 'number' },
  { key: 'quiz_pass_threshold', label: 'Quiz pass threshold (%)', type: 'number', hint: 'Percentage required to pass the quiz (if questions exist). Default: 80.' },
  { key: 'display_order', label: 'Display order', type: 'number', hint: 'In sequential paths, this determines the step order.' },
  { key: 'is_required', label: 'Required step', type: 'checkbox' },
  { key: 'is_active', label: 'Active', type: 'checkbox' }
])

const columns = [
  { key: 'title', label: 'Title' },
  { key: 'content_type', label: 'Type', render: (r: any) => (r.content_type || 'task') },
  { key: 'path_name', label: 'Path', render: (r: any) => learningPaths.value.find(p => p.id === r.path_id)?.name || '-' },
  { key: 'category', label: 'Category' },
  { key: 'is_required', label: 'Required', render: (r: any) => r.is_required ? 'Yes' : 'No' },
  { key: 'is_active', label: 'Active', render: (r: any) => r.is_active ? 'Yes' : 'No' }
]

await Promise.all([
  load([{ column: 'display_order', ascending: true }, { column: 'title', ascending: true }]),
  loadPaths()
])

function openNew() {
  editing.value = {
    is_required: true,
    is_active: true,
    category: 'general',
    content_type: 'task',
    display_order: 0,
    estimated_minutes: 0,
    quiz_pass_threshold: 80,
    path_id: ''
  }
  editorOpen.value = true
}
function openEdit(row: any) { editing.value = { ...row, path_id: row.path_id || '' }; editorOpen.value = true }
function manageResources(row: any) { resourcesStep.value = row; resourcesOpen.value = true }
function manageAssignments(row: any) { assignStep.value = row; assignOpen.value = true }

async function save(payload: Record<string, any>) {
  saving.value = true
  try {
    const data: Record<string, any> = {
      title: payload.title,
      description: payload.description ?? '',
      category: payload.category || 'general',
      content_type: payload.content_type || 'task',
      body: payload.body ?? '',
      video_url: payload.video_url ?? '',
      cover_image_url: payload.cover_image_url ?? '',
      resource_url: payload.resource_url ?? '',
      estimated_minutes: Number(payload.estimated_minutes) || 0,
      quiz_pass_threshold: Number(payload.quiz_pass_threshold) || 80,
      display_order: Number(payload.display_order) || 0,
      is_required: !!payload.is_required,
      is_active: payload.is_active === undefined ? true : !!payload.is_active,
      path_id: payload.path_id || null
    }
    if (editing.value?.id) await update(editing.value.id, data); else await create(data)
    editorOpen.value = false
    auditLog({ action: editing.value?.id ? 'update' : 'create', target_type: 'onboarding_step', target_label: data.title })
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { saving.value = false }
}

async function del(row: any) {
  const ok = await toast.confirm({ title: 'Delete', message: `Delete "${row.title}"?` + ' This cannot be undone.', variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  try { await remove(row.id)
    auditLog({ action: 'delete', target_type: 'onboarding_step', target_id: row.id, target_label: row.title })
    toast.success('Deleted') } catch (e: any) { toast.error(e.message ?? 'Failed to delete') }
}

// Path management
function openNewPath() {
  editingPath.value = { name: '', description: '', is_sequential: false, sort_order: 0, badge_id: null }
  pathEditorOpen.value = true
}
function openEditPath(path: any) { editingPath.value = { ...path }; pathEditorOpen.value = true }

async function savePath() {
  if (!editingPath.value?.name?.trim()) { toast.error('Name is required'); return }
  savingPath.value = true
  try {
    const payload = {
      name: editingPath.value.name.trim(),
      description: editingPath.value.description || '',
      is_sequential: !!editingPath.value.is_sequential,
      sort_order: Number(editingPath.value.sort_order) || 0,
      badge_id: editingPath.value.badge_id || null
    }
    if (editingPath.value.id) {
      await supabase.from('learning_paths').update(payload).eq('id', editingPath.value.id)
    } else {
      await supabase.from('learning_paths').insert(payload)
    }
    pathEditorOpen.value = false
    await loadPaths()
    auditLog({ action: editingPath.value.id ? 'update' : 'create', target_type: 'learning_path', target_label: payload.name })
    toast.success('Path saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
  finally { savingPath.value = false }
}

async function deletePath(path: any) {
  const ok = await toast.confirm({ title: 'Delete path', message: `Delete "${path.name}"? Steps will become standalone.`, variant: 'danger', confirmLabel: 'Delete' })
  if (!ok) return
  await supabase.from('learning_paths').delete().eq('id', path.id)
  await loadPaths()
  toast.success('Path deleted')
}

// Quiz management
async function openQuizEditor(row: any) {
  quizStepId.value = row.id
  quizStepTitle.value = row.title
  quizOpen.value = true
  loadingQuiz.value = true
  resetNewQuestion()
  const { data } = await supabase
    .from('step_quiz_questions')
    .select('*')
    .eq('step_id', row.id)
    .order('sort_order')
  quizQuestions.value = (data ?? []).map((q: any) => ({
    ...q,
    options: Array.isArray(q.options) ? q.options : JSON.parse(q.options || '[]')
  }))
  loadingQuiz.value = false
}

function resetNewQuestion() {
  newQuestion.value = { question: '', options: ['', '', '', ''], correct_index: 0 }
}

async function addQuestion() {
  if (!newQuestion.value.question.trim()) { toast.error('Enter a question'); return }
  const validOptions = newQuestion.value.options.filter(o => o.trim())
  if (validOptions.length < 2) { toast.error('At least 2 options required'); return }
  savingQuiz.value = true
  try {
    const { error } = await supabase.from('step_quiz_questions').insert({
      step_id: quizStepId.value,
      question: newQuestion.value.question.trim(),
      options: validOptions,
      correct_index: Math.min(newQuestion.value.correct_index, validOptions.length - 1),
      sort_order: quizQuestions.value.length
    })
    if (error) throw error
    await openQuizEditor({ id: quizStepId.value, title: quizStepTitle.value })
    resetNewQuestion()
    toast.success('Question added')
  } catch (e: any) { toast.error(e.message ?? 'Failed to add') }
  finally { savingQuiz.value = false }
}

async function removeQuestion(qId: string) {
  await supabase.from('step_quiz_questions').delete().eq('id', qId)
  quizQuestions.value = quizQuestions.value.filter(q => q.id !== qId)
  toast.success('Removed')
}

function addOption() {
  if (newQuestion.value.options.length < 6) {
    newQuestion.value.options.push('')
  }
}

function removeOption(idx: number) {
  if (newQuestion.value.options.length > 2) {
    newQuestion.value.options.splice(idx, 1)
    if (newQuestion.value.correct_index >= newQuestion.value.options.length) {
      newQuestion.value.correct_index = 0
    }
  }
}
</script>

<template>
  <div class="max-w-5xl">
    <!-- Tab Switcher -->
    <div class="flex items-center gap-1 mb-6 bg-slate-100 rounded-lg p-1 w-fit">
      <button
        @click="pathsTab = 'lessons'"
        class="px-4 py-2 rounded-md text-sm font-medium transition-colors"
        :class="pathsTab === 'lessons' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-600 hover:text-slate-900'"
      >Lessons</button>
      <button
        @click="pathsTab = 'paths'"
        class="px-4 py-2 rounded-md text-sm font-medium transition-colors"
        :class="pathsTab === 'paths' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-600 hover:text-slate-900'"
      >Learning Paths</button>
    </div>

    <!-- Lessons Tab -->
    <div v-if="pathsTab === 'lessons'">
      <AdminList
        title="Learning"
        description="Build lessons, then assign them to paths and add quizzes for gamified progression."
        :columns="columns"
        :rows="items"
        :loading="loading"
        new-label="New lesson"
        @new="openNew"
        @edit="openEdit"
        @delete="del"
      >
        <template #row-actions="{ row }">
          <button type="button" class="text-xs font-medium text-sycamore-700 hover:underline" @click="openQuizEditor(row)">Quiz</button>
          <button type="button" class="text-xs font-medium text-sycamore-700 hover:underline ml-3" @click="manageResources(row)">Resources</button>
          <button type="button" class="text-xs font-medium text-sycamore-700 hover:underline ml-3" @click="manageAssignments(row)">Assign</button>
        </template>
      </AdminList>
    </div>

    <!-- Paths Tab -->
    <div v-else>
      <div class="flex items-center justify-between mb-6">
        <div>
          <h2 class="text-lg font-bold text-slate-900">Learning Paths</h2>
          <p class="text-sm text-slate-500">Group lessons into sequential or non-sequential paths. Sequential paths require steps in order.</p>
        </div>
        <button @click="openNewPath" class="btn-primary text-sm">New path</button>
      </div>

      <div v-if="learningPaths.length === 0" class="card p-8 text-center text-slate-500">
        No learning paths yet. Create one to group lessons together.
      </div>
      <div v-else class="space-y-3">
        <div v-for="p in learningPaths" :key="p.id" class="card p-4 flex items-center gap-4">
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2">
              <h3 class="font-semibold text-slate-900">{{ p.name }}</h3>
              <span
                class="text-[10px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded"
                :class="p.is_sequential ? 'bg-sycamore-100 text-sycamore-700' : 'bg-slate-100 text-slate-600'"
              >{{ p.is_sequential ? 'Sequential' : 'Flexible' }}</span>
            </div>
            <p v-if="p.description" class="text-xs text-slate-500 mt-0.5">{{ p.description }}</p>
            <p class="text-xs text-slate-400 mt-1">
              {{ items.filter((s: any) => s.path_id === p.id).length }} lesson(s) assigned
            </p>
          </div>
          <div class="flex items-center gap-2">
            <button @click="openEditPath(p)" class="text-xs font-medium text-sycamore-700 hover:underline">Edit</button>
            <button @click="deletePath(p)" class="text-xs font-medium text-red-600 hover:underline">Delete</button>
          </div>
        </div>
      </div>
    </div>

    <!-- Lesson Editor -->
    <AdminEditor :open="editorOpen" :title="editing?.id ? 'Edit lesson' : 'New lesson'" :fields="(fields as any)" :initial="editing" :saving="saving" @close="editorOpen = false" @save="save" />
    <OnboardingResourcesEditor
      :open="resourcesOpen"
      :step-id="resourcesStep?.id ?? null"
      :step-title="resourcesStep?.title ?? ''"
      @close="resourcesOpen = false"
    />
    <LearningAssignmentsEditor
      :open="assignOpen"
      :step-id="assignStep?.id ?? null"
      :step-title="assignStep?.title ?? ''"
      @close="assignOpen = false"
    />

    <!-- Path Editor Modal -->
    <Teleport to="body">
      <div v-if="pathEditorOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/50" @click="pathEditorOpen = false" />
        <div class="relative bg-white rounded-2xl shadow-xl max-w-md w-full p-6">
          <h2 class="text-lg font-bold text-slate-900 mb-4">{{ editingPath?.id ? 'Edit' : 'New' }} Learning Path</h2>
          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">Name</label>
              <input v-model="editingPath.name" class="input" placeholder="e.g. Onboarding Journey" />
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">Description</label>
              <textarea v-model="editingPath.description" class="input" rows="2" placeholder="Brief description..." />
            </div>
            <div class="flex items-center gap-3">
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" v-model="editingPath.is_sequential" class="rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500" />
                <span class="text-sm text-slate-700">Sequential (steps must be completed in order)</span>
              </label>
            </div>
            <div>
              <label class="block text-sm font-medium text-slate-700 mb-1">Sort order</label>
              <input v-model.number="editingPath.sort_order" type="number" class="input w-24" />
            </div>
          </div>
          <div class="flex items-center justify-end gap-3 mt-6">
            <button @click="pathEditorOpen = false" class="text-sm text-slate-500 hover:text-slate-700 font-medium px-4 py-2">Cancel</button>
            <button @click="savePath" :disabled="savingPath" class="btn-primary text-sm">
              {{ savingPath ? '...' : 'Save' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Quiz Editor Modal -->
    <Teleport to="body">
      <div v-if="quizOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-slate-900/50" @click="quizOpen = false" />
        <div class="relative bg-white rounded-2xl shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
          <div class="sticky top-0 bg-white border-b border-slate-200 p-5 rounded-t-2xl z-10">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="text-lg font-bold text-slate-900">Quiz: {{ quizStepTitle }}</h2>
                <p class="text-sm text-slate-500">{{ quizQuestions.length }} question(s)</p>
              </div>
              <button @click="quizOpen = false" class="w-8 h-8 rounded-lg hover:bg-slate-100 flex items-center justify-center text-slate-400">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>
          </div>

          <div class="p-5 space-y-4">
            <div v-if="loadingQuiz" class="text-center py-6 text-slate-400">Loading...</div>
            <template v-else>
              <!-- Existing questions -->
              <div v-for="(q, qi) in quizQuestions" :key="q.id" class="p-4 rounded-lg border border-slate-200 bg-slate-50/50">
                <div class="flex items-start justify-between gap-2">
                  <p class="font-medium text-slate-900 text-sm">{{ qi + 1 }}. {{ q.question }}</p>
                  <button @click="removeQuestion(q.id)" class="text-xs text-red-500 hover:text-red-600 shrink-0">Remove</button>
                </div>
                <ul class="mt-2 space-y-1">
                  <li v-for="(opt, oi) in q.options" :key="oi" class="text-xs flex items-center gap-2"
                    :class="oi === q.correct_index ? 'text-leaf-700 font-medium' : 'text-slate-500'"
                  >
                    <span :class="oi === q.correct_index ? 'text-leaf-600' : 'text-slate-300'">{{ oi === q.correct_index ? '✓' : '○' }}</span>
                    {{ opt }}
                  </li>
                </ul>
              </div>

              <!-- Add new question form -->
              <div class="p-4 rounded-lg border-2 border-dashed border-slate-200 space-y-3">
                <p class="text-sm font-semibold text-slate-700">Add question</p>
                <input v-model="newQuestion.question" class="input text-sm" placeholder="Enter your question..." />
                <div class="space-y-2">
                  <div v-for="(opt, oi) in newQuestion.options" :key="oi" class="flex items-center gap-2">
                    <input
                      type="radio"
                      :value="oi"
                      v-model="newQuestion.correct_index"
                      class="w-4 h-4 text-sycamore-600 focus:ring-sycamore-500"
                      title="Mark as correct"
                    />
                    <input v-model="newQuestion.options[oi]" class="input text-sm flex-1" :placeholder="`Option ${oi + 1}`" />
                    <button v-if="newQuestion.options.length > 2" @click="removeOption(oi)" class="text-slate-400 hover:text-red-500">
                      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
                    </button>
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <button v-if="newQuestion.options.length < 6" @click="addOption" class="text-xs text-sycamore-700 hover:underline font-medium">+ Add option</button>
                  <div class="flex-1" />
                  <button @click="addQuestion" :disabled="savingQuiz" class="btn-primary text-xs">
                    {{ savingQuiz ? '...' : 'Add question' }}
                  </button>
                </div>
                <p class="text-[10px] text-slate-400">Select the radio button next to the correct answer.</p>
              </div>
            </template>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
