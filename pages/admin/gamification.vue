<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

definePageMeta({ middleware: ['auth'], layout: 'admin' })

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()
const { canManageSection } = useAuth()

const tab = ref<'sparks' | 'weights' | 'badges' | 'values' | 'wordle' | 'typing'>('sparks')

const typingCategories = ref<any[]>([])
const typingPrompts = ref<any[]>([])
const typingNew = ref<{ category_id: string; text: string; length_tier: 'short' | 'medium' | 'long' }>({ category_id: '', text: '', length_tier: 'medium' })
const typingNewCategory = ref<{ slug: string; name: string; description: string }>({ slug: '', name: '', description: '' })
const typingFilterCategory = ref<string>('')

async function loadTyping() {
  const [{ data: cats }, { data: ps }] = await Promise.all([
    supabase.from('typing_categories').select('*').order('sort_order'),
    supabase.from('typing_prompts').select('*, category:typing_categories(id, name)').order('created_at', { ascending: false })
  ])
  typingCategories.value = cats ?? []
  typingPrompts.value = ps ?? []
  if (!typingNew.value.category_id && typingCategories.value.length) typingNew.value.category_id = typingCategories.value[0].id
}

async function addTypingCategory() {
  const c = typingNewCategory.value
  if (!c.slug.trim() || !c.name.trim()) { toast.error('Slug and name required'); return }
  const { error } = await supabase.from('typing_categories').insert({ slug: c.slug.trim().toLowerCase(), name: c.name.trim(), description: c.description, sort_order: typingCategories.value.length })
  if (error) { toast.error(error.message); return }
  auditLog({ action: 'create', target_type: 'typing_category', target_label: c.name.trim() })
  typingNewCategory.value = { slug: '', name: '', description: '' }
  await loadTyping()
  toast.success('Category added')
}

async function toggleTypingCategory(cat: any) {
  await supabase.from('typing_categories').update({ is_active: !cat.is_active }).eq('id', cat.id)
  auditLog({ action: cat.is_active ? 'deactivate' : 'activate', target_type: 'typing_category', target_id: cat.id, target_label: cat.name })
  await loadTyping()
}

async function deleteTypingCategory(cat: any) {
  if (!confirm(`Delete category "${cat.name}" and all its prompts?`)) return
  await supabase.from('typing_categories').delete().eq('id', cat.id)
  auditLog({ action: 'delete', target_type: 'typing_category', target_id: cat.id, target_label: cat.name })
  await loadTyping()
}

async function addTypingPrompt() {
  const p = typingNew.value
  if (!p.text.trim() || !p.category_id) { toast.error('Pick category and prompt text'); return }
  const { error } = await supabase.from('typing_prompts').insert({ category_id: p.category_id, text: p.text.trim(), length_tier: p.length_tier })
  if (error) { toast.error(error.message); return }
  auditLog({ action: 'create', target_type: 'typing_prompt', target_label: p.text.trim().slice(0, 50) })
  typingNew.value.text = ''
  await loadTyping()
  toast.success('Prompt added')
}

async function toggleTypingPrompt(p: any) {
  await supabase.from('typing_prompts').update({ is_active: !p.is_active }).eq('id', p.id)
  auditLog({ action: p.is_active ? 'deactivate' : 'activate', target_type: 'typing_prompt', target_id: p.id, target_label: (p.text ?? '').slice(0, 50) })
  await loadTyping()
}

async function deleteTypingPrompt(p: any) {
  if (!confirm('Delete this prompt?')) return
  await supabase.from('typing_prompts').delete().eq('id', p.id)
  auditLog({ action: 'delete', target_type: 'typing_prompt', target_id: p.id, target_label: (p.text ?? '').slice(0, 50) })
  await loadTyping()
}

const filteredTypingPrompts = computed(() => {
  if (!typingFilterCategory.value) return typingPrompts.value
  return typingPrompts.value.filter(p => p.category_id === typingFilterCategory.value)
})

const sparks = ref<any[]>([])
const weights = ref<any[]>([])
const badges = ref<any[]>([])
const values = ref<any[]>([])
const words = ref<any[]>([])
const wordleSettings = ref<any>({ letter_count: 5, max_guesses: 6 })
const newWord = ref('')
const loading = ref(true)

