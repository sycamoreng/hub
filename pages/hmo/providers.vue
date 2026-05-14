<script setup lang="ts">
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const providers = ref<any[]>([])
const loading = ref(true)
const search = ref('')

onMounted(async () => {
  try {
    const { data } = await supabase
      .from('hmo_providers')
      .select('*')
      .eq('is_active', true)
      .order('sort_order')
      .order('name')
    providers.value = data ?? []
  } finally {
    loading.value = false
  }
})

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return providers.value
  return providers.value.filter(p =>
    `${p.name ?? ''} ${p.description ?? ''} ${p.coverage_summary ?? ''}`.toLowerCase().includes(q)
  )
})
</script>

<template>
  <div class="max-w-6xl mx-auto">
    <div class="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <NuxtLink to="/hmo" class="inline-flex items-center gap-1 text-xs font-semibold text-sycamore-700 hover:text-sycamore-800 mb-2">
          <SidebarIcon name="arrow-right" class="w-3.5 h-3.5 -scale-x-100" />
          Back to my HMO
        </NuxtLink>
        <h1 class="section-title">Approved HMO providers</h1>
        <p class="section-subtitle">Show your enrollee ID at any of these providers to access cover.</p>
      </div>
      <input
        v-model="search"
        type="search"
        placeholder="Search providers..."
        class="input max-w-xs"
      />
    </div>

    <div v-if="loading" class="card p-8 text-sm text-slate-500">Loading providers...</div>
    <div v-else-if="!filtered.length" class="card p-8 text-center text-sm text-slate-500">
      No providers found{{ search ? ` for "${search}"` : '' }}.
    </div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="p in filtered" :key="p.id" class="card card-hover p-5 flex flex-col">
        <div class="flex items-center gap-3 mb-3">
          <img v-if="p.logo_url" :src="p.logo_url" :alt="p.name" class="w-12 h-12 rounded-lg object-contain bg-white border border-slate-100 p-1" />
          <div v-else class="w-12 h-12 rounded-lg bg-sycamore-50 text-sycamore-700 flex items-center justify-center font-bold text-lg">
            {{ p.name.charAt(0) }}
          </div>
          <h2 class="font-semibold text-slate-900 leading-tight">{{ p.name }}</h2>
        </div>

        <p v-if="p.description" class="text-sm text-slate-600">{{ p.description }}</p>
        <p v-if="p.coverage_summary" class="text-xs text-slate-500 mt-2 whitespace-pre-line">{{ p.coverage_summary }}</p>

        <div class="mt-3 flex flex-wrap gap-x-3 gap-y-1 text-xs text-slate-600">
          <a v-if="p.contact_email" :href="`mailto:${p.contact_email}`" class="hover:text-sycamore-700">{{ p.contact_email }}</a>
          <span v-if="p.contact_phone">{{ p.contact_phone }}</span>
        </div>

        <div class="mt-auto pt-4 flex flex-wrap gap-2">
          <a
            v-if="p.directory_url"
            :href="p.directory_url"
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-xs font-semibold text-white bg-sycamore-700 hover:bg-sycamore-800 px-3 py-1.5 rounded"
          >Hospitals (spreadsheet)</a>
          <a
            v-if="p.document_url"
            :href="p.document_url"
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-xs font-semibold text-white bg-slate-900 hover:bg-slate-800 px-3 py-1.5 rounded"
          >Provider list (PDF)</a>
          <a
            v-if="p.website"
            :href="p.website"
            target="_blank"
            rel="noopener"
            class="inline-flex items-center gap-1 text-xs font-semibold text-sycamore-700 hover:text-sycamore-800 px-3 py-1.5 rounded border border-sycamore-200"
          >Visit website</a>
        </div>
      </article>
    </div>
  </div>
</template>
