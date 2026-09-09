<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const supabase = useSupabase()
const { user, canPerform } = useAuth()
const { success, error: toastError } = useToast()
const { loadConfig, saveConfig, uploadImage, loadPhotosForUsers, deleteMyPhoto } = useIdCard()

import { DEFAULT_ID_CARD_CONFIG } from '~/composables/useIdCard'

const config = ref({ ...DEFAULT_ID_CARD_CONFIG })
const loading = ref(true)
const savingConfig = ref(false)
const uploadingFront = ref(false)
const uploadingBack = ref(false)

interface StaffRow {
  auth_user_id: string
  full_name: string
  email: string | null
  role: string | null
  staff_id: string | null
  department_name?: string | null
}

const staff = ref<StaffRow[]>([])
const photos = ref<Map<string, string>>(new Map())
const search = ref('')
const filter = ref<'all' | 'with_photo' | 'missing'>('all')
const previewingUserId = ref<string | null>(null)

const canEdit = computed(() => canPerform('id-cards', 'update'))

async function load() {
  loading.value = true
  const [c, { data: staffData }] = await Promise.all([
    loadConfig(),
    supabase
      .from('staff_members')
      .select('auth_user_id, full_name, email, role, staff_id, departments!staff_members_department_id_fkey(name)')
      .not('auth_user_id', 'is', null)
      .eq('is_active', true)
      .order('full_name')
  ])
  config.value = c
  const rows: StaffRow[] = ((staffData as any[]) ?? []).map(r => ({
    auth_user_id: r.auth_user_id,
    full_name: r.full_name,
    email: r.email,
    role: r.role,
    staff_id: r.staff_id,
    department_name: r.departments?.name ?? null
  }))
  staff.value = rows
  photos.value = await loadPhotosForUsers(rows.map(r => r.auth_user_id))
  loading.value = false
}

async function onTemplateFile(side: 'front' | 'back', e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file || !user.value) return
  if (!file.type.startsWith('image/')) { toastError('Please choose an image file'); return }
  if (file.size > 10 * 1024 * 1024) { toastError('Image must be smaller than 10MB'); return }

  if (side === 'front') uploadingFront.value = true; else uploadingBack.value = true
  try {
    const url = await uploadImage(user.value.id, 'id-card-templates', file)
    const patch = side === 'front' ? { front_template_url: url } : { back_template_url: url }
    const updated = await saveConfig(patch)
    config.value = updated
    success(`${side === 'front' ? 'Front' : 'Back'} template updated.`)
  } catch (err: any) {
    toastError(err?.message || 'Failed to upload template')
  } finally {
    if (side === 'front') uploadingFront.value = false; else uploadingBack.value = false
    ;(e.target as HTMLInputElement).value = ''
  }
}

async function saveBox() {
  savingConfig.value = true
  try {
    const c = config.value
    const updated = await saveConfig({
      photo_x: clampPct(c.photo_x),
      photo_y: clampPct(c.photo_y),
      photo_width: clampPct(c.photo_width),
      photo_height: clampPct(c.photo_height),
      photo_shape: c.photo_shape,
      photo_fit: c.photo_fit,
      photo_position: c.photo_position,
      photo_anchor: c.photo_anchor,
      logo_show: !!c.logo_show,
      logo_x: clampPct(c.logo_x),
      logo_y: clampPct(c.logo_y),
      logo_width: clampPct(c.logo_width),
      card_width_px: Math.max(200, Math.min(1200, Math.round(c.card_width_px))),
      card_height_px: Math.max(200, Math.min(1600, Math.round(c.card_height_px))),
      text_x: clampPct(c.text_x),
      text_y: clampPct(c.text_y),
      text_width: clampPct(c.text_width),
      text_align: c.text_align,
      text_color: c.text_color,
      text_name_size: Math.max(6, Math.min(96, Number(c.text_name_size) || 0)),
      text_email_size: Math.max(6, Math.min(64, Number(c.text_email_size) || 0)),
      text_staff_id_size: Math.max(6, Math.min(64, Number(c.text_staff_id_size) || 0)),
      text_show_staff_id: !!c.text_show_staff_id
    })
    config.value = updated
    success('Placement saved.')
  } catch (err: any) {
    toastError(err?.message || 'Failed to save placement')
  } finally {
    savingConfig.value = false
  }
}

