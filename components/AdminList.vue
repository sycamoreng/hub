<script setup lang="ts">
type Column = { key: string, label: string, render?: (row: any) => string }

const props = withDefaults(defineProps<{
  title: string
  description?: string
  columns: Column[]
  rows: any[]
  loading?: boolean
  newLabel?: string
  pageSize?: number
  searchable?: boolean
  itemLabel?: string
}>(), {
  pageSize: 25,
  searchable: true,
  itemLabel: 'items'
})

const emit = defineEmits<{
  (e: 'new'): void
  (e: 'edit', row: any): void
  (e: 'delete', row: any): void
}>()

const search = ref('')
const page = ref(1)

function rowText(row: any) {
  return props.columns
    .map(c => c.render ? c.render(row) : row[c.key])
    .filter(v => v != null && v !== '')
    .join(' ')
    .toLowerCase()
}

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  if (!q) return props.rows
  return props.rows.filter(r => rowText(r).includes(q))
})

const total = computed(() => filtered.value.length)
const totalPages = computed(() => Math.max(1, Math.ceil(total.value / props.pageSize)))

watch([total, () => props.pageSize], () => {
  if (page.value > totalPages.value) page.value = totalPages.value
})

const pageRows = computed(() => {
  const start = (page.value - 1) * props.pageSize
  return filtered.value.slice(start, start + props.pageSize)
})

const rangeLabel = computed(() => {
  if (total.value === 0) return `0 ${props.itemLabel}`
  const start = (page.value - 1) * props.pageSize + 1
  const end = Math.min(total.value, page.value * props.pageSize)
  return `${start}-${end} of ${total.value} ${props.itemLabel}`
})

function goto(p: number) {
  page.value = Math.min(Math.max(1, p), totalPages.value)
}
</script>

<template>
  <div>
    <div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-6">
      <div>
        <h1 class="section-title">{{ title }}</h1>
        <p v-if="description" class="section-subtitle">{{ description }}</p>
      </div>
      <button class="btn-primary" @click="emit('new')">
        <SidebarIcon name="plus" /> {{ newLabel ?? 'New' }}
      </button>
    </div>

    <div class="card overflow-hidden">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-5 py-3 border-b border-slate-100 bg-slate-50/60">
        <div class="text-xs font-medium text-slate-500">
          <span class="text-slate-700">{{ total }}</span> {{ itemLabel }}<span v-if="search && total !== rows.length"> (filtered from {{ rows.length }})</span>
        </div>
        <div v-if="searchable" class="w-full sm:w-72">
          <input
            v-model="search"
            type="search"
            placeholder="Search..."
            class="input w-full text-sm"
            @input="page = 1"
          />
        </div>
      </div>

      <div v-if="loading" class="p-8 text-center text-slate-400 text-sm">Loading...</div>
      <div v-else-if="rows.length === 0" class="p-8 text-center text-slate-400 text-sm">No items yet. Create one to get started.</div>
      <div v-else-if="total === 0" class="p-8 text-center text-slate-400 text-sm">No matches for "{{ search }}".</div>
      <div v-else>
        <div class="hidden md:grid items-center gap-4 px-5 py-2 border-b border-slate-100 bg-slate-50 text-[11px] uppercase tracking-wide text-slate-500 font-semibold">
          <div class="flex-1 grid gap-4" :style="{ gridTemplateColumns: `repeat(${columns.length}, minmax(0, 1fr))` }">
            <div v-for="c in columns" :key="c.key" class="truncate">{{ c.label }}</div>
          </div>
          <div class="w-[88px] shrink-0 text-right whitespace-nowrap">Actions</div>
        </div>
        <div
          v-for="row in pageRows"
          :key="row.id"
          class="flex items-center gap-4 px-5 py-4 border-b border-slate-100 last:border-0 hover:bg-slate-50"
        >
          <div class="flex-1 grid gap-2 md:gap-4 min-w-0" :style="{ gridTemplateColumns: `repeat(${columns.length}, minmax(0, 1fr))` }">
            <div v-for="c in columns" :key="c.key" class="text-sm text-slate-700 min-w-0">
              <div class="md:hidden text-xs text-slate-400 mb-0.5">{{ c.label }}</div>
              <div class="truncate" :class="{ 'font-medium text-slate-900': c.key === columns[0].key }">{{ c.render ? c.render(row) : row[c.key] }}</div>
            </div>
          </div>
          <div class="flex items-center gap-2 shrink-0 w-[88px] justify-end whitespace-nowrap">
            <slot name="row-actions" :row="row" />
            <button class="p-2 rounded-lg hover:bg-sycamore-50 text-slate-600 hover:text-sycamore-700" @click="emit('edit', row)" aria-label="Edit"><SidebarIcon name="edit" /></button>
            <button class="p-2 rounded-lg hover:bg-rose-50 text-slate-600 hover:text-rose-700" @click="emit('delete', row)" aria-label="Delete"><SidebarIcon name="trash" /></button>
          </div>
        </div>

        <div v-if="totalPages > 1" class="flex items-center justify-between gap-3 px-5 py-3 border-t border-slate-100 bg-slate-50/60 text-sm">
          <div class="text-xs text-slate-500">{{ rangeLabel }}</div>
          <div class="flex items-center gap-1">
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="page <= 1" @click="goto(1)">First</button>
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="page <= 1" @click="goto(page - 1)">Prev</button>
            <span class="px-2 text-xs text-slate-600">Page {{ page }} of {{ totalPages }}</span>
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="page >= totalPages" @click="goto(page + 1)">Next</button>
            <button class="px-2 py-1 rounded border border-slate-200 text-xs disabled:opacity-40" :disabled="page >= totalPages" @click="goto(totalPages)">Last</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
