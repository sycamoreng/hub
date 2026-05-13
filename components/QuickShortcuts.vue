<script setup lang="ts">
import { SHORTCUT_CATALOG, DEFAULT_SHORTCUTS, getShortcutDef, useShortcuts } from '~/composables/useShortcuts'

const { user } = useAuth()
const toast = useToast()
const { loadPins, savePins } = useShortcuts()

const pins = ref<string[]>([...DEFAULT_SHORTCUTS])
const loading = ref(true)
const editing = ref(false)
const draft = ref<string[]>([])
const saving = ref(false)

async function load() {
  if (!user.value) { loading.value = false; return }
  try {
    pins.value = await loadPins(user.value.id)
  } finally {
    loading.value = false
  }
}
load()

const pinnedDefs = computed(() =>
  pins.value.map(getShortcutDef).filter((d): d is NonNullable<ReturnType<typeof getShortcutDef>> => !!d)
)

function openEditor() {
  draft.value = [...pins.value]
  editing.value = true
}

function toggleDraft(key: string) {
  if (draft.value.includes(key)) {
    draft.value = draft.value.filter(k => k !== key)
  } else {
    draft.value = [...draft.value, key]
  }
}

function move(key: string, dir: -1 | 1) {
  const idx = draft.value.indexOf(key)
  const next = idx + dir
  if (idx < 0 || next < 0 || next >= draft.value.length) return
  const copy = [...draft.value]
  ;[copy[idx], copy[next]] = [copy[next], copy[idx]]
  draft.value = copy
}

async function save() {
  if (!user.value) return
  saving.value = true
  try {
    await savePins(user.value.id, draft.value)
    pins.value = [...draft.value]
    toast.success('Shortcuts saved')
    editing.value = false
  } catch (e: any) {
    toast.error(e?.message ?? 'Could not save')
  } finally {
    saving.value = false
  }
}

function resetDefaults() {
  draft.value = [...DEFAULT_SHORTCUTS]
}

const available = computed(() =>
  SHORTCUT_CATALOG.filter(s => !draft.value.includes(s.key))
)
</script>

