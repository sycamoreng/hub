<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const { profile } = useAuth()

const enrollment = ref<any | null>(null)
const provider = ref<any | null>(null)
const loading = ref(true)
const copied = ref(false)

async function load() {
  loading.value = true
  try {
    const staffId = profile.value?.id
    if (!staffId) { enrollment.value = null; return }
    const { data } = await supabase
      .from('staff_hmo_enrollments')
      .select('*, provider:hmo_providers(id, name, logo_url, website, contact_email, contact_phone, document_url, directory_url, coverage_summary, description)')
      .eq('staff_id', staffId)
      .maybeSingle()
    enrollment.value = data ?? null
    provider.value = data?.provider ?? null
  } finally {
    loading.value = false
  }
}

watch(() => profile.value?.id, () => { load() }, { immediate: true })

function formatDate(d: string | null | undefined) {
  if (!d) return ''
  try { return new Date(d).toLocaleDateString('en-NG', { year: 'numeric', month: 'long', day: 'numeric' }) } catch { return d }
}

async function copyEnrollee() {
  if (!enrollment.value?.enrollee_id) return
  try {
    await navigator.clipboard.writeText(enrollment.value.enrollee_id)
    copied.value = true
    setTimeout(() => { copied.value = false }, 1500)
  } catch {
    /* clipboard not available */
  }
}
</script>

<template>
  <div class="max-w-4xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">My HMO</h1>
      <p class="section-subtitle">Your enrollee details and approved health providers.</p>
    </div>

    <div v-if="loading" class="card p-8 text-sm text-slate-500">Loading your HMO details...</div>

    <template v-else-if="enrollment && (enrollment.enrollee_id || enrollment.plan_name || provider)">
      <article class="card p-6 sm:p-8 mb-6 bg-gradient-to-br from-sycamore-600 to-sycamore-800 text-white relative overflow-hidden">
        <div class="absolute -right-8 -top-8 w-40 h-40 rounded-full bg-white/10 pointer-events-none"></div>
        <div class="absolute right-10 bottom-0 w-24 h-24 rounded-full bg-white/5 pointer-events-none"></div>

        <div class="relative flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4">
          <div>
            <div class="text-xs uppercase tracking-[0.2em] text-white/70 font-semibold">Health Cover</div>
            <div class="mt-1 text-lg font-semibold">{{ provider?.name || 'HMO Provider' }}</div>
          </div>
          <div v-if="provider?.logo_url" class="bg-white rounded-lg p-2 w-14 h-14 flex items-center justify-center shrink-0">
            <img :src="provider.logo_url" :alt="provider.name" class="max-w-full max-h-full object-contain" />
          </div>
        </div>

        <div class="relative mt-8 grid sm:grid-cols-2 gap-6">
          <div>
            <div class="text-[11px] uppercase tracking-wider text-white/60 font-semibold mb-1">Enrollee ID</div>
            <div class="flex items-center gap-2">
              <span class="text-2xl font-bold tracking-wider font-mono">{{ enrollment.enrollee_id || '—' }}</span>
              <button
                v-if="enrollment.enrollee_id"
                type="button"
                @click="copyEnrollee"
                class="text-xs font-medium px-2 py-1 rounded bg-white/15 hover:bg-white/25 transition-colors"
              >{{ copied ? 'Copied' : 'Copy' }}</button>
            </div>
          </div>
          <div>
            <div class="text-[11px] uppercase tracking-wider text-white/60 font-semibold mb-1">Plan</div>
            <div class="text-2xl font-bold">{{ enrollment.plan_name || '—' }}</div>
          </div>
          <div v-if="enrollment.effective_date">
            <div class="text-[11px] uppercase tracking-wider text-white/60 font-semibold mb-1">Cover from</div>
            <div class="text-sm">{{ formatDate(enrollment.effective_date) }}</div>
          </div>
          <div v-if="profile?.full_name">
            <div class="text-[11px] uppercase tracking-wider text-white/60 font-semibold mb-1">Member</div>
            <div class="text-sm">{{ profile.full_name }}</div>
          </div>
        </div>

        <p v-if="enrollment.notes" class="relative mt-6 text-xs text-white/80 whitespace-pre-line">{{ enrollment.notes }}</p>
      </article>

      <div class="card p-6 mb-6">
        <h2 class="text-base font-semibold text-slate-900 mb-3">Find a hospital or clinic</h2>
        <p class="text-sm text-slate-600 mb-4">Use your enrollee ID at any hospital covered by your provider, or browse the full list of approved providers.</p>
        <div class="flex flex-wrap gap-3">
          <a
            v-if="provider?.directory_url"
            :href="provider.directory_url"
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2 rounded-lg bg-sycamore-600 hover:bg-sycamore-700 text-white"
          >
            See hospitals under {{ provider?.name || 'this provider' }}
            <SidebarIcon name="arrow-right" class="w-4 h-4" />
          </a>
          <NuxtLink
            to="/hmo/providers"
            class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2 rounded-lg border border-slate-200 text-slate-800 hover:bg-slate-50"
          >
            All approved providers
          </NuxtLink>
          <a
            v-if="provider?.document_url"
            :href="provider.document_url"
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2 rounded-lg border border-slate-200 text-slate-800 hover:bg-slate-50"
          >Provider list (PDF)</a>
          <a
            v-if="provider?.website"
            :href="provider.website"
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-2 text-sm font-semibold px-4 py-2 rounded-lg border border-slate-200 text-slate-800 hover:bg-slate-50"
          >Provider website</a>
        </div>
      </div>

      <div v-if="provider" class="card p-6 grid sm:grid-cols-2 gap-4">
        <div>
          <div class="text-xs uppercase tracking-wide text-slate-500 font-semibold mb-1">Cover summary</div>
          <p v-if="provider.coverage_summary" class="text-sm text-slate-700 whitespace-pre-line">{{ provider.coverage_summary }}</p>
          <p v-else class="text-sm text-slate-400">Not provided.</p>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide text-slate-500 font-semibold mb-1">Provider contact</div>
          <ul class="text-sm text-slate-700 space-y-1">
            <li v-if="provider.contact_email">
              Email: <a :href="`mailto:${provider.contact_email}`" class="text-sycamore-700 font-medium">{{ provider.contact_email }}</a>
            </li>
            <li v-if="provider.contact_phone">
              Phone: <a :href="`tel:${provider.contact_phone}`" class="text-sycamore-700 font-medium">{{ provider.contact_phone }}</a>
            </li>
            <li v-if="!provider.contact_email && !provider.contact_phone" class="text-slate-400">Contact not provided.</li>
          </ul>
        </div>
      </div>
    </template>

    <div v-else class="card p-8 text-center">
      <div class="w-12 h-12 mx-auto rounded-full bg-sycamore-50 text-sycamore-600 flex items-center justify-center mb-3">
        <SidebarIcon name="gift" class="w-6 h-6" />
      </div>
      <h2 class="text-base font-semibold text-slate-900">No HMO enrollment on file</h2>
      <p class="text-sm text-slate-500 mt-1 max-w-sm mx-auto">Once Human Capital adds your enrollee ID and plan, your card will appear here.</p>
      <NuxtLink to="/hmo/providers" class="inline-flex items-center gap-1 mt-5 text-sm font-semibold text-sycamore-700 hover:text-sycamore-800">
        Browse approved providers
        <SidebarIcon name="arrow-right" class="w-4 h-4" />
      </NuxtLink>
    </div>
  </div>
</template>
