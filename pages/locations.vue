<script setup lang="ts">
const { fetchLocations } = useCompanyData()
const locations = ref<any[]>([])
const selectedCountry = ref('All')
const loading = ref(true)

onMounted(async () => {
  try { locations.value = await fetchLocations() } finally { loading.value = false }
})

const countries = computed(() => ['All', ...new Set(locations.value.map(l => l.country))])
const filtered = computed(() =>
  selectedCountry.value === 'All' ? locations.value : locations.value.filter(l => l.country === selectedCountry.value)
)
</script>

<template>
  <div class="max-w-7xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Our Locations</h1>
      <p class="section-subtitle">Sycamore offices across the world.</p>
    </div>

    <div class="flex flex-wrap gap-2 mb-6">
      <button
        v-for="c in countries"
        :key="c"
        @click="selectedCountry = c"
        :class="[
          'px-4 py-2 rounded-lg text-sm font-medium transition-colors',
          selectedCountry === c ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300'
        ]"
      >{{ c }}</button>
    </div>

    <div v-if="loading" class="text-slate-400">Loading locations...</div>
    <div v-else class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
      <article v-for="l in filtered" :key="l.id" class="card card-hover p-6">
        <div class="flex items-center gap-2 mb-3 flex-wrap">
          <span v-if="l.is_headquarters" class="badge badge-green">Headquarters</span>
          <span class="badge badge-slate capitalize">{{ l.location_type }}</span>
          <span class="badge badge-blue">{{ l.staff_count }} staff</span>
        </div>
        <h3 class="text-lg font-bold text-slate-900">{{ l.name }}</h3>
        <div class="text-sm text-slate-600 mt-2">
          <div>{{ l.address }}</div>
          <div>{{ l.city }}<span v-if="l.state">, {{ l.state }}</span></div>
          <div class="text-slate-500">{{ l.country }}</div>
        </div>
        <div class="mt-4 pt-4 border-t border-slate-100 space-y-1.5 text-sm">
          <a v-if="l.phone" :href="`tel:${l.phone}`" class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">
            <SidebarIcon name="phone" /> {{ l.phone }}
          </a>
          <a v-if="l.email" :href="`mailto:${l.email}`" class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">
            <SidebarIcon name="mail" /> {{ l.email }}
          </a>
        </div>
      </article>
    </div>
  </div>
</template>