<template>
  <section class="relative">
    <div class="flex items-end justify-between mb-4">
      <div>
        <h2 class="text-2xl font-bold text-slate-900 tracking-tight">Your shortcuts</h2>
        <p class="text-sm text-slate-500">Tap anything to jump right in.</p>
      </div>
      <button
        type="button"
        class="btn-secondary !py-1.5 !px-3 text-xs"
        @click="openEditor"
      >
        <SidebarIcon name="edit" />
        Customize
      </button>
    </div>

    <div v-if="loading" class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
      <div v-for="i in 6" :key="i" class="h-28 rounded-2xl bg-slate-100 animate-pulse" />
    </div>
    <div v-else-if="pinnedDefs.length === 0" class="card p-6 text-center">
      <p class="text-sm text-slate-500">No shortcuts pinned yet.</p>
      <button class="btn-primary mt-3" @click="openEditor">Add your favourites</button>
    </div>
    <div v-else class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
      <NuxtLink
        v-for="s in pinnedDefs"
        :key="s.key"
        :to="s.to"
        class="group relative overflow-hidden rounded-2xl p-4 bg-gradient-to-br text-white min-h-[120px] flex flex-col justify-between shadow-sm hover:shadow-lg transition-all hover:-translate-y-0.5"
        :class="s.accent"
      >
        <div class="absolute -top-6 -right-6 w-24 h-24 rounded-full bg-white/10 blur-xl"></div>
        <div class="relative w-9 h-9 rounded-xl bg-white/20 ring-1 ring-white/30 backdrop-blur flex items-center justify-center">
          <SidebarIcon :name="s.icon" />
        </div>
        <div class="relative">
          <div class="font-semibold text-sm leading-tight">{{ s.label }}</div>
          <div class="text-[11px] text-white/80 mt-0.5">{{ s.description }}</div>
        </div>
        <div class="absolute top-3 right-3 opacity-0 group-hover:opacity-100 transition-opacity text-white/90">
          <SidebarIcon name="arrow-right" />
        </div>
      </NuxtLink>
    </div>

    <div
      v-if="editing"
      class="fixed inset-0 z-50 bg-slate-900/50 backdrop-blur-sm flex items-start sm:items-center justify-center p-4"
      @click.self="editing = false"
    >
      <div class="card w-full max-w-3xl max-h-[90vh] flex flex-col">
        <header class="p-6 border-b border-slate-100 flex items-start justify-between gap-4">
          <div>
            <h3 class="text-lg font-semibold text-slate-900">Customize your shortcuts</h3>
            <p class="text-sm text-slate-500 mt-0.5">Pick up to a dozen and arrange them how you like.</p>
          </div>
          <button class="text-slate-400 hover:text-slate-700 text-xl leading-none" @click="editing = false">&times;</button>
        </header>

        <div class="p-6 overflow-y-auto space-y-6">
          <div>
            <div class="flex items-center justify-between mb-3">
              <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500">Pinned ({{ draft.length }})</h4>
              <button class="text-xs text-sycamore-700 font-medium hover:underline" @click="resetDefaults">Reset to defaults</button>
            </div>
            <p v-if="draft.length === 0" class="text-sm text-slate-400">Nothing pinned yet. Pick from below.</p>
            <ul v-else class="space-y-2">
              <li
                v-for="(key, idx) in draft"
                :key="key"
                class="flex items-center gap-3 p-3 rounded-xl border border-slate-200 bg-slate-50"
              >
                <div
                  class="w-9 h-9 rounded-lg bg-gradient-to-br text-white flex items-center justify-center flex-shrink-0"
                  :class="getShortcutDef(key)?.accent ?? 'from-slate-400 to-slate-600'"
                >
                  <SidebarIcon :name="getShortcutDef(key)?.icon ?? 'arrow-right'" />
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-semibold text-sm text-slate-900">{{ getShortcutDef(key)?.label ?? key }}</div>
                  <div class="text-xs text-slate-500 truncate">{{ getShortcutDef(key)?.description ?? '' }}</div>
                </div>
                <div class="flex items-center gap-1">
                  <button
                    class="w-8 h-8 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 disabled:opacity-40 flex items-center justify-center"
                    :disabled="idx === 0"
                    @click="move(key, -1)"
                    aria-label="Move up"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M14.77 12.79a.75.75 0 0 1-1.06 0L10 9.06 6.29 12.77a.75.75 0 0 1-1.06-1.06l4.25-4.25a.75.75 0 0 1 1.06 0l4.23 4.23a.75.75 0 0 1 0 1.1Z" clip-rule="evenodd" /></svg>
                  </button>
                  <button
                    class="w-8 h-8 rounded-lg border border-slate-200 bg-white text-slate-600 hover:bg-slate-100 disabled:opacity-40 flex items-center justify-center"
                    :disabled="idx === draft.length - 1"
                    @click="move(key, 1)"
                    aria-label="Move down"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 0 1 1.06 0L10 10.94l3.71-3.71a.75.75 0 0 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.23 8.29a.75.75 0 0 1 0-1.08Z" clip-rule="evenodd" /></svg>
                  </button>
                  <button
                    class="w-8 h-8 rounded-lg border border-rose-200 bg-white text-rose-600 hover:bg-rose-50 flex items-center justify-center"
                    @click="toggleDraft(key)"
                    aria-label="Remove"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" /></svg>
                  </button>
                </div>
              </li>
            </ul>
          </div>

          <div>
            <h4 class="text-xs font-semibold uppercase tracking-wide text-slate-500 mb-3">Available ({{ available.length }})</h4>
            <p v-if="available.length === 0" class="text-sm text-slate-400">You've pinned everything. Impressive.</p>
            <div v-else class="grid grid-cols-2 sm:grid-cols-3 gap-2">
              <button
                v-for="s in available"
                :key="s.key"
                type="button"
                class="flex items-center gap-3 p-3 rounded-xl border border-slate-200 bg-white hover:border-sycamore-300 hover:bg-sycamore-50/40 transition-colors text-left"
                @click="toggleDraft(s.key)"
              >
                <div
                  class="w-9 h-9 rounded-lg bg-gradient-to-br text-white flex items-center justify-center flex-shrink-0"
                  :class="s.accent"
                >
                  <SidebarIcon :name="s.icon" />
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-semibold text-sm text-slate-900">{{ s.label }}</div>
                  <div class="text-xs text-slate-500 truncate">{{ s.description }}</div>
                </div>
                <SidebarIcon name="plus" />
              </button>
            </div>
          </div>
        </div>

        <footer class="p-6 border-t border-slate-100 flex items-center justify-end gap-2">
          <button class="btn-secondary" @click="editing = false">Cancel</button>
          <button class="btn-primary" :disabled="saving" @click="save">
            {{ saving ? 'Saving...' : 'Save shortcuts' }}
          </button>
        </footer>
      </div>
    </div>
  </section>
</template>
