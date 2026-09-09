<script setup lang="ts">
import type { AudienceType, DepartmentOption, StaffOption } from '~/composables/useSurveys'

const props = defineProps<{
  departments: DepartmentOption[]
  staff: StaffOption[]
}>()

const audienceType = defineModel<AudienceType>('audienceType', { required: true })
const departmentIds = defineModel<string[]>('departmentIds', { required: true })
const staffIds = defineModel<string[]>('staffIds', { required: true })

const staffSearch = ref('')

const filteredStaff = computed(() => {
  const q = staffSearch.value.trim().toLowerCase()
  if (!q) return props.staff
  return props.staff.filter(s => s.full_name.toLowerCase().includes(q))
})

function toggleDept(id: string) {
  const arr = departmentIds.value
  departmentIds.value = arr.includes(id) ? arr.filter(x => x !== id) : [...arr, id]
}

function toggleStaff(id: string) {
  const arr = staffIds.value
  staffIds.value = arr.includes(id) ? arr.filter(x => x !== id) : [...arr, id]
}

const options: { value: AudienceType; label: string; hint: string }[] = [
  { value: 'all', label: 'Everyone', hint: 'The whole organisation' },
  { value: 'departments', label: 'Specific departments', hint: 'Only people in the chosen departments' },
  { value: 'staff', label: 'Specific people', hint: 'Only the people you pick' }
]
</script>

<template>
  <div>
    <label class="block text-sm font-medium text-slate-600 mb-2">Who should receive this survey?</label>
    <div class="space-y-2">
      <label
        v-for="opt in options" :key="opt.value"
        class="flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors"
        :class="audienceType === opt.value ? 'border-sycamore-500 bg-sycamore-50/60' : 'border-slate-200 hover:bg-slate-50'"
      >
        <input type="radio" :value="opt.value" v-model="audienceType" class="mt-0.5 border-slate-300 text-sycamore-600">
        <span>
          <span class="block text-sm font-medium text-slate-800">{{ opt.label }}</span>
          <span class="block text-xs text-slate-400">{{ opt.hint }}</span>
        </span>
      </label>
    </div>

    <div v-if="audienceType === 'departments'" class="mt-3 border border-slate-200 rounded-lg p-3 max-h-52 overflow-y-auto space-y-1.5">
      <p v-if="departments.length === 0" class="text-sm text-slate-400">No departments found.</p>
      <label v-for="d in departments" :key="d.id" class="flex items-center gap-2 text-sm text-slate-700">
        <input type="checkbox" :checked="departmentIds.includes(d.id)" @change="toggleDept(d.id)" class="rounded border-slate-300 text-sycamore-600">
        {{ d.name }}
      </label>
    </div>

    <div v-else-if="audienceType === 'staff'" class="mt-3">
      <input v-model="staffSearch" class="input mb-2" placeholder="Search people by name">
      <div class="border border-slate-200 rounded-lg p-3 max-h-52 overflow-y-auto space-y-1.5">
        <p v-if="filteredStaff.length === 0" class="text-sm text-slate-400">No matching people.</p>
        <label v-for="s in filteredStaff" :key="s.auth_user_id" class="flex items-center gap-2 text-sm text-slate-700">
          <input type="checkbox" :checked="staffIds.includes(s.auth_user_id)" @change="toggleStaff(s.auth_user_id)" class="rounded border-slate-300 text-sycamore-600">
          {{ s.full_name }}
        </label>
      </div>
      <p class="text-xs text-slate-400 mt-1">{{ staffIds.length }} selected</p>
    </div>
  </div>
</template>
