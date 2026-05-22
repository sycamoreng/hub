<script setup lang="ts">
definePageMeta({ layout: 'admin', title: 'Playlist Management' })

const supabase = useSupabase()
const { ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface PlaylistWeek {
  id: string
  week_start: string
  theme: string | null
  created_by: string | null
  is_staff_playlist: boolean
  created_at: string
  song_count?: number
}

interface Song {
  id: string
  title: string
  artist: string
  url: string | null
  submitted_by: string
  votes: number
  submitter_name?: string
}

const playlists = ref<PlaylistWeek[]>([])
const loading = ref(true)
const showForm = ref(false)
const editingId = ref<string | null>(null)
const form = ref({ week_start: '', theme: '' })
const expandedId = ref<string | null>(null)
const expandedSongs = ref<Song[]>([])
const loadingSongs = ref(false)
const confirmDelete = ref<string | null>(null)

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('playlist_weeks')
    .select('*, playlist_songs(count)')
    .order('week_start', { ascending: false })

  if (data) {
    playlists.value = data.map((p: any) => ({
      ...p,
      song_count: p.playlist_songs?.[0]?.count ?? 0
    }))
  }
  loading.value = false
}

async function save() {
  if (!form.value.week_start) return
  const payload = {
    week_start: form.value.week_start,
    theme: form.value.theme.trim() || null
  }

  if (editingId.value) {
    const { error } = await supabase.from('playlist_weeks').update(payload).eq('id', editingId.value)
    if (error) toastError('Failed to update playlist')
    else success('Playlist updated!')
  } else {
    const { error } = await supabase.from('playlist_weeks').insert(payload)
    if (error) {
      if (error.code === '23505') toastError('A playlist for that week already exists')
      else toastError('Failed to create playlist')
      return
    }
    success('Playlist created!')
  }
  form.value = { week_start: '', theme: '' }
  showForm.value = false
  editingId.value = null
  await load()
}

async function deletePlaylist(id: string) {
  const { error } = await supabase.from('playlist_weeks').delete().eq('id', id)
  if (error) toastError('Failed to delete playlist')
  else {
    success('Playlist deleted')
    confirmDelete.value = null
    if (expandedId.value === id) expandedId.value = null
    await load()
  }
}

async function toggleExpand(pl: PlaylistWeek) {
  if (expandedId.value === pl.id) {
    expandedId.value = null
    return
  }
  expandedId.value = pl.id
  loadingSongs.value = true
  const { data } = await supabase
    .from('playlist_songs')
    .select('*')
    .eq('playlist_id', pl.id)
    .order('votes', { ascending: false })
  if (data) {
    expandedSongs.value = data as Song[]
    const ids = [...new Set(data.map((s: any) => s.submitted_by))]
    if (ids.length) {
      const { data: staff } = await supabase.from('staff_members').select('auth_user_id, full_name').in('auth_user_id', ids)
      if (staff) {
        const nameMap = new Map(staff.map((s: any) => [s.auth_user_id, s.full_name]))
        expandedSongs.value = expandedSongs.value.map(s => ({ ...s, submitter_name: (nameMap.get(s.submitted_by) as string) ?? 'Unknown' }))
      }
    }
  }
  loadingSongs.value = false
}

async function deleteSong(songId: string) {
  const { error } = await supabase.from('playlist_songs').delete().eq('id', songId)
  if (error) toastError('Failed to delete song')
  else {
    expandedSongs.value = expandedSongs.value.filter(s => s.id !== songId)
    const pl = playlists.value.find(p => p.id === expandedId.value)
    if (pl && pl.song_count) pl.song_count--
    success('Song removed')
  }
}

function getMonday() {
  const d = new Date()
  const day = d.getDay()
  const diff = d.getDate() - day + (day === 0 ? -6 : 1)
  d.setDate(diff)
  return d.toISOString().split('T')[0]
}

function openCreate() {
  editingId.value = null
  form.value = { week_start: getMonday(), theme: '' }
  showForm.value = true
}

function openEdit(pl: PlaylistWeek) {
  editingId.value = pl.id
  form.value = { week_start: pl.week_start, theme: pl.theme ?? '' }
  showForm.value = true
}

