<script setup lang="ts">
definePageMeta({ title: 'My ID Card' })

const supabase = useSupabase()
const { user, ready, profile } = useAuth()
const { success, error: toastError } = useToast()
const { loadConfig, loadMyPhoto, uploadImage, saveMyPhoto, deleteMyPhoto } = useIdCard()

import { DEFAULT_ID_CARD_CONFIG } from '~/composables/useIdCard'

const config = ref({ ...DEFAULT_ID_CARD_CONFIG })
const photoUrl = ref<string | null>(null)
const loading = ref(true)
const submitting = ref(false)
const previewUrl = ref<string | null>(null)
const selectedFile = ref<File | null>(null)
const cropperOpen = ref(false)
const originalSrc = ref<string | null>(null)

const staffMeta = ref<{ full_name: string | null; role: string | null; staff_id: string | null } | null>(null)

const cropAspect = computed(() => {
  const c = config.value
  const w = (c.photo_width || 1) * (c.card_width_px || 1)
  const h = (c.photo_height || 1) * (c.card_height_px || 1)
  return h > 0 ? w / h : 1
})

async function load() {
  loading.value = true
  const [c, mine] = await Promise.all([
    loadConfig(),
    user.value ? loadMyPhoto(user.value.id) : Promise.resolve(null)
  ])
  config.value = c
  photoUrl.value = mine?.photo_url ?? null

  if (user.value) {
    const { data } = await supabase
      .from('staff_members')
      .select('full_name, role, staff_id')
      .eq('auth_user_id', user.value.id)
      .maybeSingle()
    staffMeta.value = (data as any) ?? null
  }
  loading.value = false
}

function onFileSelected(e: Event) {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  if (!file.type.startsWith('image/')) {
    toastError('Please choose an image file')
    input.value = ''
    return
  }
  if (file.size > 8 * 1024 * 1024) {
    toastError('Image must be smaller than 8MB')
    input.value = ''
    return
  }
  if (originalSrc.value) URL.revokeObjectURL(originalSrc.value)
  originalSrc.value = URL.createObjectURL(file)
  cropperOpen.value = true
  input.value = ''
}

function reopenCrop() {
  if (originalSrc.value) cropperOpen.value = true
}

function onCropCancel() {
  cropperOpen.value = false
}

function onCropConfirm(blob: Blob) {
  cropperOpen.value = false
  selectedFile.value = new File([blob], 'id-card-photo.jpg', { type: 'image/jpeg' })
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
  previewUrl.value = URL.createObjectURL(blob)
}

async function submit() {
  if (!selectedFile.value || !user.value) return
  submitting.value = true
  try {
    const url = await uploadImage(user.value.id, 'id-card', selectedFile.value)
    await saveMyPhoto(user.value.id, url)
    photoUrl.value = url
    selectedFile.value = null
    if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
    previewUrl.value = null
    if (originalSrc.value) { URL.revokeObjectURL(originalSrc.value); originalSrc.value = null }
    success('Your ID card photo has been saved.')
  } catch (err: any) {
    toastError(err?.message || 'Failed to save your photo')
  } finally {
    submitting.value = false
  }
}

async function removePhoto() {
  if (!user.value) return
  if (!confirm('Remove your ID card photo?')) return
  submitting.value = true
  try {
    await deleteMyPhoto(user.value.id)
    photoUrl.value = null
    success('Photo removed.')
  } catch (err: any) {
    toastError(err?.message || 'Failed to remove photo')
  } finally {
    submitting.value = false
  }
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 py-8">
    <div class="mb-6">
      <h1 class="section-title">My ID Card</h1>
      <p class="section-subtitle">Upload a headshot to appear on your Sycamore ID card. Marketing will use this to print your card.</p>
    </div>

    <div v-if="loading" class="card p-10 text-center text-slate-400">Loading...</div>
    <div v-else class="grid grid-cols-1 lg:grid-cols-[auto_1fr] gap-8 items-start">
      <div class="flex flex-col items-center gap-6">
        <div class="flex flex-col sm:flex-row gap-6 items-start">
          <div>
            <p class="text-xs uppercase tracking-wide font-semibold text-slate-500 mb-2 text-center">Front</p>
            <IdCardPreview
              :config="config"
              side="front"
              :photo-url="photoUrl"
              :full-name="staffMeta?.full_name || profile?.name"
              :email="profile?.email"
              :staff-id="staffMeta?.staff_id"
              :scale="0.75"
            />
          </div>
          <div>
            <p class="text-xs uppercase tracking-wide font-semibold text-slate-500 mb-2 text-center">Back</p>
            <IdCardPreview :config="config" side="back" :scale="0.75" />
          </div>
        </div>
        <div v-if="!config.front_template_url && !config.back_template_url" class="text-xs text-slate-500 max-w-md text-center">
          Marketing hasn't uploaded the card templates yet. Your photo will still be saved and will appear here once the templates go live.
        </div>
      </div>

      <div class="card p-6 space-y-4">
        <div>
          <h2 class="text-lg font-bold text-slate-900">Your photo</h2>
          <p class="text-sm text-slate-500 mt-1">Use a clear headshot on a plain background. It should be square-ish so it fits the card slot.</p>
        </div>

        <div v-if="staffMeta" class="rounded-lg bg-slate-50 border border-slate-200 p-3 text-sm space-y-0.5">
          <div class="text-slate-500 text-xs uppercase tracking-wide font-semibold">On the card</div>
          <div class="text-slate-900 font-medium">{{ staffMeta.full_name || profile?.name }}</div>
          <div v-if="staffMeta.role" class="text-slate-600">{{ staffMeta.role }}</div>
          <div v-if="staffMeta.staff_id" class="text-slate-500 text-xs">Staff ID: {{ staffMeta.staff_id }}</div>
        </div>

        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1">Choose an image</label>
          <input
            type="file"
            accept="image/*"
            @change="onFileSelected"
            class="block w-full text-sm text-slate-500 file:mr-3 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-sycamore-50 file:text-sycamore-700 hover:file:bg-sycamore-100 cursor-pointer"
          >
          <p class="text-xs text-slate-400 mt-1">JPG, PNG, or WEBP up to 8MB.</p>
        </div>

        <div v-if="previewUrl" class="space-y-2">
          <div class="rounded-lg border border-slate-200 overflow-hidden bg-white mx-auto" :style="{ maxWidth: '224px' }">
            <div :style="{ aspectRatio: String(cropAspect) }">
              <img :src="previewUrl" class="w-full h-full object-cover" alt="Preview">
            </div>
          </div>
          <button
            @click="reopenCrop"
            type="button"
            class="text-xs font-medium text-sycamore-700 hover:text-sycamore-800 underline underline-offset-2"
          >
            Adjust crop
          </button>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            @click="submit"
            :disabled="!selectedFile || submitting"
            class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {{ submitting ? 'Saving...' : (photoUrl ? 'Replace photo' : 'Save photo') }}
          </button>
          <button
            v-if="photoUrl"
            @click="removePhoto"
            :disabled="submitting"
            class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-white border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50 disabled:opacity-50 transition-colors"
          >
            Remove photo
          </button>
        </div>

        <div v-if="photoUrl && !selectedFile" class="text-xs text-emerald-700 bg-emerald-50 border border-emerald-100 rounded-lg px-3 py-2">
          Your photo is saved. Marketing can see the finished card whenever they're ready to print.
        </div>
      </div>
    </div>

    <PhotoCropper
      :open="cropperOpen"
      :src="originalSrc"
      :aspect="cropAspect"
      @cancel="onCropCancel"
      @confirm="onCropConfirm"
    />
  </div>
</template>