async function loadAll() {
  loading.value = true
  try {
    const [s, w, b, v, ws, wws] = await Promise.all([
      supabase.from('daily_sparks').select('*').order('active_on', { ascending: false }),
      supabase.from('point_weights').select('*').order('event_kind'),
      supabase.from('badges').select('*').order('sort_order'),
      supabase.from('kudos_values').select('*').order('sort_order'),
      supabase.from('wordle_settings').select('*').eq('id', 1).maybeSingle(),
      supabase.from('wordle_words').select('*').order('length').order('word')
    ])
    sparks.value = s.data ?? []
    weights.value = w.data ?? []
    badges.value = b.data ?? []
    values.value = v.data ?? []
    if (ws.data) wordleSettings.value = ws.data
    words.value = wws.data ?? []
  } finally {
    loading.value = false
  }
}
onMounted(async () => { await loadAll(); await loadTyping() })

// Spark editor
const sparkForm = ref({
  id: null as string | null,
  active_on: new Date().toISOString().slice(0, 10),
  kind: 'trivia',
  question: '',
  options: ['', '', '', ''],
  correct_index: 0,
  points_award: 5,
  is_active: true
})

function editSpark(row: any) {
  sparkForm.value = {
    id: row.id,
    active_on: row.active_on,
    kind: row.kind,
    question: row.question,
    options: Array.isArray(row.options) ? [...row.options, '', '', '', ''].slice(0, 4) : ['', '', '', ''],
    correct_index: row.correct_index ?? 0,
    points_award: row.points_award,
    is_active: row.is_active
  }
}
function resetSpark() {
  sparkForm.value = {
    id: null,
    active_on: new Date().toISOString().slice(0, 10),
    kind: 'trivia',
    question: '',
    options: ['', '', '', ''],
    correct_index: 0,
    points_award: 5,
    is_active: true
  }
}
async function saveSpark() {
  const f = sparkForm.value
  if (!f.question.trim()) { toast.error('Question required'); return }
  const opts = f.options.map(o => o.trim()).filter(Boolean)
  if (opts.length < 2) { toast.error('At least 2 options'); return }
  const payload: any = {
    active_on: f.active_on,
    kind: f.kind,
    question: f.question.trim(),
    options: opts,
    correct_index: Math.min(f.correct_index, opts.length - 1),
    points_award: Number(f.points_award) || 5,
    is_active: f.is_active
  }
  try {
    if (f.id) await supabase.from('daily_sparks').update(payload).eq('id', f.id)
    else await supabase.from('daily_sparks').insert(payload)
    auditLog({ action: f.id ? 'update' : 'create', target_type: 'daily_spark', target_label: payload.question.slice(0, 50) })
    toast.success('Saved')
    resetSpark()
    await loadAll()
  } catch (e: any) { toast.error(e.message ?? 'Failed to save') }
}
async function deleteSpark(row: any) {
  const ok = await toast.confirm({ title: 'Delete spark', message: 'Remove this Daily Spark?', confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  await supabase.from('daily_sparks').delete().eq('id', row.id)
  auditLog({ action: 'delete', target_type: 'daily_spark', target_id: row.id, target_label: (row.question ?? '').slice(0, 50) })
  toast.success('Deleted')
  await loadAll()
}

async function saveWeight(row: any) {
  try {
    await supabase.from('point_weights').update({
      label: row.label,
      points: Number(row.points) || 0,
      is_active: row.is_active
    }).eq('id', row.id)
    auditLog({ action: 'update', target_type: 'point_weight', target_id: row.id, target_label: row.event_kind })
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function saveBadge(row: any) {
  try {
    await supabase.from('badges').update({
      name: row.name,
      description: row.description,
      emoji: row.emoji,
      color: row.color,
      threshold: Number(row.threshold) || 1,
      metric: row.metric,
      is_active: row.is_active
    }).eq('id', row.id)
    auditLog({ action: 'update', target_type: 'badge', target_id: row.id, target_label: row.name })
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function saveWordleSettings() {
  const lc = Math.max(3, Math.min(9, Number(wordleSettings.value.letter_count) || 5))
  const mg = Math.max(3, Math.min(10, Number(wordleSettings.value.max_guesses) || 6))
  try {
    await supabase.from('wordle_settings').update({
      letter_count: lc,
      max_guesses: mg,
      updated_at: new Date().toISOString()
    }).eq('id', 1)
    wordleSettings.value.letter_count = lc
    wordleSettings.value.max_guesses = mg
    auditLog({ action: 'update', target_type: 'wordle_settings', target_label: `${lc} letters, ${mg} guesses` })
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function addWord() {
  const raw = newWord.value.trim().toLowerCase()
  if (!/^[a-z]+$/.test(raw)) { toast.error('Letters only'); return }
  try {
    const { error } = await supabase.from('wordle_words').insert({ word: raw, length: raw.length })
    if (error) throw error
    auditLog({ action: 'create', target_type: 'wordle_word', target_label: raw })
    newWord.value = ''
    toast.success('Added')
    await loadAll()
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function toggleWord(row: any) {
  try {
    await supabase.from('wordle_words').update({ is_active: !row.is_active }).eq('word', row.word)
    row.is_active = !row.is_active
    auditLog({ action: row.is_active ? 'activate' : 'deactivate', target_type: 'wordle_word', target_label: row.word })
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

async function deleteWord(row: any) {
  const ok = await toast.confirm({ title: 'Delete word', message: `Remove "${row.word}" from the pool?`, confirmLabel: 'Delete', variant: 'danger' })
  if (!ok) return
  await supabase.from('wordle_words').delete().eq('word', row.word)
  auditLog({ action: 'delete', target_type: 'wordle_word', target_label: row.word })
  await loadAll()
}

const wordsByLength = computed(() => {
  const m: Record<number, any[]> = {}
  for (const w of words.value) (m[w.length] ||= []).push(w)
  return m
})

const activeCounts = computed(() => {
  const m: Record<number, number> = {}
  for (const w of words.value) if (w.is_active) m[w.length] = (m[w.length] ?? 0) + 1
  return m
})

async function saveValue(row: any) {
  try {
    await supabase.from('kudos_values').update({
      label: row.label,
      emoji: row.emoji,
      color: row.color,
      is_active: row.is_active
    }).eq('id', row.id)
    auditLog({ action: 'update', target_type: 'kudos_value', target_id: row.id, target_label: row.label })
    toast.success('Saved')
  } catch (e: any) { toast.error(e.message ?? 'Failed') }
}

const canManage = computed(() => canManageSection('gamification'))
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-white">Gamification</h1>
      <p class="text-sm text-slate-400 mt-1">Tune point weights, manage badges, and schedule Daily Sparks.</p>
    </header>

    <div v-if="!canManage" class="bg-slate-800 border border-slate-700 rounded-xl p-6 text-sm text-slate-300">
      You do not have permission to manage gamification.
    </div>

    <div v-else>
      <div class="inline-flex p-0.5 bg-slate-800 rounded-lg text-xs font-medium mb-6">
        <button v-for="t in (['sparks','wordle','typing','weights','badges','values'] as const)" :key="t" type="button" @click="tab = t" :class="tab === t ? 'bg-slate-700 text-white' : 'text-slate-400 hover:text-slate-200'" class="px-3 py-1.5 rounded-md capitalize">
          {{ t }}
        </button>
      </div>

      <section v-if="tab === 'sparks'" class="space-y-6">
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-sm font-semibold text-white mb-4">{{ sparkForm.id ? 'Edit spark' : 'New spark' }}</h2>
          <div class="grid sm:grid-cols-2 gap-4">
            <label class="block">
              <span class="text-xs font-medium text-slate-300">Active on</span>
              <input type="date" v-model="sparkForm.active_on" class="mt-1 w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            </label>
            <label class="block">
              <span class="text-xs font-medium text-slate-300">Points</span>
              <input type="number" v-model.number="sparkForm.points_award" class="mt-1 w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            </label>
            <label class="block sm:col-span-2">
              <span class="text-xs font-medium text-slate-300">Question</span>
              <input v-model="sparkForm.question" class="mt-1 w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" placeholder="e.g. Which country is Sycamore headquartered in?" />
            </label>
            <div class="sm:col-span-2 grid sm:grid-cols-2 gap-2">
              <label v-for="i in 4" :key="i" class="block">
                <span class="text-xs font-medium text-slate-300">Option {{ String.fromCharCode(64 + i) }} <span v-if="sparkForm.correct_index === i - 1" class="text-emerald-400 font-bold">(correct)</span></span>
                <div class="flex gap-2 mt-1">
                  <input v-model="sparkForm.options[i - 1]" class="flex-1 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
                  <button type="button" @click="sparkForm.correct_index = i - 1" class="px-3 text-xs rounded-lg border border-slate-700" :class="sparkForm.correct_index === i - 1 ? 'bg-emerald-600 text-white border-emerald-500' : 'text-slate-300 hover:bg-slate-700'">Mark</button>
                </div>
              </label>
            </div>
            <label class="block sm:col-span-2 flex items-center gap-2 text-sm text-slate-300">
              <input type="checkbox" v-model="sparkForm.is_active" />
              Active
            </label>
          </div>
          <div class="flex justify-end gap-2 mt-4">
            <button type="button" v-if="sparkForm.id" @click="resetSpark" class="px-4 py-2 text-sm font-medium text-slate-300 hover:bg-slate-700 rounded-lg">Cancel</button>
            <button type="button" @click="saveSpark" class="px-4 py-2 text-sm font-semibold bg-sycamore-600 hover:bg-sycamore-500 text-white rounded-lg">{{ sparkForm.id ? 'Update' : 'Create' }}</button>
          </div>
        </div>

        <div class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
          <header class="px-5 py-3 border-b border-slate-700 text-sm font-semibold text-white">Scheduled</header>
          <div v-if="sparks.length === 0" class="p-5 text-sm text-slate-400">No sparks yet.</div>
          <table v-else class="w-full text-sm">
            <thead class="bg-slate-900/50 text-slate-400 text-xs uppercase tracking-wide">
              <tr>
                <th class="text-left px-5 py-2">Date</th>
                <th class="text-left px-5 py-2">Question</th>
                <th class="text-right px-5 py-2">Points</th>
                <th class="text-left px-5 py-2">Active</th>
                <th class="text-right px-5 py-2"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="s in sparks" :key="s.id" class="border-t border-slate-700/50 text-slate-200">
                <td class="px-5 py-3">{{ s.active_on }}</td>
                <td class="px-5 py-3 truncate max-w-sm">{{ s.question }}</td>
                <td class="px-5 py-3 text-right tabular-nums">{{ s.points_award }}</td>
                <td class="px-5 py-3">{{ s.is_active ? 'Yes' : 'No' }}</td>
                <td class="px-5 py-3 text-right space-x-2">
                  <button type="button" @click="editSpark(s)" class="text-sycamore-300 hover:underline text-xs">Edit</button>
                  <button type="button" @click="deleteSpark(s)" class="text-rose-400 hover:underline text-xs">Delete</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section v-if="tab === 'weights'" class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
        <header class="px-5 py-3 border-b border-slate-700 text-sm font-semibold text-white">Point weights</header>
        <table class="w-full text-sm">
          <thead class="bg-slate-900/50 text-slate-400 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Event</th>
              <th class="text-left px-5 py-2">Label</th>
              <th class="text-right px-5 py-2">Points</th>
              <th class="text-left px-5 py-2">Active</th>
              <th class="text-right px-5 py-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="w in weights" :key="w.id" class="border-t border-slate-700/50 text-slate-200">
              <td class="px-5 py-3 font-mono text-xs">{{ w.event_kind }}</td>
              <td class="px-5 py-3"><input v-model="w.label" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3 text-right"><input type="number" v-model.number="w.points" class="w-24 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm text-right tabular-nums" /></td>
              <td class="px-5 py-3"><input type="checkbox" v-model="w.is_active" /></td>
              <td class="px-5 py-3 text-right"><button type="button" @click="saveWeight(w)" class="text-sycamore-300 hover:underline text-xs">Save</button></td>
            </tr>
          </tbody>
        </table>
      </section>

      <section v-if="tab === 'badges'" class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
        <header class="px-5 py-3 border-b border-slate-700 text-sm font-semibold text-white">Badges</header>
        <table class="w-full text-sm">
          <thead class="bg-slate-900/50 text-slate-400 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Code</th>
              <th class="text-left px-5 py-2">Name</th>
              <th class="text-left px-5 py-2">Description</th>
              <th class="text-left px-5 py-2">Emoji</th>
              <th class="text-left px-5 py-2">Color</th>
              <th class="text-left px-5 py-2">Metric</th>
              <th class="text-right px-5 py-2">Threshold</th>
              <th class="text-left px-5 py-2">Active</th>
              <th class="text-right px-5 py-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="b in badges" :key="b.id" class="border-t border-slate-700/50 text-slate-200">
              <td class="px-5 py-3 font-mono text-xs">{{ b.code }}</td>
              <td class="px-5 py-3"><input v-model="b.name" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input v-model="b.description" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input v-model="b.emoji" class="w-16 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input v-model="b.color" class="w-24 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input v-model="b.metric" class="w-44 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-xs font-mono" /></td>
              <td class="px-5 py-3 text-right"><input type="number" v-model.number="b.threshold" class="w-20 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm text-right tabular-nums" /></td>
              <td class="px-5 py-3"><input type="checkbox" v-model="b.is_active" /></td>
              <td class="px-5 py-3 text-right"><button type="button" @click="saveBadge(b)" class="text-sycamore-300 hover:underline text-xs">Save</button></td>
            </tr>
          </tbody>
        </table>
      </section>

      <section v-if="tab === 'wordle'" class="space-y-6">
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-sm font-semibold text-white mb-1">Puzzle settings</h2>
          <p class="text-xs text-slate-400 mb-4">The only manual control. Daily word selection is automated and deterministic by date.</p>
          <div class="grid sm:grid-cols-3 gap-4 items-end">
            <label class="block">
              <span class="text-xs font-medium text-slate-300">Letters (3-9)</span>
              <input type="number" min="3" max="9" v-model.number="wordleSettings.letter_count" class="mt-1 w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
              <span class="text-[11px] text-slate-500 mt-1 block">{{ activeCounts[wordleSettings.letter_count] ?? 0 }} active words at this length</span>
            </label>
            <label class="block">
              <span class="text-xs font-medium text-slate-300">Max guesses (3-10)</span>
              <input type="number" min="3" max="10" v-model.number="wordleSettings.max_guesses" class="mt-1 w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            </label>
            <button type="button" @click="saveWordleSettings" class="px-4 py-2 text-sm font-semibold bg-sycamore-600 hover:bg-sycamore-500 text-white rounded-lg">Save settings</button>
          </div>
        </div>

        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-sm font-semibold text-white mb-1">Word pool</h2>
          <p class="text-xs text-slate-400 mb-4">The system picks from active words of the chosen length each day. Players never see this list.</p>
          <div class="flex gap-2 mb-4">
            <input v-model="newWord" placeholder="add a word..." class="flex-1 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white uppercase" />
            <button type="button" @click="addWord" class="px-4 py-2 text-sm font-semibold bg-sycamore-600 hover:bg-sycamore-500 text-white rounded-lg">Add</button>
          </div>
          <div class="space-y-4">
            <div v-for="(list, len) in wordsByLength" :key="len">
              <div class="text-xs font-semibold text-slate-400 uppercase tracking-wide mb-2">{{ len }} letters ({{ list.length }})</div>
              <div class="flex flex-wrap gap-2">
                <div v-for="w in list" :key="w.word" class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-mono font-semibold border" :class="w.is_active ? 'bg-slate-900 border-slate-600 text-slate-100' : 'bg-slate-900/40 border-slate-800 text-slate-500 line-through'">
                  <button type="button" @click="toggleWord(w)" class="uppercase">{{ w.word }}</button>
                  <button type="button" @click="deleteWord(w)" class="text-rose-400 hover:text-rose-300 ml-1">&times;</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section v-if="tab === 'typing'" class="space-y-6">
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-sm font-semibold text-white mb-1">Categories</h2>
          <p class="text-xs text-slate-400 mb-4">Buckets for prompts. Staff can filter by category in the Typing Sprint game.</p>
          <div class="grid sm:grid-cols-4 gap-2 mb-4">
            <input v-model="typingNewCategory.slug" placeholder="slug" class="bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            <input v-model="typingNewCategory.name" placeholder="name" class="bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            <input v-model="typingNewCategory.description" placeholder="description" class="bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            <button type="button" @click="addTypingCategory" class="px-4 py-2 text-sm font-semibold bg-sycamore-600 hover:bg-sycamore-500 text-white rounded-lg">Add category</button>
          </div>
          <div class="flex flex-wrap gap-2">
            <div v-for="c in typingCategories" :key="c.id" class="inline-flex items-center gap-2 px-3 py-1.5 rounded-full text-xs border" :class="c.is_active ? 'bg-slate-900 border-slate-600 text-slate-100' : 'bg-slate-900/40 border-slate-800 text-slate-500'">
              <span>{{ c.name }} <span class="text-slate-500">/{{ c.slug }}</span></span>
              <button type="button" @click="toggleTypingCategory(c)" class="text-amber-400 hover:text-amber-300">{{ c.is_active ? 'hide' : 'show' }}</button>
              <button type="button" @click="deleteTypingCategory(c)" class="text-rose-400 hover:text-rose-300">&times;</button>
            </div>
          </div>
        </div>

        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-sm font-semibold text-white mb-1">Prompts</h2>
          <p class="text-xs text-slate-400 mb-4">Phrases or sentences staff will type. Mark prompts with the right length tier so timed/sprint modes pick appropriate text.</p>
          <div class="grid sm:grid-cols-12 gap-2 mb-4">
            <select v-model="typingNew.category_id" class="sm:col-span-3 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white">
              <option v-for="c in typingCategories" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
            <select v-model="typingNew.length_tier" class="sm:col-span-2 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white">
              <option value="short">Short</option>
              <option value="medium">Medium</option>
              <option value="long">Long</option>
            </select>
            <input v-model="typingNew.text" placeholder="Type the prompt text..." class="sm:col-span-5 bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-sm text-white" />
            <button type="button" @click="addTypingPrompt" class="sm:col-span-2 px-4 py-2 text-sm font-semibold bg-sycamore-600 hover:bg-sycamore-500 text-white rounded-lg">Add prompt</button>
          </div>

          <div class="mb-3 flex items-center gap-2">
            <span class="text-xs uppercase tracking-wide text-slate-400">Filter</span>
            <select v-model="typingFilterCategory" class="bg-slate-900 border border-slate-700 rounded-lg px-3 py-1.5 text-xs text-white">
              <option value="">All categories</option>
              <option v-for="c in typingCategories" :key="c.id" :value="c.id">{{ c.name }}</option>
            </select>
            <span class="text-xs text-slate-500">{{ filteredTypingPrompts.length }} prompts</span>
          </div>

          <ul class="divide-y divide-slate-700">
            <li v-for="p in filteredTypingPrompts" :key="p.id" class="py-2 flex items-start justify-between gap-3">
              <div class="min-w-0 flex-1">
                <div class="text-[11px] uppercase tracking-wide text-slate-500">{{ p.category?.name ?? '—' }} · {{ p.length_tier }}</div>
                <div class="text-sm text-slate-100" :class="!p.is_active ? 'opacity-50 line-through' : ''">{{ p.text }}</div>
              </div>
              <div class="flex items-center gap-3 shrink-0">
                <button type="button" @click="toggleTypingPrompt(p)" class="text-xs text-amber-400 hover:text-amber-300">{{ p.is_active ? 'hide' : 'show' }}</button>
                <button type="button" @click="deleteTypingPrompt(p)" class="text-xs text-rose-400 hover:text-rose-300">delete</button>
              </div>
            </li>
          </ul>
        </div>
      </section>

      <section v-if="tab === 'values'" class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden">
        <header class="px-5 py-3 border-b border-slate-700 text-sm font-semibold text-white">Kudos values</header>
        <table class="w-full text-sm">
          <thead class="bg-slate-900/50 text-slate-400 text-xs uppercase tracking-wide">
            <tr>
              <th class="text-left px-5 py-2">Code</th>
              <th class="text-left px-5 py-2">Label</th>
              <th class="text-left px-5 py-2">Emoji</th>
              <th class="text-left px-5 py-2">Color</th>
              <th class="text-left px-5 py-2">Active</th>
              <th class="text-right px-5 py-2"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="v in values" :key="v.id" class="border-t border-slate-700/50 text-slate-200">
              <td class="px-5 py-3 font-mono text-xs">{{ v.code }}</td>
              <td class="px-5 py-3"><input v-model="v.label" class="w-full bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input v-model="v.emoji" class="w-16 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input v-model="v.color" class="w-24 bg-slate-900 border border-slate-700 rounded px-2 py-1 text-sm" /></td>
              <td class="px-5 py-3"><input type="checkbox" v-model="v.is_active" /></td>
              <td class="px-5 py-3 text-right"><button type="button" @click="saveValue(v)" class="text-sycamore-300 hover:underline text-xs">Save</button></td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
  </div>
</template>