watch(ready, (r) => { if (r && isAdmin.value) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-8">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="section-title">Playlist Management</h1>
        <p class="section-subtitle">Manage weekly playlists and staff submissions</p>
      </div>
      <button @click="openCreate" class="btn-primary">New Playlist Week</button>
    </div>

    <div v-if="loading" class="card p-8 text-center text-slate-400">Loading...</div>
    <div v-else-if="playlists.length === 0" class="card p-8 text-center text-slate-400">
      No playlists yet. Create one to get started!
    </div>
    <div v-else class="space-y-3">
      <div v-for="pl in playlists" :key="pl.id" class="card overflow-hidden">
        <div class="p-4 flex items-center justify-between">
          <button @click="toggleExpand(pl)" class="flex-1 text-left flex items-center gap-3">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4 text-slate-400 transition-transform" :class="{ 'rotate-90': expandedId === pl.id }">
              <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 .02-1.06L11.168 10 7.23 6.29a.75.75 0 1 1 1.04-1.08l4.5 4.25a.75.75 0 0 1 0 1.08l-4.5 4.25a.75.75 0 0 1-1.06-.02Z" clip-rule="evenodd" />
            </svg>
            <div>
              <div class="flex items-center gap-2">
                <h3 class="font-semibold text-slate-900">Week of {{ new Date(pl.week_start).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) }}</h3>
                <span v-if="pl.theme" class="badge badge-blue">{{ pl.theme }}</span>
                <span v-if="pl.is_staff_playlist" class="badge badge-green">Staff</span>
              </div>
              <div class="text-xs text-slate-500 mt-0.5">{{ pl.song_count }} songs submitted</div>
            </div>
          </button>
          <div class="flex items-center gap-1.5">
            <button @click="openEdit(pl)" class="p-2 rounded-lg text-slate-400 hover:text-sycamore-600 hover:bg-sycamore-50 transition-colors" title="Edit">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path d="m5.433 13.917 1.262-3.155A4 4 0 0 1 7.58 9.42l6.92-6.918a2.121 2.121 0 0 1 3 3l-6.92 6.918c-.383.383-.84.685-1.343.886l-3.154 1.262a.5.5 0 0 1-.65-.65Z" />
                <path d="M3.5 5.75c0-.69.56-1.25 1.25-1.25H10A.75.75 0 0 0 10 3H4.75A2.75 2.75 0 0 0 2 5.75v9.5A2.75 2.75 0 0 0 4.75 18h9.5A2.75 2.75 0 0 0 17 15.25V10a.75.75 0 0 0-1.5 0v5.25c0 .69-.56 1.25-1.25 1.25h-9.5c-.69 0-1.25-.56-1.25-1.25v-9.5Z" />
              </svg>
            </button>
            <button v-if="confirmDelete !== pl.id" @click="confirmDelete = pl.id" class="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 transition-colors" title="Delete">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                <path fill-rule="evenodd" d="M8.75 1A2.75 2.75 0 0 0 6 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 1 0 .23 1.482l.149-.022 1.005 11.07A2.75 2.75 0 0 0 7.763 19.5h4.474a2.75 2.75 0 0 0 2.744-2.469l1.005-11.07.149.022a.75.75 0 0 0 .23-1.482A41.03 41.03 0 0 0 14 4.193V3.75A2.75 2.75 0 0 0 11.25 1h-2.5ZM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4ZM8.58 7.72a.75.75 0 0 0-1.5.06l.3 7.5a.75.75 0 1 0 1.5-.06l-.3-7.5Zm4.34.06a.75.75 0 1 0-1.5-.06l-.3 7.5a.75.75 0 1 0 1.5.06l.3-7.5Z" clip-rule="evenodd" />
              </svg>
            </button>
            <div v-else class="flex items-center gap-1">
              <button @click="deletePlaylist(pl.id)" class="px-2 py-1 rounded text-xs font-medium bg-red-600 text-white hover:bg-red-700">Delete</button>
              <button @click="confirmDelete = null" class="px-2 py-1 rounded text-xs font-medium bg-slate-100 text-slate-600 hover:bg-slate-200">Cancel</button>
            </div>
          </div>
        </div>

        <!-- Expanded songs list -->
        <div v-if="expandedId === pl.id" class="border-t border-slate-100 bg-slate-50/50">
          <div v-if="loadingSongs" class="p-4 text-center text-sm text-slate-400">Loading songs...</div>
          <div v-else-if="expandedSongs.length === 0" class="p-4 text-center text-sm text-slate-400">No songs submitted yet</div>
          <div v-else class="divide-y divide-slate-100">
            <div v-for="song in expandedSongs" :key="song.id" class="px-4 py-2.5 flex items-center gap-3 group">
              <div class="flex-1 min-w-0">
                <span class="font-medium text-slate-800 text-sm">{{ song.title }}</span>
                <span class="text-slate-400 mx-1.5">-</span>
                <span class="text-sm text-slate-600">{{ song.artist }}</span>
                <span class="text-xs text-slate-400 ml-2">by {{ song.submitter_name }}</span>
              </div>
              <div class="flex items-center gap-2 shrink-0">
                <span class="text-xs font-medium text-slate-500">{{ song.votes }} votes</span>
                <button @click="deleteSong(song.id)" class="p-1.5 rounded text-slate-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Create/Edit Modal -->
    <div v-if="showForm" class="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" @click.self="showForm = false">
      <div class="bg-white rounded-xl shadow-xl w-full max-w-sm p-6">
        <h2 class="text-lg font-bold text-slate-900 mb-4">{{ editingId ? 'Edit Playlist' : 'New Playlist Week' }}</h2>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Week Start (Monday)</label>
            <input v-model="form.week_start" type="date" class="input">
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Theme (optional)</label>
            <input v-model="form.theme" class="input" placeholder="e.g. 90s Throwbacks, Feel-Good Fridays">
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-4">
          <button @click="showForm = false; editingId = null" class="btn-secondary">Cancel</button>
          <button @click="save" :disabled="!form.week_start" class="btn-primary">{{ editingId ? 'Save Changes' : 'Create' }}</button>
        </div>
      </div>
    </div>
  </div>
</template>