function clampPct(v: number) { return Math.max(0, Math.min(100, Number(v) || 0)) }

function restOnGreenLine() {
  config.value.photo_anchor = 'bottom'
}

async function clearStaffPhoto(userId: string, name: string) {
  if (!confirm(`Remove ${name}'s ID card photo?`)) return
  try {
    const { error } = await supabase.from('staff_id_card_photos').delete().eq('user_id', userId)
    if (error) throw error
    photos.value.delete(userId)
    photos.value = new Map(photos.value)
    success('Photo removed.')
  } catch (err: any) {
    toastError(err?.message || 'Failed to remove photo')
  }
}

const filtered = computed(() => {
  const q = search.value.trim().toLowerCase()
  return staff.value.filter(s => {
    if (q && !(`${s.full_name} ${s.role ?? ''} ${s.staff_id ?? ''}`.toLowerCase().includes(q))) return false
    const has = photos.value.has(s.auth_user_id)
    if (filter.value === 'with_photo' && !has) return false
    if (filter.value === 'missing' && has) return false
    return true
  })
})

const stats = computed(() => {
  const total = staff.value.length
  const withPhoto = staff.value.filter(s => photos.value.has(s.auth_user_id)).length
  return { total, withPhoto, missing: total - withPhoto }
})

const previewStaff = computed(() => staff.value.find(s => s.auth_user_id === previewingUserId.value) ?? null)
const previewPhoto = computed(() => previewingUserId.value ? photos.value.get(previewingUserId.value) ?? null : null)

onMounted(load)
</script>

