<script setup lang="ts">
import { useMentions } from '~/composables/useMentions'

const props = defineProps<{
  modelValue: string
  rows?: number
  maxlength?: number
  placeholder?: string
  inputClass?: string
}>()

const emit = defineEmits<{
  (e: 'update:modelValue', v: string): void
}>()

const { suggestions, loadSuggestions } = useMentions()

const textareaEl = ref<HTMLTextAreaElement | null>(null)
const query = ref<string | null>(null)
const anchor = ref(0)
const highlight = ref(0)

onMounted(() => { loadSuggestions() })

const matches = computed(() => {
  if (query.value === null) return []
  const q = query.value.toLowerCase()
  return suggestions.value.filter(s => s.full_name.toLowerCase().includes(q)).slice(0, 6)
})

function onInput(e: Event) {
  const v = (e.target as HTMLTextAreaElement).value
  emit('update:modelValue', v)
  const el = textareaEl.value
  if (!el) return
  const cursor = el.selectionStart ?? v.length
  const upto = v.slice(0, cursor)
  const at = upto.lastIndexOf('@')
  if (at === -1) { query.value = null; return }
  const after = upto.slice(at + 1)
  if (/\s/.test(after) || after.length > 30) { query.value = null; return }
  const before = at === 0 ? '' : upto[at - 1]
  if (before && !/\s/.test(before)) { query.value = null; return }
  query.value = after
  anchor.value = at
  highlight.value = 0
}

function applyMention(name: string) {
  if (query.value === null) return
  const el = textareaEl.value
  const start = anchor.value
  const end = (el?.selectionStart ?? props.modelValue.length)
  const before = props.modelValue.slice(0, start)
  const after = props.modelValue.slice(end)
  const insert = '@' + name + ' '
  const next = before + insert + after
  emit('update:modelValue', next)
  query.value = null
  nextTick(() => {
    if (el) {
      const pos = (before + insert).length
      el.focus()
      el.setSelectionRange(pos, pos)
    }
  })
}

function onBlur() { setTimeout(() => { query.value = null }, 150) }

function onKey(e: KeyboardEvent) {
  if (query.value === null) return
  const m = matches.value
  if (m.length === 0) return
  if (e.key === 'ArrowDown') { e.preventDefault(); highlight.value = (highlight.value + 1) % m.length }
  else if (e.key === 'ArrowUp') { e.preventDefault(); highlight.value = (highlight.value - 1 + m.length) % m.length }
  else if (e.key === 'Enter' || e.key === 'Tab') { e.preventDefault(); applyMention(m[highlight.value].full_name) }
  else if (e.key === 'Escape') { query.value = null }
}
</script>

<template>
  <div class="relative">
    <textarea
      ref="textareaEl"
      :value="modelValue"
      :rows="rows ?? 4"
      :maxlength="maxlength"
      :placeholder="placeholder"
      :class="inputClass ?? 'input'"
      @input="onInput"
      @keydown="onKey"
      @blur="onBlur"
    />
    <div
      v-if="query !== null && matches.length"
      class="absolute z-10 left-0 right-0 sm:right-auto sm:w-72 mt-1 bg-white border border-slate-200 rounded-lg shadow-lg overflow-hidden"
    >
      <button
        v-for="(s, i) in matches"
        :key="s.id"
        type="button"
        class="w-full text-left px-3 py-2 text-sm flex items-center gap-2"
        :class="i === highlight ? 'bg-sycamore-50 text-sycamore-800' : 'hover:bg-slate-50 text-slate-700'"
        @mousedown.prevent="applyMention(s.full_name)"
      >
        <span class="text-xs text-slate-400">@</span>
        <span class="font-medium">{{ s.full_name }}</span>
      </button>
    </div>
  </div>
</template>
