<script setup lang="ts">
const { items, dismiss, confirmState, resolveConfirm } = useToast()

const variantClasses: Record<string, { ring: string; icon: string; iconBg: string; bar: string }> = {
  success: { ring: 'ring-leaf-200', icon: 'text-leaf-700', iconBg: 'bg-leaf-100', bar: 'bg-leaf-500' },
  error: { ring: 'ring-rose-200', icon: 'text-rose-700', iconBg: 'bg-rose-100', bar: 'bg-rose-500' },
  warning: { ring: 'ring-amber-200', icon: 'text-amber-700', iconBg: 'bg-amber-100', bar: 'bg-amber-500' },
  info: { ring: 'ring-sycamore-200', icon: 'text-sycamore-700', iconBg: 'bg-sycamore-100', bar: 'bg-sycamore-500' }
}

const iconNames: Record<string, string> = {
  success: 'check',
  error: 'alert',
  warning: 'alert',
  info: 'info'
}
</script>

<template>
  <Teleport to="body">
    <div class="fixed top-4 right-4 z-[100] flex flex-col gap-3 w-[min(22rem,calc(100vw-2rem))] pointer-events-none">
      <TransitionGroup name="toast">
        <div
          v-for="t in items"
          :key="t.id"
          class="pointer-events-auto bg-white rounded-xl shadow-lg ring-1 overflow-hidden flex items-stretch"
          :class="variantClasses[t.variant].ring"
        >
          <div class="w-1" :class="variantClasses[t.variant].bar" />
          <div class="flex items-start gap-3 p-3.5 flex-1">
            <div
              class="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0"
              :class="[variantClasses[t.variant].iconBg, variantClasses[t.variant].icon]"
            >
              <SidebarIcon :name="iconNames[t.variant]" />
            </div>
            <div class="min-w-0 flex-1">
              <div v-if="t.title" class="text-sm font-semibold text-slate-900">{{ t.title }}</div>
              <div class="text-sm text-slate-700" :class="t.title ? 'mt-0.5' : ''">{{ t.message }}</div>
            </div>
            <button
              type="button"
              class="text-slate-400 hover:text-slate-700 flex-shrink-0 -mt-0.5"
              aria-label="Dismiss"
              @click="dismiss(t.id)"
            >
              <SidebarIcon name="close" />
            </button>
          </div>
        </div>
      </TransitionGroup>
    </div>

    <Transition name="confirm">
      <div
        v-if="confirmState.open"
        class="fixed inset-0 z-[110] flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-sm"
        @click.self="resolveConfirm(false)"
      >
        <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden">
          <div class="p-6">
            <div class="flex items-start gap-4">
              <div
                class="w-10 h-10 rounded-full flex items-center justify-center flex-shrink-0"
                :class="confirmState.variant === 'danger' ? 'bg-rose-100 text-rose-700' : 'bg-sycamore-100 text-sycamore-700'"
              >
                <SidebarIcon name="alert" />
              </div>
              <div class="min-w-0 flex-1">
                <h3 class="text-base font-semibold text-slate-900">{{ confirmState.title }}</h3>
                <p class="text-sm text-slate-600 mt-1.5 whitespace-pre-line">{{ confirmState.message }}</p>
              </div>
            </div>
          </div>
          <div class="bg-slate-50 px-6 py-3.5 flex items-center justify-end gap-2 border-t border-slate-100">
            <button
              type="button"
              class="px-3.5 py-1.5 rounded-lg text-sm font-medium text-slate-700 hover:bg-slate-200/60"
              @click="resolveConfirm(false)"
            >
              {{ confirmState.cancelLabel }}
            </button>
            <button
              type="button"
              class="px-3.5 py-1.5 rounded-lg text-sm font-semibold text-white"
              :class="confirmState.variant === 'danger' ? 'bg-rose-600 hover:bg-rose-700' : 'bg-sycamore-700 hover:bg-sycamore-800'"
              @click="resolveConfirm(true)"
            >
              {{ confirmState.confirmLabel }}
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.toast-enter-active, .toast-leave-active { transition: all 0.25s cubic-bezier(.25,.1,.25,1); }
.toast-enter-from { opacity: 0; transform: translateX(20px); }
.toast-leave-to { opacity: 0; transform: translateX(20px); }
.confirm-enter-active, .confirm-leave-active { transition: opacity 0.2s ease; }
.confirm-enter-from, .confirm-leave-to { opacity: 0; }
</style>
