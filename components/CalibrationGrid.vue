<script setup lang="ts">
import { usePerformance } from '~/composables/usePerformance'

const props = defineProps<{ cycleId: string }>()
const { loadAppraisals } = usePerformance()
const appraisals = ref<any[]>([])
const loading = ref(true)

async function reload() {
  if (!props.cycleId) { appraisals.value = []; loading.value = false; return }
  loading.value = true
  try {
    appraisals.value = await loadAppraisals({ cycleId: props.cycleId })
  } finally {
    loading.value = false
  }
}

watch(() => props.cycleId, reload, { immediate: true })

const POS = [
  ['Enigma', 'Growth Employee', 'Future Leader'],
  ['Low Performer / Medium Potential', 'Core Player', 'High Performer / Medium Potential'],
  ['Low Performer / Low Potential', 'Solid Performer / Low Potential', 'High Performer / Low Potential']
]

const grid = computed(() => {
  const map: Record<string, any[]> = {}
  for (const a of appraisals.value) {
    const k = a.nine_box_position || ''
    if (!k) continue
    ;(map[k] ??= []).push(a)
  }
  return map
})

function cellClass(label: string): string {
  if (label.startsWith('High Performer') && label.includes('Medium')) return 'bg-leaf-50 border-leaf-200'
  if (label === 'Future Leader') return 'bg-leaf-100 border-leaf-300'
  if (label === 'Core Player') return 'bg-sycamore-50 border-sycamore-200'
  if (label === 'Growth Employee') return 'bg-sycamore-50 border-sycamore-200'
  if (label === 'Solid Performer / Low Potential') return 'bg-amber-50 border-amber-200'
  if (label.startsWith('Low Performer')) return 'bg-rose-50 border-rose-200'
  return 'bg-white border-slate-200'
}
</script>

<template>
  <section class="space-y-3">
    <header class="card p-5">
      <h2 class="text-lg font-bold text-slate-900">Calibration · 9-Box</h2>
      <p class="text-sm text-slate-500">Auto-positioned from objective and behavioural scores. Use this view to plan promotion, succession and PIP conversations.</p>
    </header>

    <div v-if="loading" class="card p-8 text-center text-sm text-slate-500">Loading...</div>
    <div v-else>
      <div class="flex">
        <div class="flex flex-col justify-around text-[11px] uppercase tracking-wide text-slate-500 pr-3 py-1 font-semibold">
          <span>High potential</span>
          <span>Medium potential</span>
          <span>Low potential</span>
        </div>
        <div class="grid grid-cols-3 gap-2 flex-1">
          <div
            v-for="cell in POS.flat()"
            :key="cell"
            class="rounded-xl border p-3 min-h-[140px]"
            :class="cellClass(cell)"
          >
            <div class="text-[11px] uppercase tracking-wide text-slate-600 font-semibold">{{ cell }}</div>
            <div class="text-xs text-slate-500 mb-2">{{ (grid[cell] ?? []).length }} staff</div>
            <ul class="space-y-1">
              <li v-for="a in (grid[cell] ?? [])" :key="a.id" class="text-xs text-slate-800 truncate">
                {{ a.subject?.full_name }}
                <span class="text-slate-400">({{ Number(a.final_score).toFixed(2) }})</span>
              </li>
            </ul>
          </div>
        </div>
      </div>
      <div class="grid grid-cols-3 gap-2 mt-2 text-[11px] uppercase tracking-wide text-slate-500 font-semibold pl-[88px]">
        <span class="text-center">Low performance</span>
        <span class="text-center">Medium performance</span>
        <span class="text-center">High performance</span>
      </div>
    </div>
  </section>
</template>
