<script setup lang="ts">
import type { ReactionKey, ReactionSummary, ReactionTargetType } from '~/composables/useFeed'
import { EMOJI_GROUPS, QUICK_EMOJIS } from '~/composables/useFeed'

const props = defineProps<{
  targetType: ReactionTargetType
  targetId: string
  summary: ReactionSummary
  reactorsByEmoji?: Record<string, string[]>
  disabled?: boolean
}>()

function reactorList(emoji: string): string[] {
  return props.reactorsByEmoji?.[emoji] ?? []
}

function reactorTitle(emoji: string): string {
  const names = reactorList(emoji)
  if (names.length === 0) return ''
  if (names.length <= 8) return names.join('\n')
  return names.slice(0, 8).join('\n') + `\n+${names.length - 8} more`
}

const emit = defineEmits<{
  (e: 'toggle', payload: { targetType: ReactionTargetType; targetId: string; emoji: ReactionKey; on: boolean }): void
}>()

const open = ref(false)
const rootEl = ref<HTMLElement | null>(null)
const triggerEl = ref<HTMLElement | null>(null)
const pickerEl = ref<HTMLElement | null>(null)
const pickerStyle = ref<Record<string, string>>({})

function close() { open.value = false }

function positionPicker() {
  if (!triggerEl.value) return
  const rect = triggerEl.value.getBoundingClientRect()
  const pickerWidth = 320
  const margin = 12
  const viewportW = window.innerWidth
  let left = rect.left
  if (left + pickerWidth + margin > viewportW) left = Math.max(margin, viewportW - pickerWidth - margin)
  pickerStyle.value = {
    top: `${rect.bottom + 8}px`,
    left: `${left}px`
  }
}

function onDocClick(e: MouseEvent) {
  if (!open.value) return
  const target = e.target as Node
  if (rootEl.value?.contains(target)) return
  if (pickerEl.value?.contains(target)) return
  open.value = false
}

function onScrollOrResize() {
  if (open.value) positionPicker()
}

async function toggleOpen() {
  open.value = !open.value
  if (open.value) {
    await nextTick()
    positionPicker()
  }
}

onMounted(() => {
  document.addEventListener('click', onDocClick)
  window.addEventListener('scroll', onScrollOrResize, true)
  window.addEventListener('resize', onScrollOrResize)
})
onBeforeUnmount(() => {
  document.removeEventListener('click', onDocClick)
  window.removeEventListener('scroll', onScrollOrResize, true)
  window.removeEventListener('resize', onScrollOrResize)
})

function pick(emoji: string) {
  if (props.disabled) return
  const on = props.summary.mine.has(emoji)
  emit('toggle', { targetType: props.targetType, targetId: props.targetId, emoji, on })
  close()
}
</script>

<template>
  <div ref="rootEl" class="flex flex-wrap items-center gap-1.5 mt-3 relative">
    <span
      v-for="e in summary.order"
      :key="e"
      class="relative group/reactor"
    >
      <button
        type="button"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium transition-colors"
        :class="summary.mine.has(e)
          ? 'bg-sycamore-50 border-sycamore-300 text-sycamore-700'
          : 'bg-white border-slate-200 text-slate-600 hover:bg-slate-50'"
        :disabled="disabled"
        :title="reactorTitle(e)"
        @click="pick(e)"
      >
        <span class="text-base leading-none">{{ e }}</span>
        <span class="text-[11px] text-slate-500">{{ summary.counts[e] || 0 }}</span>
      </button>
      <span
        v-if="reactorList(e).length"
        class="pointer-events-none absolute z-20 bottom-full left-1/2 -translate-x-1/2 mb-2 hidden group-hover/reactor:block"
      >
        <span class="block whitespace-nowrap max-w-xs bg-slate-900 text-white text-[11px] rounded-lg px-2.5 py-1.5 shadow-lg">
          <span class="block font-semibold mb-0.5">{{ e }} {{ reactorList(e).length }}</span>
          <span v-for="(name, i) in reactorList(e).slice(0, 8)" :key="i" class="block">{{ name }}</span>
          <span v-if="reactorList(e).length > 8" class="block text-slate-300">+{{ reactorList(e).length - 8 }} more</span>
        </span>
        <span class="block w-2 h-2 bg-slate-900 rotate-45 mx-auto -mt-1"></span>
      </span>
    </span>

    <button
      ref="triggerEl"
      type="button"
      class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full border border-dashed border-slate-300 text-xs font-medium text-slate-500 hover:bg-slate-50"
      :disabled="disabled"
      @click.stop="toggleOpen"
    >
      <SidebarIcon name="plus" />
      <span>React</span>
    </button>

    <Teleport to="body">
    <div
      v-if="open"
      ref="pickerEl"
      class="fixed z-[60] w-80 max-w-[calc(100vw-2rem)] bg-white border border-slate-200 rounded-xl shadow-xl p-3"
      :style="pickerStyle"
      @click.stop
    >
      <div class="mb-3">
        <div class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1.5">Quick</div>
        <div class="flex flex-wrap gap-1">
          <button
            v-for="e in QUICK_EMOJIS"
            :key="`quick-${e}`"
            type="button"
            class="w-9 h-9 flex items-center justify-center text-xl rounded-lg hover:bg-slate-100"
            :class="summary.mine.has(e) ? 'bg-sycamore-50 ring-1 ring-sycamore-300' : ''"
            @click="pick(e)"
          >{{ e }}</button>
        </div>
      </div>

      <div class="space-y-2 max-h-72 overflow-y-auto pr-1">
        <div v-for="g in EMOJI_GROUPS" :key="g.label">
          <div class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1.5">{{ g.label }}</div>
          <div class="flex flex-wrap gap-1">
            <button
              v-for="e in g.emojis"
              :key="`${g.label}-${e}`"
              type="button"
              class="w-9 h-9 flex items-center justify-center text-xl rounded-lg hover:bg-slate-100"
              :class="summary.mine.has(e) ? 'bg-sycamore-50 ring-1 ring-sycamore-300' : ''"
              @click="pick(e)"
            >{{ e }}</button>
          </div>
        </div>
      </div>
    </div>
    </Teleport>
  </div>
</template>
