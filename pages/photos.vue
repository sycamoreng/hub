<script setup lang="ts">
definePageMeta({ title: 'Photo Wall' })

const supabase = useSupabase()
const { user, ready } = useAuth()
const { success, error: toastError } = useToast()

interface Photo {
  id: string
  author_id: string
  image_url: string
  caption: string
  event_name: string | null
  likes_count: number
  created_at: string
  author_name?: string
  liked?: boolean
}

const photos = ref<Photo[]>([])
const myLikes = ref<Set<string>>(new Set())
const loading = ref(true)
const showUpload = ref(false)
const form = ref({ caption: '', event_name: '' })
const selectedFile = ref<File | null>(null)
const previewUrl = ref('')
const submitting = ref(false)
const eventFilter = ref('')

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('photo_wall_posts')
    .select('*')
    .order('created_at', { ascending: false })

  if (data) {
    photos.value = data as Photo[]
    await loadNames()
  }

  if (user.value) {
    const { data: likes } = await supabase
      .from('photo_wall_likes')
      .select('photo_id')
      .eq('user_id', user.value.id)
    if (likes) myLikes.value = new Set(likes.map((l: any) => l.photo_id))
  }
  loading.value = false
}

async function loadNames() {
  const ids = [...new Set(photos.value.map(p => p.author_id))]
  if (ids.length === 0) return
  const { data: staff } = await supabase.from('staff_members').select('auth_user_id, full_name').in('auth_user_id', ids)
  const nameMap = new Map<string, string>()
  if (staff) staff.forEach((s: any) => nameMap.set(s.auth_user_id, s.full_name))
  photos.value = photos.value.map(p => ({ ...p, author_name: nameMap.get(p.author_id) ?? 'Unknown' }))
}

const events = computed(() => {
  const names = photos.value.map(p => p.event_name).filter(Boolean) as string[]
  return [...new Set(names)].sort()
})

const filtered = computed(() => {
  if (!eventFilter.value) return photos.value
  return photos.value.filter(p => p.event_name === eventFilter.value)
})

async function toggleLike(photo: Photo) {
  if (!user.value) return
  if (myLikes.value.has(photo.id)) {
    await supabase.from('photo_wall_likes').delete().eq('photo_id', photo.id).eq('user_id', user.value.id)
    myLikes.value.delete(photo.id)
    photo.likes_count--
  } else {
    await supabase.from('photo_wall_likes').insert({ photo_id: photo.id, user_id: user.value.id })
    myLikes.value.add(photo.id)
    photo.likes_count++
  }
}

function onFileSelected(e: Event) {
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return
  selectedFile.value = file
  previewUrl.value = URL.createObjectURL(file)
}

async function upload() {
  if (!selectedFile.value || !user.value) return
  submitting.value = true
  const ext = selectedFile.value.name.split('.').pop() ?? 'jpg'
  const path = `${user.value.id}/photos/${Date.now()}.${ext}`
  const { error: uploadErr } = await supabase.storage.from('uploads').upload(path, selectedFile.value)
  if (uploadErr) { toastError('Upload failed'); submitting.value = false; return }
  const { data: urlData } = supabase.storage.from('uploads').getPublicUrl(path)
  const imageUrl = urlData.publicUrl

  const { error } = await supabase.from('photo_wall_posts').insert({
    author_id: user.value.id,
    image_url: imageUrl,
    caption: form.value.caption.trim(),
    event_name: form.value.event_name.trim() || null
  })
  if (error) toastError('Failed to share photo')
  else {
    success('Photo shared!')
    form.value = { caption: '', event_name: '' }
    selectedFile.value = null
    previewUrl.value = ''
    showUpload.value = false
    await load()
  }
  submitting.value = false
}

