<script setup lang="ts">
const { fetchKeyContacts } = useCompanyData()
const contacts = ref<any[]>([])
const loading = ref(true)

onMounted(async () => {
  try { contacts.value = await fetchKeyContacts() } finally { loading.value = false }
})

const emergency = computed(() => contacts.value.filter(c => c.is_emergency))
const regular = computed(() => contacts.value.filter(c => !c.is_emergency))
</script>

<template>
  <div class="max-w-5xl mx-auto space-y-8">
    <div>
      <h1 class="section-title">Key Contacts</h1>
      <p class="section-subtitle">Know who to reach out to for what.</p>
    </div>

    <div v-if="loading" class="text-slate-400">Loading contacts...</div>

    <section v-if="!loading && emergency.length" class="rounded-2xl border-2 border-rose-200 bg-rose-50 p-6">
      <div class="flex items-center gap-2 mb-4">
        <div class="w-9 h-9 rounded-lg bg-rose-600 text-white flex items-center justify-center"><SidebarIcon name="alert" /></div>
        <h2 class="text-lg font-bold text-rose-900">Emergency Contacts</h2>
      </div>
      <div class="grid sm:grid-cols-2 gap-3">
        <article v-for="c in emergency" :key="c.id" class="bg-white rounded-lg p-4 border border-rose-100">
          <h3 class="font-semibold text-slate-900">{{ c.name }}</h3>
          <div class="text-sm text-slate-600">{{ c.role }}</div>
          <div class="text-sm space-y-1 mt-3">
            <a v-if="c.phone" :href="`tel:${c.phone}`" class="flex items-center gap-2 text-rose-700 font-semibold"><SidebarIcon name="phone" /> {{ c.phone }}</a>
            <a v-if="c.email" :href="`mailto:${c.email}`" class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700"><SidebarIcon name="mail" /> {{ c.email }}</a>
          </div>
        </article>
      </div>
    </section>

    <section v-if="!loading && regular.length">
      <h2 class="text-lg font-bold text-slate-900 mb-4">Department Contacts</h2>
      <div class="grid sm:grid-cols-2 gap-4">
        <article v-for="c in regular" :key="c.id" class="card p-5">
          <div class="flex items-start justify-between mb-2">
            <h3 class="font-semibold text-slate-900">{{ c.name }}</h3>
            <span v-if="c.department" class="badge badge-green">{{ c.department }}</span>
          </div>
          <div class="text-sm text-slate-600">{{ c.role }}</div>
          <div class="text-sm space-y-1 mt-3 pt-3 border-t border-slate-100">
            <a v-if="c.email" :href="`mailto:${c.email}`" class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700"><SidebarIcon name="mail" /> {{ c.email }}</a>
            <a v-if="c.phone" :href="`tel:${c.phone}`" class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700"><SidebarIcon name="phone" /> {{ c.phone }}</a>
          </div>
        </article>
      </div>
    </section>
  </div>
</template>
