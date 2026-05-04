<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const tab = ref<'employees' | 'runs' | 'settings'>('employees')
</script>

<template>
  <div class="max-w-6xl">
    <header class="mb-6">
      <h1 class="text-2xl font-semibold text-slate-900">Payroll</h1>
      <p class="text-sm text-slate-500 mt-1">
        Nigerian-compliant payroll: PAYE (Finance Act 2020), pension, NHF, and statutory toggles.
      </p>
    </header>

    <div class="flex flex-wrap gap-1 p-1 bg-slate-100 rounded-lg mb-6 w-fit">
      <button
        v-for="t in (['employees','runs','settings'] as const)"
        :key="t"
        type="button"
        @click="tab = t"
        class="px-4 py-2 rounded-md text-sm font-medium capitalize transition-colors"
        :class="tab === t ? 'bg-white text-sycamore-700 shadow-sm' : 'text-slate-600 hover:text-slate-900'"
      >
        {{ t }}
      </button>
    </div>

    <LazyPayrollEmployees v-if="tab === 'employees'" />
    <LazyPayrollRuns v-if="tab === 'runs'" />
    <LazyPayrollSettingsPanel v-if="tab === 'settings'" />
  </div>
</template>
