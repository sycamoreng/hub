<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const { fetchBenefits } = useCompanyData()
const supabase = useSupabase()
const benefits = ref<any[]>([])
const hmoProviders = ref<any[]>([])
const learningBudgets = ref<any[]>([])
const selectedCat = ref('All')
const loading = ref(true)

function formatNGN(n: number, currency = 'NGN') {
  try {
    return new Intl.NumberFormat('en-NG', { style: 'currency', currency, maximumFractionDigits: 0 }).format(Number(n) || 0)
  } catch {
    return `${currency} ${Number(n).toLocaleString()}`
  }
}

onMounted(async () => {
  try {
    const [b, { data: hmo }, { data: lb }] = await Promise.all([
      fetchBenefits(),
      supabase.from('hmo_providers').select('*').eq('is_active', true).order('sort_order').order('name'),
      supabase.from('learning_budgets').select('*').eq('is_active', true).order('annual_amount', { ascending: false })
    ])
    benefits.value = b
    hmoProviders.value = hmo ?? []
    learningBudgets.value = lb ?? []
  } finally { loading.value = false }
})

const categories = computed(() => ['All', ...new Set(benefits.value.map(b => b.category))])
const filtered = computed(() =>
  selectedCat.value === 'All' ? benefits.value : benefits.value.filter(b => b.category === selectedCat.value)
)
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Benefits &amp; Perks</h1>
      <p class="section-subtitle">We invest in you. Here's what that looks like.</p>
    </div>

    <div class="flex flex-wrap gap-2 mb-6">
      <button
        v-for="c in categories"
        :key="c"
        @click="selectedCat = c"
        :class="[
          'px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors',
          selectedCat === c ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300'
        ]"
      >{{ c }}</button>
    </div>

    <div v-if="loading" class="text-slate-400">Loading benefits...</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="b in filtered" :key="b.id" class="card card-hover p-6">
        <div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center mb-4">
          <SidebarIcon name="gift" />
        </div>
        <h3 class="font-bold text-slate-900">{{ b.title }}</h3>
        <p class="text-sm text-slate-600 mt-2">{{ b.description }}</p>
        <div class="mt-4 pt-4 border-t border-slate-100 flex items-center justify-between text-xs">
          <span class="badge badge-green capitalize">{{ b.category }}</span>
          <span class="text-slate-500">{{ b.eligibility }}</span>
        </div>
      </article>
    </div>

    <section v-if="!loading && learningBudgets.length" class="mt-12">
      <header class="mb-4">
        <h2 class="text-xl font-semibold text-slate-900">Learning &amp; development budget</h2>
        <p class="text-sm text-slate-500 mt-1">Annual learning budget available per staff level. Speak with Human Capital to use yours.</p>
      </header>
      <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <article v-for="lb in learningBudgets" :key="lb.id" class="card p-5">
          <div class="text-xs uppercase tracking-wide text-slate-500 font-semibold">{{ lb.level }}</div>
          <div class="text-2xl font-bold text-slate-900 mt-1">{{ formatNGN(lb.annual_amount, lb.currency) }}</div>
          <div class="text-xs text-slate-500 mt-1">per year</div>
          <p v-if="lb.notes" class="text-xs text-slate-600 mt-3 whitespace-pre-line">{{ lb.notes }}</p>
        </article>
      </div>
    </section>

    <section v-if="!loading && hmoProviders.length" class="mt-12">
      <header class="mb-4">
        <h2 class="text-xl font-semibold text-slate-900">HMO providers</h2>
        <p class="text-sm text-slate-500 mt-1">Approved health management organizations and the cover available to staff.</p>
      </header>
      <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <article v-for="h in hmoProviders" :key="h.id" class="card card-hover p-5">
          <div class="flex items-center gap-3 mb-3">
            <img v-if="h.logo_url" :src="h.logo_url" :alt="h.name" class="w-10 h-10 rounded object-contain bg-white border border-slate-100" />
            <div v-else class="w-10 h-10 rounded bg-sycamore-50 text-sycamore-700 flex items-center justify-center font-bold">{{ h.name.charAt(0) }}</div>
            <h3 class="font-semibold text-slate-900">{{ h.name }}</h3>
          </div>
          <p v-if="h.description" class="text-sm text-slate-600">{{ h.description }}</p>
          <p v-if="h.coverage_summary" class="text-xs text-slate-500 mt-2 whitespace-pre-line">{{ h.coverage_summary }}</p>
          <div class="mt-3 flex flex-wrap gap-2 text-xs">
            <a v-if="h.website" :href="h.website" target="_blank" rel="noopener" class="text-sycamore-700 font-semibold">Website</a>
            <a v-if="h.contact_email" :href="`mailto:${h.contact_email}`" class="text-slate-600">{{ h.contact_email }}</a>
            <span v-if="h.contact_phone" class="text-slate-600">{{ h.contact_phone }}</span>
          </div>
          <a v-if="h.document_url" :href="h.document_url" target="_blank" rel="noopener"
            class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-white bg-slate-900 hover:bg-slate-800 px-3 py-1.5 rounded">
            View provider list
          </a>
        </article>
      </div>
    </section>
  </div>
</template>