<template>
  <div class="max-w-6xl space-y-8">
    <div>
      <h1 class="text-xl font-bold text-slate-900">ID Cards</h1>
      <p class="text-sm text-slate-500">Upload the front and back card templates and see each staff member's finished card ready to print.</p>
    </div>

    <div v-if="loading" class="card p-10 text-center text-slate-400">Loading...</div>

    <template v-else>
      <!-- Templates + placement -->
      <section class="card p-6 space-y-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-base font-bold text-slate-900">Card templates</h2>
            <p class="text-xs text-slate-500 mt-0.5">Upload the front and back designs. Then position where the staff photo appears on the front.</p>
          </div>
          <div v-if="!canEdit" class="text-xs text-amber-700 bg-amber-50 border border-amber-100 rounded-lg px-3 py-1.5">Read-only</div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-[auto_auto_1fr] gap-6 items-start">
          <div class="flex flex-col items-center gap-2">
            <p class="text-xs uppercase tracking-wide font-semibold text-slate-500">Front</p>
            <IdCardPreview
              :config="config"
              side="front"
              full-name="Sample Staff Name"
              email="sample.staff@sycamore.ng"
              staff-id="SISL-2026-001"
              :scale="0.55"
            />
            <label v-if="canEdit" class="text-xs text-sycamore-700 hover:text-sycamore-800 cursor-pointer font-medium">
              {{ uploadingFront ? 'Uploading...' : (config.front_template_url ? 'Replace front' : 'Upload front') }}
              <input type="file" accept="image/*" class="hidden" @change="onTemplateFile('front', $event)" :disabled="uploadingFront">
            </label>
          </div>

          <div class="flex flex-col items-center gap-2">
            <p class="text-xs uppercase tracking-wide font-semibold text-slate-500">Back</p>
            <IdCardPreview :config="config" side="back" :scale="0.55" />
            <label v-if="canEdit" class="text-xs text-sycamore-700 hover:text-sycamore-800 cursor-pointer font-medium">
              {{ uploadingBack ? 'Uploading...' : (config.back_template_url ? 'Replace back' : 'Upload back') }}
              <input type="file" accept="image/*" class="hidden" @change="onTemplateFile('back', $event)" :disabled="uploadingBack">
            </label>
          </div>

          <div class="space-y-3">
            <p class="text-xs uppercase tracking-wide font-semibold text-slate-500">Photo placement (percent of card)</p>
            <div class="grid grid-cols-2 gap-3">
              <label class="text-xs text-slate-600">
                Left
                <input v-model.number="config.photo_x" type="number" min="0" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
              </label>
              <label class="text-xs text-slate-600">
                {{ config.photo_anchor === 'bottom' ? 'Bottom edge' : 'Top edge' }}
                <input v-model.number="config.photo_y" type="number" min="0" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
              </label>
              <label class="text-xs text-slate-600">
                Width
                <input v-model.number="config.photo_width" type="number" min="1" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
              </label>
              <label class="text-xs text-slate-600">
                Height
                <input v-model.number="config.photo_height" type="number" min="1" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
              </label>
              <label class="text-xs text-slate-600">
                Shape
                <select v-model="config.photo_shape" :disabled="!canEdit" class="input mt-1">
                  <option value="rectangle">Rectangle</option>
                  <option value="circle">Circle</option>
                </select>
              </label>
              <label class="text-xs text-slate-600">
                Photo fit
                <select v-model="config.photo_fit" :disabled="!canEdit" class="input mt-1">
                  <option value="cover">Fill slot (crop to fit)</option>
                  <option value="contain">Show whole photo</option>
                </select>
              </label>
              <label class="text-xs text-slate-600">
                Photo position
                <select v-model="config.photo_position" :disabled="!canEdit" class="input mt-1">
                  <option value="top">Top</option>
                  <option value="center">Center</option>
                  <option value="bottom">Bottom</option>
                </select>
              </label>
              <label class="text-xs text-slate-600">
                Anchor from
                <select v-model="config.photo_anchor" :disabled="!canEdit" class="input mt-1">
                  <option value="top">Top edge</option>
                  <option value="bottom">Bottom edge</option>
                </select>
              </label>
              <label class="text-xs text-slate-600">
                Card width (px)
                <input v-model.number="config.card_width_px" type="number" min="200" max="1200" step="10" :disabled="!canEdit" class="input mt-1">
              </label>
              <label class="text-xs text-slate-600">
                Card height (px)
                <input v-model.number="config.card_height_px" type="number" min="200" max="1600" step="10" :disabled="!canEdit" class="input mt-1">
              </label>
            </div>
            <p class="text-xs text-slate-500 leading-relaxed">
              To make the photo sit right at the base of the white area, just above the green banner: set
              <span class="font-medium text-slate-700">Anchor from</span> to <span class="font-medium text-slate-700">Bottom edge</span>,
              then set the <span class="font-medium text-slate-700">Bottom edge</span> value to the green line's position (percent from the top).
              The photo then rests on that line whatever its height. Use the button below to snap it there and fine-tune.
            </p>
            <button
              v-if="canEdit"
              @click="restOnGreenLine"
              type="button"
              class="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-white border border-sycamore-200 text-sycamore-700 text-sm font-medium hover:bg-sycamore-50 transition-colors"
            >
              Rest photo on the green line
            </button>
            <button
              v-if="canEdit"
              @click="saveBox"
              :disabled="savingConfig"
              class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50 transition-colors"
            >
              {{ savingConfig ? 'Saving...' : 'Save placement' }}
            </button>

            <div class="pt-4 border-t border-slate-100 space-y-3">
              <div class="flex items-center justify-between">
                <p class="text-xs uppercase tracking-wide font-semibold text-slate-500">Company logo</p>
                <label class="inline-flex items-center gap-2 text-xs text-slate-600">
                  <input v-model="config.logo_show" type="checkbox" :disabled="!canEdit" class="rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500">
                  Show logo
                </label>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <label class="text-xs text-slate-600">
                  Left
                  <input v-model.number="config.logo_x" type="number" min="0" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Top
                  <input v-model.number="config.logo_y" type="number" min="0" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Width
                  <input v-model.number="config.logo_width" type="number" min="1" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <div />
              </div>
              <button
                v-if="canEdit"
                @click="saveBox"
                :disabled="savingConfig"
                class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50 transition-colors"
              >
                {{ savingConfig ? 'Saving...' : 'Save logo' }}
              </button>
            </div>

            <div class="pt-4 border-t border-slate-100 space-y-3">
              <p class="text-xs uppercase tracking-wide font-semibold text-slate-500">Name / email / staff ID text</p>
              <p class="text-xs text-slate-500 -mt-1">Position the text block that overlays the staff member's name, email, and staff ID on the front of the card.</p>
              <div class="grid grid-cols-2 gap-3">
                <label class="text-xs text-slate-600">
                  Text left (%)
                  <input v-model.number="config.text_x" type="number" min="0" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Text top (%)
                  <input v-model.number="config.text_y" type="number" min="0" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Text width (%)
                  <input v-model.number="config.text_width" type="number" min="1" max="100" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Align
                  <select v-model="config.text_align" :disabled="!canEdit" class="input mt-1">
                    <option value="left">Left</option>
                    <option value="center">Center</option>
                    <option value="right">Right</option>
                  </select>
                </label>
                <label class="text-xs text-slate-600">
                  Text color
                  <input v-model="config.text_color" type="color" :disabled="!canEdit" class="mt-1 h-9 w-full rounded-lg border border-slate-200 bg-white px-1 cursor-pointer">
                </label>
                <label class="text-xs text-slate-600 flex items-end gap-2 pb-1">
                  <input v-model="config.text_show_staff_id" type="checkbox" :disabled="!canEdit" class="w-4 h-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500">
                  Show staff ID line
                </label>
                <label class="text-xs text-slate-600">
                  Name size (px)
                  <input v-model.number="config.text_name_size" type="number" min="6" max="96" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Email size (px)
                  <input v-model.number="config.text_email_size" type="number" min="6" max="64" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
                <label class="text-xs text-slate-600">
                  Staff ID size (px)
                  <input v-model.number="config.text_staff_id_size" type="number" min="6" max="64" step="0.5" :disabled="!canEdit" class="input mt-1">
                </label>
              </div>
            </div>
          </div>
        </div>
      </section>

      <!-- Staff list -->
      <section class="card p-6 space-y-4">
        <div class="flex items-start justify-between gap-4 flex-wrap">
          <div>
            <h2 class="text-base font-bold text-slate-900">Staff ID cards</h2>
            <p class="text-xs text-slate-500 mt-0.5">Click any staff member to see the full front + back of their card.</p>
          </div>
          <div class="flex items-center gap-3 text-xs text-slate-600">
            <span><span class="font-bold text-slate-900">{{ stats.withPhoto }}</span> uploaded</span>
            <span class="text-slate-300">·</span>
            <span><span class="font-bold text-slate-900">{{ stats.missing }}</span> missing</span>
            <span class="text-slate-300">·</span>
            <span><span class="font-bold text-slate-900">{{ stats.total }}</span> total</span>
          </div>
        </div>

        <div class="flex flex-wrap gap-2">
          <input v-model="search" placeholder="Search name, role, staff ID..." class="input flex-1 min-w-[200px]">
          <div class="flex rounded-lg overflow-hidden border border-slate-200">
            <button
              v-for="opt in [{ v: 'all', l: 'All' }, { v: 'with_photo', l: 'Uploaded' }, { v: 'missing', l: 'Missing' }]"
              :key="opt.v"
              @click="filter = opt.v as any"
              class="px-3 py-1.5 text-xs font-medium transition-colors"
              :class="filter === opt.v ? 'bg-sycamore-600 text-white' : 'bg-white text-slate-600 hover:bg-slate-50'"
            >{{ opt.l }}</button>
          </div>
        </div>

        <div v-if="filtered.length === 0" class="text-center text-slate-400 py-10 text-sm">No staff match this filter.</div>
        <div v-else class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
          <button
            v-for="s in filtered"
            :key="s.auth_user_id"
            @click="previewingUserId = s.auth_user_id"
            class="group text-left card-hover card p-3 flex flex-col items-center gap-2"
          >
            <IdCardPreview
              :config="config"
              side="front"
              :photo-url="photos.get(s.auth_user_id) ?? null"
              :full-name="s.full_name"
              :email="s.email"
              :staff-id="s.staff_id"
              :scale="0.32"
            />
            <div class="w-full text-center">
              <div class="text-sm font-medium text-slate-900 truncate">{{ s.full_name }}</div>
              <div class="text-xs text-slate-500 truncate">{{ s.role || s.department_name || '—' }}</div>
              <div class="text-[10px] mt-1 inline-flex items-center gap-1">
                <span
                  class="w-1.5 h-1.5 rounded-full"
                  :class="photos.has(s.auth_user_id) ? 'bg-emerald-500' : 'bg-amber-400'"
                />
                <span :class="photos.has(s.auth_user_id) ? 'text-emerald-700' : 'text-amber-700'">
                  {{ photos.has(s.auth_user_id) ? 'Photo ready' : 'No photo yet' }}
                </span>
              </div>
            </div>
          </button>
        </div>
      </section>
    </template>

    <!-- Full preview modal -->
    <div
      v-if="previewingUserId && previewStaff"
      class="fixed inset-0 bg-slate-900/60 flex items-center justify-center z-50 p-4"
      @click.self="previewingUserId = null"
    >
      <div class="bg-white rounded-2xl shadow-2xl max-w-4xl w-full p-6 space-y-5">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h3 class="text-lg font-bold text-slate-900">{{ previewStaff.full_name }}</h3>
            <p class="text-sm text-slate-500">
              {{ previewStaff.role || '—' }}<template v-if="previewStaff.staff_id"> · Staff ID {{ previewStaff.staff_id }}</template>
            </p>
          </div>
          <button @click="previewingUserId = null" class="p-2 rounded-lg hover:bg-slate-100 text-slate-500">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z" clip-rule="evenodd" /></svg>
          </button>
        </div>

        <div class="flex flex-wrap gap-6 justify-center">
          <div class="flex flex-col items-center gap-1">
            <span class="text-xs uppercase tracking-wide font-semibold text-slate-500">Front</span>
            <IdCardPreview
              :config="config"
              side="front"
              :photo-url="previewPhoto"
              :full-name="previewStaff.full_name"
              :email="previewStaff.email"
              :staff-id="previewStaff.staff_id"
              :scale="0.85"
            />
          </div>
          <div class="flex flex-col items-center gap-1">
            <span class="text-xs uppercase tracking-wide font-semibold text-slate-500">Back</span>
            <IdCardPreview :config="config" side="back" :scale="0.85" />
          </div>
        </div>

        <div class="flex items-center justify-between gap-3 pt-3 border-t border-slate-100">
          <div class="text-xs text-slate-500">
            <template v-if="previewPhoto">
              Photo uploaded by staff member.
            </template>
            <template v-else>
              This staff member hasn't uploaded a photo yet.
            </template>
          </div>
          <div class="flex gap-2">
            <a
              v-if="previewPhoto"
              :href="previewPhoto"
              target="_blank"
              rel="noopener"
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white border border-slate-200 text-slate-700 text-xs font-medium hover:bg-slate-50"
            >Open photo</a>
            <button
              v-if="previewPhoto && canEdit"
              @click="clearStaffPhoto(previewStaff.auth_user_id, previewStaff.full_name)"
              class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-50 border border-red-100 text-red-700 text-xs font-medium hover:bg-red-100"
            >Remove photo</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
