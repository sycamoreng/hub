<script setup lang="ts">
interface CalendarEvent {
  id: string
  title: string
  description?: string
  event_date: string
  event_type?: string
  is_recurring?: boolean
}

const { fetchHolidaysEvents } = useCompanyData()
const events = ref<CalendarEvent[]>([])
const loading = ref(true)

onMounted(async () => {
  try { events.value = await fetchHolidaysEvents() } finally { loading.value = false }
})

const today = new Date()
const todayKey = ymd(today)
const cursor = ref({ year: today.getFullYear(), month: today.getMonth() })

function ymd(d: Date) {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

function parseLocalDate(s: string): Date | null {
  if (!s) return null
  const parts = s.slice(0, 10).split('-').map(Number)
  if (parts.length !== 3 || parts.some(n => Number.isNaN(n))) return null
  return new Date(parts[0], parts[1] - 1, parts[2])
}

function expandRecurring(e: CalendarEvent, year: number): { date: string; e: CalendarEvent }[] {
  const base = parseLocalDate(e.event_date)
  if (!base) return []
  if (!e.is_recurring) return [{ date: e.event_date.slice(0, 10), e }]
  const out: { date: string; e: CalendarEvent }[] = []
  for (let y = year - 1; y <= year + 1; y++) {
    const d = new Date(y, base.getMonth(), base.getDate())
    out.push({ date: ymd(d), e })
  }
  return out
}

const eventsByDate = computed(() => {
  const map: Record<string, CalendarEvent[]> = {}
  for (const e of events.value) {
    for (const inst of expandRecurring(e, cursor.value.year)) {
      if (!map[inst.date]) map[inst.date] = []
      map[inst.date].push(inst.e)
    }
  }
  return map
})

const monthLabel = computed(() =>
  new Date(cursor.value.year, cursor.value.month, 1).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
)

const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

interface DayCell {
  date: Date
  key: string
  inMonth: boolean
  isToday: boolean
  events: CalendarEvent[]
}

const grid = computed<DayCell[]>(() => {
  const { year, month } = cursor.value
  const first = new Date(year, month, 1)
  const startOffset = (first.getDay() + 6) % 7 // Monday-first
  const start = new Date(year, month, 1 - startOffset)
  const cells: DayCell[] = []
  for (let i = 0; i < 42; i++) {
    const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i)
    const key = ymd(d)
    cells.push({
      date: d,
      key,
      inMonth: d.getMonth() === month,
      isToday: key === todayKey,
      events: eventsByDate.value[key] || []
    })
  }
  return cells
})

function shiftMonth(delta: number) {
  let m = cursor.value.month + delta
  let y = cursor.value.year
  while (m < 0) { m += 12; y -= 1 }
  while (m > 11) { m -= 12; y += 1 }
  cursor.value = { year: y, month: m }
}

function goToday() {
  cursor.value = { year: today.getFullYear(), month: today.getMonth() }
}

const selectedKey = ref<string | null>(null)
const selectedEvents = computed(() => (selectedKey.value ? eventsByDate.value[selectedKey.value] || [] : []))

const upcomingAcrossYear = computed(() => {
  const out: { date: string; e: CalendarEvent }[] = []
  for (const e of events.value) {
    for (const inst of expandRecurring(e, cursor.value.year)) {
      if (inst.date >= todayKey) out.push(inst)
    }
  }
  return out.sort((a, b) => a.date.localeCompare(b.date)).slice(0, 6)
})

function badgeClass(t?: string) {
  if (t === 'holiday') return 'bg-rose-100 text-rose-700'
  if (t === 'company') return 'bg-emerald-100 text-emerald-700'
  if (t === 'training') return 'bg-sky-100 text-sky-700'
  return 'bg-slate-100 text-slate-700'
}

function dotClass(t?: string) {
  if (t === 'holiday') return 'bg-rose-500'
  if (t === 'company') return 'bg-emerald-500'
  if (t === 'training') return 'bg-sky-500'
  return 'bg-slate-400'
}

function formatFull(d: string) {
  const parsed = parseLocalDate(d)
  return (parsed || new Date(d)).toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })
}
</script>

