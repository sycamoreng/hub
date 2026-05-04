<script setup lang="ts">
import { useGamification } from '~/composables/useGamification'

const { user } = useAuth()
const { getTodaySpark, getMySparkResponse, answerSpark } = useGamification()
const toast = useToast()

const spark = ref<any>(null)
const myResponse = ref<any>(null)
const loading = ref(true)
const answering = ref(false)
const selectedIndex = ref<number | null>(null)

async function load() {
  loading.value = true
  try {
    const s = await getTodaySpark()
    spark.value = s
    if (s && user.value) {
      myResponse.value = await getMySparkResponse(s.id, user.value.id)
    }
  } finally {
    loading.value = false
  }
}
onMounted(load)

async function answer(idx: number) {
  if (!user.value || !spark.value || myResponse.value) return
  answering.value = true
  selectedIndex.value = idx
  try {
    const res = await answerSpark(spark.value.id, user.value.id, idx, spark.value.correct_index ?? null, spark.value.points_award ?? 5)
    myResponse.value = res
    if (res?.is_correct) toast.success(`+${spark.value.points_award} points!`)
    else toast.success('Thanks for playing!')
  } catch (e: any) {
    toast.error(e.message ?? 'Could not submit')
  } finally {
    answering.value = false
  }
}

const options = computed<string[]>(() => Array.isArray(spark.value?.options) ? spark.value.options : [])
const hasAnswered = computed(() => Boolean(myResponse.value))
</script>

<template>
  <section v-if="!loading && spark" class="relative overflow-hidden rounded-2xl bg-gradient-to-br from-amber-50 via-rose-50 to-sky-50 border border-amber-100 p-5 sm:p-6">
    <div class="absolute -top-8 -right-8 w-40 h-40 rounded-full bg-amber-200/40 blur-2xl"></div>
    <div class="relative flex items-start gap-3 mb-3">
      <div class="w-10 h-10 rounded-xl bg-white shadow-sm border border-amber-100 flex items-center justify-center text-xl">⚡</div>
      <div class="flex-1 min-w-0">
        <div class="text-[11px] uppercase tracking-[0.2em] font-bold text-amber-700">Daily Spark</div>
        <h3 class="text-base sm:text-lg font-semibold text-slate-900 leading-snug mt-0.5">{{ spark.question }}</h3>
      </div>
      <NuxtLink to="/recognition" class="hidden sm:inline-flex items-center gap-1 text-xs text-sycamore-700 font-medium hover:underline flex-shrink-0">Leaderboard →</NuxtLink>
    </div>
    <div class="relative grid sm:grid-cols-2 gap-2">
      <button
        v-for="(opt, i) in options"
        :key="i"
        type="button"
        :disabled="hasAnswered || answering"
        @click="answer(i)"
        class="text-left px-4 py-3 rounded-xl border text-sm font-medium transition-all"
        :class="[
          hasAnswered
            ? (spark.correct_index === i
                ? 'bg-emerald-50 border-emerald-300 text-emerald-800'
                : (myResponse?.choice_index === i ? 'bg-rose-50 border-rose-300 text-rose-800' : 'bg-white/70 border-slate-200 text-slate-500'))
            : 'bg-white/90 border-slate-200 text-slate-800 hover:border-sycamore-300 hover:shadow-sm'
        ]"
      >
        <span class="inline-flex items-center justify-center w-6 h-6 rounded-full bg-white border border-slate-200 text-xs font-bold mr-2">{{ String.fromCharCode(65 + i) }}</span>
        {{ opt }}
        <span v-if="hasAnswered && spark.correct_index === i" class="ml-2 text-xs font-semibold">Correct</span>
      </button>
    </div>
    <div v-if="hasAnswered" class="relative mt-3 text-xs text-slate-600">
      <span v-if="myResponse?.is_correct" class="font-semibold text-emerald-700">Nice — you earned {{ spark.points_award }} points today.</span>
      <span v-else class="font-semibold text-slate-600">Better luck tomorrow! +1 point for playing.</span>
    </div>
  </section>
</template>
