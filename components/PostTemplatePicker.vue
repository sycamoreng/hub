<script setup lang="ts">
import { POST_TEMPLATES, type PostTemplateMeta, type PostKind } from '~/composables/useFeed'

const emit = defineEmits<{
  (e: 'apply', payload: { kind: PostKind; data: Record<string, any>; text: string }): void
  (e: 'close'): void
}>()

const props = defineProps<{ open: boolean }>()

const active = ref<PostTemplateMeta | null>(null)
const formData = ref<Record<string, any>>({})

watch(() => props.open, (v) => {
  if (!v) { active.value = null; formData.value = {} }
})

function pick(t: PostTemplateMeta) {
  active.value = t
  formData.value = {}
}

function back() { active.value = null; formData.value = {} }

function apply() {
  if (!active.value) return
  const text = active.value.defaultText(formData.value)
  emit('apply', { kind: active.value.kind, data: { ...formData.value }, text })
  emit('close')
}
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition duration-200"
      enter-from-class="opacity-0"
      leave-active-class="transition duration-150"
      leave-to-class="opacity-0"
    >
      <div v-if="open" class="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4" @click.self="emit('close')">
        <div class="bg-white rounded-2xl shadow-xl max-w-lg w-full max-h-[90vh] flex flex-col overflow-hidden">
          <header class="flex items-center justify-between px-6 py-4 border-b border-slate-100">
            <div class="flex items-center gap-3 min-w-0">
              <button v-if="active" class="p-1.5 rounded-lg hover:bg-slate-100" @click="back" aria-label="Back">
                <SidebarIcon name="arrow-left" />
              </button>
              <div class="min-w-0">
                <h2 class="text-lg font-bold text-slate-900 truncate">{{ active ? active.promptTitle : 'Choose a template' }}</h2>
                <p class="text-xs text-slate-500 mt-0.5 truncate">
                  {{ active ? 'Personalise it, then add to your post.' : 'Pick a vibe to start a richer post.' }}
                </p>
              </div>
            </div>
            <button class="p-2 rounded-lg hover:bg-slate-100" @click="emit('close')" aria-label="Close">
              <SidebarIcon name="close" />
            </button>
          </header>

          <div class="flex-1 overflow-y-auto p-6">
            <div v-if="!active" class="grid grid-cols-2 gap-3">
              <button
                v-for="t in POST_TEMPLATES"
                :key="t.kind"
                type="button"
                class="group text-left p-4 rounded-xl border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50/40 transition-all"
                @click="pick(t)"
              >
                <div :class="['w-10 h-10 rounded-lg bg-gradient-to-br text-white flex items-center justify-center text-xl mb-2', t.accent]">{{ t.emoji }}</div>
                <div class="text-sm font-semibold text-slate-900">{{ t.label }}</div>
                <div class="text-xs text-slate-500 mt-0.5 line-clamp-2">{{ t.defaultText({}) }}</div>
              </button>
            </div>

            <div v-else class="space-y-4">
              <div :class="['rounded-xl p-4 text-white bg-gradient-to-br', active.accent]">
                <div class="text-2xl">{{ active.emoji }}</div>
                <div class="text-sm font-semibold mt-1">{{ active.label }}</div>
              </div>

              <div v-for="f in (active.fields || [])" :key="f.key">
                <label class="block text-xs font-medium text-slate-700 mb-1">{{ f.label }}</label>
                <input
                  v-model="formData[f.key]"
                  :type="f.type || 'text'"
                  :placeholder="f.placeholder"
                  class="input"
                />
              </div>

              <div class="rounded-xl border border-dashed border-slate-200 p-4 bg-slate-50">
                <div class="text-[10px] font-semibold text-slate-400 uppercase tracking-wide mb-1">Preview</div>
                <p class="text-sm text-slate-700 whitespace-pre-line">{{ active.defaultText(formData) }}</p>
              </div>
            </div>
          </div>

          <footer v-if="active" class="flex items-center justify-end gap-3 px-6 py-4 border-t border-slate-100">
            <button type="button" class="btn-secondary" @click="back">Back</button>
            <button type="button" class="btn-primary" @click="apply">Use template</button>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