<template>
  <div class="max-w-6xl mx-auto space-y-8">
    <div>
      <h1 class="section-title">Calendar &amp; Events</h1>
      <p class="section-subtitle">Browse company events, holidays, and important dates across any month.</p>
    </div>

    <div v-if="loading" class="text-slate-400">Loading events...</div>

    <div v-else class="grid lg:grid-cols-[1fr_320px] gap-6 items-start">
      <section class="card p-4 sm:p-6">
        <div class="flex items-center justify-between mb-4 gap-3">
          <div class="flex items-center gap-1">
            <button @click="shiftMonth(-12)" class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Previous year">&laquo;</button>
            <button @click="shiftMonth(-1)" class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Previous month">&lsaquo;</button>
          </div>
          <div class="flex-1 text-center">
            <h2 class="text-lg font-bold text-slate-900">{{ monthLabel }}</h2>
          </div>
          <div class="flex items-center gap-1">
            <button @click="goToday" class="px-3 py-1.5 rounded-lg text-xs font-semibold text-sycamore-700 hover:bg-sycamore-50">Today</button>
            <button @click="shiftMonth(1)" class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Next month">&rsaquo;</button>
            <button @click="shiftMonth(12)" class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Next year">&raquo;</button>
          </div>
        </div>

        <div class="grid grid-cols-7 gap-px bg-slate-100 rounded-lg overflow-hidden border border-slate-100">
          <div v-for="d in weekdayLabels" :key="d" class="bg-slate-50 text-[11px] font-semibold uppercase tracking-wide text-slate-500 text-center py-2">{{ d }}</div>
          <button
            v-for="cell in grid"
            :key="cell.key"
            type="button"
            @click="selectedKey = cell.key"
            class="bg-white text-left p-2 min-h-[88px] flex flex-col gap-1 transition-colors"
            :class="[
              cell.inMonth ? 'text-slate-800' : 'text-slate-300 bg-slate-50/50',
              selectedKey === cell.key ? 'ring-2 ring-sycamore-500 ring-inset' : 'hover:bg-slate-50'
            ]"
          >
            <span
              class="inline-flex items-center justify-center w-6 h-6 rounded-full text-xs font-semibold"
              :class="cell.isToday ? 'bg-sycamore-600 text-white' : ''"
            >{{ cell.date.getDate() }}</span>
            <div class="flex-1 flex flex-col gap-0.5 overflow-hidden">
              <div
                v-for="ev in cell.events.slice(0, 3)"
                :key="ev.id + cell.key"
                class="flex items-center gap-1 truncate text-[11px] leading-tight"
              >
                <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" :class="dotClass(ev.event_type)" />
                <span class="truncate">{{ ev.title }}</span>
              </div>
              <div v-if="cell.events.length > 3" class="text-[10px] text-slate-400">+{{ cell.events.length - 3 }} more</div>
            </div>
          </button>
        </div>

        <div class="flex flex-wrap gap-3 mt-4 text-xs text-slate-500">
          <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-emerald-500" /> Company</span>
          <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-rose-500" /> Holiday</span>
          <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-sky-500" /> Training</span>
          <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-slate-400" /> Other</span>
        </div>
      </section>

      <aside class="space-y-6">
        <div class="card p-5">
          <h3 class="font-bold text-slate-900 mb-1">{{ selectedKey ? formatFull(selectedKey) : 'Select a date' }}</h3>
          <p v-if="!selectedKey" class="text-sm text-slate-500">Click any day in the calendar to see what's scheduled.</p>
          <div v-else-if="!selectedEvents.length" class="text-sm text-slate-400">No events on this day.</div>
          <ul v-else class="space-y-3 mt-2">
            <li v-for="e in selectedEvents" :key="e.id" class="flex gap-3">
              <span class="w-2 h-2 rounded-full mt-1.5 flex-shrink-0" :class="dotClass(e.event_type)" />
              <div class="min-w-0 flex-1">
                <div class="font-semibold text-sm text-slate-900">{{ e.title }}</div>
                <p v-if="e.description" class="text-xs text-slate-600 mt-0.5">{{ e.description }}</p>
                <div class="flex items-center gap-2 mt-1 text-[11px]">
                  <span v-if="e.event_type" class="px-2 py-0.5 rounded-full capitalize" :class="badgeClass(e.event_type)">{{ e.event_type }}</span>
                  <span v-if="e.is_recurring" class="text-slate-400">Recurring annually</span>
                </div>
              </div>
            </li>
          </ul>
        </div>

        <div class="card p-5">
          <h3 class="font-bold text-slate-900 mb-3">Up next</h3>
          <ul v-if="upcomingAcrossYear.length" class="space-y-3">
            <li v-for="(item, idx) in upcomingAcrossYear" :key="item.e.id + idx" class="flex gap-3">
              <div class="flex-shrink-0 w-12 text-center py-1.5 rounded-lg bg-sycamore-50 text-sycamore-700 border border-sycamore-100">
                <div class="text-[10px] font-semibold uppercase">{{ (parseLocalDate(item.date) || new Date()).toLocaleString('en-GB', { month: 'short' }) }}</div>
                <div class="text-base font-bold leading-none">{{ (parseLocalDate(item.date) || new Date()).getDate() }}</div>
              </div>
              <div class="min-w-0 flex-1">
                <div class="text-sm font-semibold text-slate-900 truncate">{{ item.e.title }}</div>
                <div class="text-[11px] text-slate-500 truncate capitalize">{{ item.e.event_type }}</div>
              </div>
            </li>
          </ul>
          <div v-else class="text-sm text-slate-400">No upcoming events.</div>
        </div>
      </aside>
    </div>
  </div>
</template>