async function deletePhoto(id: string) {
  const { error } = await supabase.from('photo_wall_posts').delete().eq('id', id)
  if (error) toastError('Failed to delete')
  else { success('Photo removed'); await load() }
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-6xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6 gap-3">
      <div>
        <h1 class="section-title">Photo Wall</h1>
        <p class="section-subtitle">Company memories and event galleries</p>
      </div>
      <button @click="showUpload = true" class="inline-flex items-center justify-center gap-1.5 px-3 sm:px-4 py-2 sm:py-2.5 rounded-lg bg-sycamore-600 text-white text-xs sm:text-sm font-medium hover:bg-sycamore-700 active:scale-[0.97] transition-all whitespace-nowrap">Share a Photo</button>
    </div>

    <div v-if="events.length" class="flex flex-wrap gap-2 mb-6">
      <button
        @click="eventFilter = ''"
        class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
        :class="!eventFilter ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >All</button>
      <button
        v-for="e in events"
        :key="e"
        @click="eventFilter = e"
        class="px-3 py-1.5 rounded-lg text-sm font-medium transition-colors"
        :class="eventFilter === e ? 'bg-sycamore-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'"
      >{{ e }}</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="filtered.length === 0" class="card p-8 text-center text-slate-400">
      No photos yet. Be the first to share a memory!
    </div>
    <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <div v-for="photo in filtered" :key="photo.id" class="card overflow-hidden card-hover">
        <div class="aspect-square bg-slate-100 relative">
          <img :src="photo.image_url" :alt="photo.caption" class="w-full h-full object-cover">
          <button
            v-if="photo.author_id === user?.id"
            @click.stop="deletePhoto(photo.id)"
            class="absolute top-2 right-2 w-7 h-7 rounded-full bg-black/50 text-white flex items-center justify-center hover:bg-black/70"
          >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z" clip-rule="evenodd" /></svg>
          </button>
        </div>
        <div class="p-3">
          <p v-if="photo.caption" class="text-sm text-slate-800 mb-1">{{ photo.caption }}</p>
          <div class="flex items-center justify-between text-xs text-slate-500">
            <div class="flex items-center gap-2">
              <span>{{ photo.author_name }}</span>
              <span v-if="photo.event_name" class="badge badge-blue text-[10px]">{{ photo.event_name }}</span>
            </div>
            <button
              @click="toggleLike(photo)"
              class="flex items-center gap-1 transition-colors"
              :class="myLikes.has(photo.id) ? 'text-red-500' : 'text-slate-400 hover:text-red-400'"
            >
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path d="M9.653 16.915l-.005-.003-.019-.01a20.759 20.759 0 0 1-1.162-.682 22.045 22.045 0 0 1-2.582-1.9C4.045 12.733 2 10.352 2 7.5a4.5 4.5 0 0 1 8-2.828A4.5 4.5 0 0 1 18 7.5c0 2.852-2.044 5.233-3.885 6.82a22.049 22.049 0 0 1-3.744 2.582l-.019.01-.005.003h-.002a.723.723 0 0 1-.692 0h-.002Z" />
              </svg>
              <span>{{ photo.likes_count }}</span>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Upload Modal -->
    <div v-if="showUpload" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showUpload = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-md p-6">
        <h2 class="text-lg font-bold text-slate-900 mb-4">Share a Photo</h2>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Photo</label>
            <div v-if="previewUrl" class="mb-2 rounded-lg overflow-hidden aspect-video bg-slate-100">
              <img :src="previewUrl" class="w-full h-full object-cover">
            </div>
            <input type="file" accept="image/*" @change="onFileSelected" class="block w-full text-sm text-slate-500 file:mr-3 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-sycamore-50 file:text-sycamore-700 hover:file:bg-sycamore-100">
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Caption</label>
            <input v-model="form.caption" class="input" placeholder="What's happening in this photo?" maxlength="300">
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Event Name (optional)</label>
            <input v-model="form.event_name" class="input" placeholder="e.g. Team Retreat 2026">
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showUpload = false" class="btn-secondary">Cancel</button>
          <button @click="upload" :disabled="!selectedFile || submitting" class="btn-primary">
            {{ submitting ? 'Uploading...' : 'Share' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
