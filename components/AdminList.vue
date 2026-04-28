<script setup lang="ts">
type Column = { key: string, label: string, render?: (row: any) => string }

defineProps<{
  title: string
  description?: string
  columns: Column[]
  rows: any[]
  loading?: boolean
  newLabel?: string
}>()

const emit = defineEmits<{
  (e: 'new'): void
  (e: 'edit', row: any): void
  (e: 'delete', row: any): void
}>()
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
      <div v-if="loading" class="p-8 text-center text-slate-400 text-sm">Loading...</div>
      <div v-else-if="rows.length === 0" class="p-8 text-center text-slate-400 text-sm">No items yet. Create one to get started.</div>
      <div v-else>
        <div
          v-for="row in rows"
          :key="row.id"
          class="flex items-center gap-4 px-5 py-4 border-b border-slate-100 last:border-0 hover:bg-slate-50"
        >
          <div class="flex-1 grid grid-cols-1 md:grid-cols-4 gap-2 md:gap-4 min-w-0">
            <div v-for="c in columns" :key="c.key" class="text-sm text-slate-700 min-w-0">
              <div class="md:hidden text-xs text-slate-400 mb-0.5">{{ c.label }}</div>
              <div class="truncate" :class="{ 'font-medium text-slate-900': c.key === columns[0].key }">{{ c.render ? c.render(row) : row[c.key] }}</div>
            </div>
          </div>
          <div class="flex gap-1 shrink-0">
            <button class="p-2 rounded-lg hover:bg-sycamore-50 text-slate-600 hover:text-sycamore-700" @click="emit('edit', row)" aria-label="Edit"><SidebarIcon name="edit" /></button>
            <button class="p-2 rounded-lg hover:bg-rose-50 text-slate-600 hover:text-rose-700" @click="emit('delete', row)" aria-label="Delete"><SidebarIcon name="trash" /></button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
