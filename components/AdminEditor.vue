<script setup lang="ts">
type Field = {
  key: string
  label: string
  type?: 'text' | 'textarea' | 'select' | 'checkbox' | 'date' | 'number' | 'email' | 'tel'
  options?: { value: string, label: string }[]
  required?: boolean
  placeholder?: string
  hint?: string
  mention?: boolean
}

const props = defineProps<{
  open: boolean
  title: string
  fields: Field[]
  initial: Record<string, any> | null
  saving?: boolean
}>()

const emit = defineEmits<{
  (e: 'close'): void
  (e: 'save', payload: Record<string, any>): void
}>()

const form = ref<Record<string, any>>({})
const errors = ref<Record<string, string>>({})

watch(() => [props.open, props.initial], () => {
  if (props.open) {
    form.value = {}
    for (const f of props.fields) {
      const v = props.initial?.[f.key]
      form.value[f.key] = v ?? (f.type === 'checkbox' ? false : '')
    }
    errors.value = {}
  }
}, { immediate: true })

function validate() {
  errors.value = {}
  for (const f of props.fields) {
    if (f.required) {
      const v = form.value[f.key]
      if (v === '' || v === null || v === undefined) {
        errors.value[f.key] = `${f.label} is required`
      }
    }
  }
  return Object.keys(errors.value).length === 0
}

function submit() {
  if (!validate()) return
  emit('save', { ...form.value })
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
        <div class="bg-white rounded-2xl shadow-xl max-w-2xl w-full max-h-[90vh] flex flex-col">
          <header class="flex items-center justify-between p-6 border-b border-slate-100">
            <h2 class="text-xl font-bold text-slate-900">{{ title }}</h2>
            <button class="p-2 rounded-lg hover:bg-slate-100" @click="emit('close')" aria-label="Close">
              <SidebarIcon name="close" />
            </button>
          </header>
          <form @submit.prevent="submit" class="flex-1 overflow-y-auto p-6 space-y-5">
            <div v-for="f in fields" :key="f.key">
              <label :for="`f-${f.key}`" class="block text-sm font-medium text-slate-700 mb-1.5">
                {{ f.label }}<span v-if="f.required" class="text-rose-600 ml-0.5">*</span>
              </label>

              <MentionTextarea
                v-if="f.type === 'textarea' && f.mention"
                v-model="form[f.key]"
                :placeholder="f.placeholder"
                :rows="5"
              />

              <textarea
                v-else-if="f.type === 'textarea'"
                :id="`f-${f.key}`"
                v-model="form[f.key]"
                :placeholder="f.placeholder"
                rows="5"
                class="input"
              />

              <select
                v-else-if="f.type === 'select'"
                :id="`f-${f.key}`"
                v-model="form[f.key]"
                class="input"
              >
                <option value="" disabled>Select...</option>
                <option v-for="o in f.options" :key="o.value" :value="o.value">{{ o.label }}</option>
              </select>

              <label
                v-else-if="f.type === 'checkbox'"
                class="flex items-center gap-2 select-none cursor-pointer"
              >
                <input :id="`f-${f.key}`" type="checkbox" v-model="form[f.key]" class="w-4 h-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-300" />
                <span class="text-sm text-slate-700">{{ f.placeholder ?? 'Enabled' }}</span>
              </label>

              <input
                v-else
                :id="`f-${f.key}`"
                :type="f.type ?? 'text'"
                v-model="form[f.key]"
                :placeholder="f.placeholder"
                class="input"
              />

              <p v-if="errors[f.key]" class="text-xs text-rose-600 mt-1.5">{{ errors[f.key] }}</p>
              <p v-else-if="f.hint" class="text-xs text-slate-500 mt-1.5">{{ f.hint }}</p>
            </div>
          </form>
          <footer class="flex items-center justify-end gap-3 p-6 border-t border-slate-100">
            <button type="button" class="btn-secondary" @click="emit('close')">Cancel</button>
            <button type="button" class="btn-primary" :disabled="saving" @click="submit">
              <span v-if="saving">Saving...</span>
              <span v-else>Save</span>
            </button>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
