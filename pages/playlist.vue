<script setup lang="ts">
definePageMeta({ title: 'Playlist of the Week' })

const supabase = useSupabase()
const { user, ready, isAdmin } = useAuth()
const { success, error: toastError } = useToast()

interface PlaylistWeek {
  id: string
  week_start: string
  theme: string | null
  created_by: string | null
  is_staff_playlist: boolean
  created_at: string
}

interface Song {
  id: string
  playlist_id: string
  submitted_by: string
  title: string
  artist: string
  url: string | null
  votes: number
  created_at: string
  submitter_name?: string
}

const tab = ref<'weekly' | 'my'>('weekly')
const playlists = ref<PlaylistWeek[]>([])
const myPlaylists = ref<PlaylistWeek[]>([])
const currentPlaylist = ref<PlaylistWeek | null>(null)
const songs = ref<Song[]>([])
const myVotes = ref<Set<string>>(new Set())
const loading = ref(true)
const showAddSong = ref(false)
const songForm = ref({ title: '', artist: '', url: '' })
const submitting = ref(false)
const animatingVote = ref<string | null>(null)
const showCreatePlaylist = ref(false)
const playlistForm = ref({ theme: '' })
const editingPlaylistId = ref<string | null>(null)
const confirmDeletePlaylist = ref<string | null>(null)

const moodGradients: Record<string, string> = {
  'chill': 'from-sky-400 via-blue-500 to-sky-700',
  'energy': 'from-orange-400 via-red-500 to-rose-600',
  'throwback': 'from-amber-400 via-orange-500 to-red-500',
  'feel-good': 'from-emerald-400 via-teal-500 to-cyan-600',
  'focus': 'from-slate-600 via-slate-700 to-slate-900',
  'party': 'from-rose-400 via-pink-500 to-rose-600',
  'default': 'from-sycamore-500 via-sycamore-600 to-leaf-700'
}

function getMoodGradient(theme: string | null) {
  if (!theme) return moodGradients.default
  const lower = theme.toLowerCase()
  for (const [key, val] of Object.entries(moodGradients)) {
    if (lower.includes(key)) return val
  }
  return moodGradients.default
}

function getMoodEmoji(theme: string | null) {
  if (!theme) return '🎵'
  const lower = theme.toLowerCase()
  if (lower.includes('chill') || lower.includes('relax')) return '🌊'
  if (lower.includes('energy') || lower.includes('pump') || lower.includes('workout')) return '⚡'
  if (lower.includes('throwback') || lower.includes('90') || lower.includes('80') || lower.includes('retro')) return '📼'
  if (lower.includes('feel') || lower.includes('happy') || lower.includes('good')) return '☀️'
  if (lower.includes('focus') || lower.includes('work') || lower.includes('deep')) return '🧠'
  if (lower.includes('party') || lower.includes('friday') || lower.includes('weekend')) return '🎉'
  if (lower.includes('love') || lower.includes('romance')) return '💕'
  if (lower.includes('afro') || lower.includes('african')) return '🥁'
  return '🎵'
}

function detectPlatform(url: string | null): 'spotify' | 'youtube' | 'apple' | 'other' | null {
  if (!url) return null
  const lower = url.toLowerCase()
  if (lower.includes('spotify')) return 'spotify'
  if (lower.includes('youtube') || lower.includes('youtu.be')) return 'youtube'
  if (lower.includes('apple') || lower.includes('music.apple')) return 'apple'
  return 'other'
}

function platformIcon(platform: string) {
  switch (platform) {
    case 'spotify': return { bg: 'bg-[#1DB954]', label: 'Spotify' }
    case 'youtube': return { bg: 'bg-[#FF0000]', label: 'YouTube' }
    case 'apple': return { bg: 'bg-[#FA243C]', label: 'Apple Music' }
    default: return { bg: 'bg-slate-500', label: 'Listen' }
  }
}

async function load() {
  loading.value = true
  const { data: plData } = await supabase
    .from('playlist_weeks')
    .select('*')
    .eq('is_staff_playlist', false)
    .order('week_start', { ascending: false })
    .limit(10)

  if (plData && plData.length) {
    playlists.value = plData as PlaylistWeek[]
    currentPlaylist.value = plData[0] as PlaylistWeek
    await loadSongs(currentPlaylist.value.id)
  }

  if (user.value) {
    await loadMyPlaylists()
  }
  loading.value = false
}

async function loadMyPlaylists() {
  const { data } = await supabase
    .from('playlist_weeks')
    .select('*')
    .eq('is_staff_playlist', true)
    .order('created_at', { ascending: false })

  if (data) myPlaylists.value = data as PlaylistWeek[]
}

async function loadSongs(playlistId: string) {
  const { data } = await supabase
    .from('playlist_songs')
    .select('*')
    .eq('playlist_id', playlistId)
    .order('votes', { ascending: false })

  if (data) {
    songs.value = data as Song[]
    await loadSubmitterNames()
  }

  if (user.value) {
    const songIds = songs.value.map(s => s.id)
    if (songIds.length) {
      const { data: votes } = await supabase
        .from('playlist_votes')
        .select('song_id')
        .eq('user_id', user.value.id)
        .in('song_id', songIds)
      if (votes) myVotes.value = new Set(votes.map((v: any) => v.song_id))
    } else {
      myVotes.value = new Set()
    }
  }
}

async function loadSubmitterNames() {
  const ids = [...new Set(songs.value.map(s => s.submitted_by))]
  if (ids.length === 0) return
  const { data: staff } = await supabase.from('staff_members').select('auth_user_id, full_name').in('auth_user_id', ids)
  const nameMap = new Map<string, string>()
  if (staff) staff.forEach((s: any) => nameMap.set(s.auth_user_id, s.full_name))
  songs.value = songs.value.map(s => ({ ...s, submitter_name: nameMap.get(s.submitted_by) ?? 'Unknown' }))
}

async function selectPlaylist(pl: PlaylistWeek) {
  currentPlaylist.value = pl
  await loadSongs(pl.id)
}

async function toggleVote(song: Song) {
  if (!user.value) return
  animatingVote.value = song.id
  if (myVotes.value.has(song.id)) {
    await supabase.from('playlist_votes').delete().eq('song_id', song.id).eq('user_id', user.value.id)
    myVotes.value.delete(song.id)
    song.votes--
  } else {
    await supabase.from('playlist_votes').insert({ song_id: song.id, user_id: user.value.id })
    myVotes.value.add(song.id)
    song.votes++
  }
  setTimeout(() => { animatingVote.value = null }, 400)
}

async function addSong() {
  if (!songForm.value.title.trim() || !songForm.value.artist.trim() || !user.value || !currentPlaylist.value) return
  submitting.value = true
  const { error } = await supabase.from('playlist_songs').insert({
    playlist_id: currentPlaylist.value.id,
    submitted_by: user.value.id,
    title: songForm.value.title.trim(),
    artist: songForm.value.artist.trim(),
    url: songForm.value.url.trim() || null
  })
  if (error) toastError('Failed to add song')
  else {
    success('Song added to the playlist!')
    songForm.value = { title: '', artist: '', url: '' }
    showAddSong.value = false
    await loadSongs(currentPlaylist.value.id)
  }
  submitting.value = false
}

async function deleteSong(id: string) {
  const { error } = await supabase.from('playlist_songs').delete().eq('id', id)
  if (error) toastError('Failed to remove song')
  else { success('Song removed'); if (currentPlaylist.value) await loadSongs(currentPlaylist.value.id) }
}

async function createMyPlaylist() {
  if (!user.value || !playlistForm.value.theme.trim()) return
  submitting.value = true
  const today = new Date()
  const day = today.getDay()
  const diff = today.getDate() - day + (day === 0 ? -6 : 1)
  const monday = new Date(today)
  monday.setDate(diff)

  const { error } = await supabase.from('playlist_weeks').insert({
    week_start: monday.toISOString().split('T')[0],
    theme: playlistForm.value.theme.trim(),
    created_by: user.value.id,
    is_staff_playlist: true
  })
  if (error) toastError('Failed to create playlist')
  else {
    success('Playlist created!')
    playlistForm.value = { theme: '' }
    showCreatePlaylist.value = false
    await loadMyPlaylists()
  }
  submitting.value = false
}

async function editMyPlaylist() {
  if (!editingPlaylistId.value || !playlistForm.value.theme.trim()) return
  const { error } = await supabase.from('playlist_weeks').update({
    theme: playlistForm.value.theme.trim()
  }).eq('id', editingPlaylistId.value)
  if (error) toastError('Failed to update playlist')
  else {
    success('Playlist updated!')
    playlistForm.value = { theme: '' }
    editingPlaylistId.value = null
    showCreatePlaylist.value = false
    await loadMyPlaylists()
  }
}

async function deleteMyPlaylist(id: string) {
  const { error } = await supabase.from('playlist_weeks').delete().eq('id', id)
  if (error) toastError('Failed to delete playlist')
  else {
    success('Playlist deleted')
    confirmDeletePlaylist.value = null
    if (currentPlaylist.value?.id === id) {
      currentPlaylist.value = null
      songs.value = []
    }
    await loadMyPlaylists()
  }
}

function openEditPlaylist(pl: PlaylistWeek) {
  editingPlaylistId.value = pl.id
  playlistForm.value = { theme: pl.theme ?? '' }
  showCreatePlaylist.value = true
}

function formatWeek(date: string) {
  return new Date(date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })
}

function openInSpotifySearch(song: Song) {
  const q = encodeURIComponent(`${song.title} ${song.artist}`)
  window.open(`https://open.spotify.com/search/${q}`, '_blank')
}

function openInYouTubeSearch(song: Song) {
  const q = encodeURIComponent(`${song.title} ${song.artist}`)
  window.open(`https://www.youtube.com/results?search_query=${q}`, '_blank')
}

watch(ready, (r) => { if (r) load() }, { immediate: true })
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-8">
    <!-- Tab switcher -->
    <div class="flex gap-1 p-1 bg-slate-100 rounded-xl mb-6 max-w-xs">
      <button
        @click="tab = 'weekly'"
        class="flex-1 px-4 py-2 rounded-lg text-sm font-medium transition-all"
        :class="tab === 'weekly' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
      >Weekly</button>
      <button
        @click="tab = 'my'"
        class="flex-1 px-4 py-2 rounded-lg text-sm font-medium transition-all"
        :class="tab === 'my' ? 'bg-white text-slate-900 shadow-sm' : 'text-slate-500 hover:text-slate-700'"
      >My Playlists</button>
    </div>

    <!-- WEEKLY TAB -->
    <template v-if="tab === 'weekly'">
      <div v-if="loading" class="card p-12 text-center text-slate-400">Loading playlist...</div>

      <div v-else-if="!currentPlaylist" class="card p-12 text-center">
        <div class="text-6xl mb-4">🎵</div>
        <h2 class="text-xl font-bold text-slate-900">No playlist this week</h2>
        <p class="text-slate-500 mt-2">Check back soon for this week's staff-curated picks!</p>
      </div>

      <template v-else>
        <!-- Hero Banner with mood gradient -->
        <div class="relative overflow-hidden rounded-2xl mb-8" :class="`bg-gradient-to-br ${getMoodGradient(currentPlaylist.theme)}`">
          <div class="absolute inset-0 opacity-20">
            <div class="absolute -top-10 -right-10 w-60 h-60 rounded-full bg-white/20 blur-3xl"></div>
            <div class="absolute -bottom-10 -left-10 w-48 h-48 rounded-full bg-black/10 blur-2xl"></div>
            <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 rounded-full bg-white/5 blur-3xl"></div>
          </div>
          <div class="relative p-5 sm:p-10 text-white">
            <div class="flex items-start justify-between gap-3 sm:gap-4">
              <div>
                <div class="flex items-center gap-2 mb-2 sm:mb-3">
                  <span class="text-2xl sm:text-3xl">{{ getMoodEmoji(currentPlaylist.theme) }}</span>
                  <span class="text-[10px] sm:text-xs uppercase tracking-[0.2em] font-bold text-white/70">Playlist of the Week</span>
                </div>
                <h1 class="text-2xl sm:text-4xl font-bold leading-tight">
                  {{ currentPlaylist.theme || 'Staff Picks' }}
                </h1>
                <p class="mt-2 text-white/70 text-xs sm:text-sm">Week of {{ formatWeek(currentPlaylist.week_start) }} -- {{ songs.length }} songs submitted</p>
              </div>
              <button @click="showAddSong = true" class="shrink-0 inline-flex items-center gap-1.5 sm:gap-2 px-3 sm:px-5 py-2 sm:py-2.5 rounded-full bg-white/20 ring-1 ring-white/30 backdrop-blur text-white font-semibold text-xs sm:text-sm hover:bg-white/30 transition-colors">
                + Add Song
              </button>
            </div>

            <div class="flex flex-wrap gap-2 mt-5">
              <button
                v-for="pl in playlists.slice(0, 5)"
                :key="pl.id"
                @click="selectPlaylist(pl)"
                class="px-3 py-1.5 rounded-full text-xs font-medium transition-all"
                :class="currentPlaylist.id === pl.id ? 'bg-white text-slate-900' : 'bg-white/15 text-white/90 hover:bg-white/25'"
              >{{ formatWeek(pl.week_start) }}</button>
            </div>
          </div>
        </div>

        <!-- Songs list -->
        <div v-if="songs.length === 0" class="card p-10 text-center">
          <div class="text-5xl mb-3">🎶</div>
          <h3 class="text-lg font-bold text-slate-900">This playlist is empty</h3>
          <p class="text-slate-500 mt-1">Be the first to add a track!</p>
          <button @click="showAddSong = true" class="btn-primary mt-4">Add a Song</button>
        </div>
        <div v-else class="space-y-2">
          <div
            v-for="(song, i) in songs"
            :key="song.id"
            class="group relative card px-4 py-3 flex items-center gap-4 hover:shadow-md transition-all"
            :class="{ 'ring-2 ring-sycamore-200': animatingVote === song.id }"
          >
            <div class="w-8 h-8 rounded-full flex items-center justify-center text-sm font-bold shrink-0"
              :class="i === 0 ? 'bg-gradient-to-br from-amber-300 to-amber-500 text-white shadow-sm' : i === 1 ? 'bg-gradient-to-br from-slate-300 to-slate-400 text-white' : i === 2 ? 'bg-gradient-to-br from-orange-300 to-orange-500 text-white' : 'bg-slate-100 text-slate-500'"
            >{{ i + 1 }}</div>

            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-slate-900 truncate text-sm">{{ song.title }}</span>
              </div>
              <div class="flex items-center gap-2 text-[11px] sm:text-xs text-slate-500 mt-0.5">
                <span class="truncate">{{ song.artist }}</span>
                <span class="text-slate-300">|</span>
                <span class="truncate">{{ song.submitter_name }}</span>
              </div>
            </div>

            <div class="hidden sm:flex items-center gap-1.5">
              <template v-if="song.url && detectPlatform(song.url)">
                <a :href="song.url" target="_blank" rel="noopener" class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-semibold text-white transition-transform hover:scale-105" :class="platformIcon(detectPlatform(song.url)!).bg">
                  {{ platformIcon(detectPlatform(song.url)!).label }}
                </a>
              </template>
              <template v-else>
                <button @click="openInSpotifySearch(song)" class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-[11px] font-medium bg-[#1DB954]/10 text-[#1DB954] hover:bg-[#1DB954]/20 transition-colors">
                  Spotify
                </button>
                <button @click="openInYouTubeSearch(song)" class="inline-flex items-center gap-1 px-2 py-1 rounded-full text-[11px] font-medium bg-red-50 text-red-600 hover:bg-red-100 transition-colors">
                  YouTube
                </button>
              </template>
            </div>

            <div class="flex items-center gap-2 shrink-0">
              <button
                v-if="song.submitted_by === user?.id"
                @click.stop="deleteSong(song.id)"
                class="text-slate-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4"><path fill-rule="evenodd" d="M4.293 4.293a1 1 0 0 1 1.414 0L10 8.586l4.293-4.293a1 1 0 1 1 1.414 1.414L11.414 10l4.293 4.293a1 1 0 0 1-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 0 1-1.414-1.414L8.586 10 4.293 5.707a1 1 0 0 1 0-1.414Z" clip-rule="evenodd" /></svg>
              </button>
              <button
                @click="toggleVote(song)"
                class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-sm font-semibold transition-all"
                :class="myVotes.has(song.id) ? 'bg-sycamore-100 text-sycamore-700 ring-1 ring-sycamore-200 scale-105' : 'bg-slate-100 text-slate-500 hover:bg-slate-200'"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4" :class="{ 'animate-bounce': animatingVote === song.id }">
                  <path fill-rule="evenodd" d="M10 15a.75.75 0 0 1-.75-.75V7.612L7.29 9.77a.75.75 0 0 1-1.08-1.04l3.25-3.5a.75.75 0 0 1 1.08 0l3.25 3.5a.75.75 0 1 1-1.08 1.04l-1.96-2.158v6.638A.75.75 0 0 1 10 15Z" clip-rule="evenodd" />
                </svg>
                {{ song.votes }}
              </button>
            </div>
          </div>
        </div>
      </template>
    </template>

    <!-- MY PLAYLISTS TAB -->
    <template v-if="tab === 'my'">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h2 class="text-xl font-bold text-slate-900">My Playlists</h2>
          <p class="text-sm text-slate-500 mt-0.5">Create and share your own playlists with the team</p>
        </div>
        <button @click="editingPlaylistId = null; playlistForm = { theme: '' }; showCreatePlaylist = true" class="btn-primary">New Playlist</button>
      </div>

      <div v-if="myPlaylists.length === 0" class="card p-10 text-center">
        <div class="text-5xl mb-3">🎧</div>
        <h3 class="text-lg font-bold text-slate-900">No playlists yet</h3>
        <p class="text-slate-500 mt-1">Start a playlist to share your favourite tunes with colleagues</p>
        <button @click="editingPlaylistId = null; playlistForm = { theme: '' }; showCreatePlaylist = true" class="btn-primary mt-4">Create My First Playlist</button>
      </div>

      <div v-else class="space-y-3">
        <div v-for="pl in myPlaylists" :key="pl.id" class="card overflow-hidden">
          <div class="p-4 flex items-center gap-4">
            <div class="w-12 h-12 rounded-xl flex items-center justify-center text-2xl shrink-0" :class="`bg-gradient-to-br ${getMoodGradient(pl.theme)}`">
              <span class="text-white">{{ getMoodEmoji(pl.theme) }}</span>
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-semibold text-slate-900 truncate">{{ pl.theme || 'Untitled Playlist' }}</h3>
              <p class="text-xs text-slate-500">Created {{ new Date(pl.created_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) }}</p>
            </div>
            <div class="flex items-center gap-1.5">
              <button @click="selectPlaylist(pl); tab = 'weekly'" class="p-2 rounded-lg text-slate-400 hover:text-sycamore-600 hover:bg-sycamore-50 transition-colors" title="View">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                  <path d="M10 12.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z" />
                  <path fill-rule="evenodd" d="M.664 10.59a1.651 1.651 0 0 1 0-1.186A10.004 10.004 0 0 1 10 3c4.257 0 7.893 2.66 9.336 6.41.147.381.146.804 0 1.186A10.004 10.004 0 0 1 10 17c-4.257 0-7.893-2.66-9.336-6.41ZM14 10a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z" clip-rule="evenodd" />
                </svg>
              </button>
              <button @click="openEditPlaylist(pl)" class="p-2 rounded-lg text-slate-400 hover:text-sycamore-600 hover:bg-sycamore-50 transition-colors" title="Edit">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                  <path d="m5.433 13.917 1.262-3.155A4 4 0 0 1 7.58 9.42l6.92-6.918a2.121 2.121 0 0 1 3 3l-6.92 6.918c-.383.383-.84.685-1.343.886l-3.154 1.262a.5.5 0 0 1-.65-.65Z" />
                  <path d="M3.5 5.75c0-.69.56-1.25 1.25-1.25H10A.75.75 0 0 0 10 3H4.75A2.75 2.75 0 0 0 2 5.75v9.5A2.75 2.75 0 0 0 4.75 18h9.5A2.75 2.75 0 0 0 17 15.25V10a.75.75 0 0 0-1.5 0v5.25c0 .69-.56 1.25-1.25 1.25h-9.5c-.69 0-1.25-.56-1.25-1.25v-9.5Z" />
                </svg>
              </button>
              <button v-if="confirmDeletePlaylist !== pl.id" @click="confirmDeletePlaylist = pl.id" class="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 transition-colors" title="Delete">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-4 h-4">
                  <path fill-rule="evenodd" d="M8.75 1A2.75 2.75 0 0 0 6 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 1 0 .23 1.482l.149-.022 1.005 11.07A2.75 2.75 0 0 0 7.763 19.5h4.474a2.75 2.75 0 0 0 2.744-2.469l1.005-11.07.149.022a.75.75 0 0 0 .23-1.482A41.03 41.03 0 0 0 14 4.193V3.75A2.75 2.75 0 0 0 11.25 1h-2.5ZM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4ZM8.58 7.72a.75.75 0 0 0-1.5.06l.3 7.5a.75.75 0 1 0 1.5-.06l-.3-7.5Zm4.34.06a.75.75 0 1 0-1.5-.06l-.3 7.5a.75.75 0 1 0 1.5.06l.3-7.5Z" clip-rule="evenodd" />
                </svg>
              </button>
              <div v-else class="flex items-center gap-1">
                <button @click="deleteMyPlaylist(pl.id)" class="px-2 py-1 rounded text-xs font-medium bg-red-600 text-white hover:bg-red-700">Delete</button>
                <button @click="confirmDeletePlaylist = null" class="px-2 py-1 rounded text-xs font-medium bg-slate-100 text-slate-600 hover:bg-slate-200">Cancel</button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- All Staff Playlists -->
      <div v-if="myPlaylists.length > 0" class="mt-8">
        <h3 class="text-sm font-semibold text-slate-500 uppercase tracking-wider mb-3">All Staff Playlists</h3>
        <div class="grid sm:grid-cols-2 gap-3">
          <button
            v-for="pl in myPlaylists"
            :key="'browse-'+pl.id"
            @click="selectPlaylist(pl); tab = 'weekly'"
            class="card p-4 text-left hover:shadow-md transition-all group"
          >
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-lg flex items-center justify-center text-lg shrink-0" :class="`bg-gradient-to-br ${getMoodGradient(pl.theme)}`">
                <span class="text-white">{{ getMoodEmoji(pl.theme) }}</span>
              </div>
              <div class="flex-1 min-w-0">
                <h4 class="font-medium text-slate-900 truncate group-hover:text-sycamore-700 transition-colors">{{ pl.theme || 'Untitled' }}</h4>
                <p class="text-xs text-slate-400">{{ formatWeek(pl.week_start) }}</p>
              </div>
            </div>
          </button>
        </div>
      </div>
    </template>

    <!-- Add Song Modal -->
    <div v-if="showAddSong" class="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4" @click.self="showAddSong = false">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 animate-[slideUp_0.2s_ease-out]">
        <div class="flex items-center gap-3 mb-5">
          <div class="w-10 h-10 rounded-xl bg-sycamore-100 flex items-center justify-center text-xl">🎵</div>
          <div>
            <h2 class="text-lg font-bold text-slate-900">Add a Song</h2>
            <p class="text-xs text-slate-500">Share what you're listening to</p>
          </div>
        </div>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Song Title</label>
            <input v-model="songForm.title" class="input" placeholder="e.g. Bohemian Rhapsody">
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Artist</label>
            <input v-model="songForm.artist" class="input" placeholder="e.g. Queen">
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Spotify / YouTube Link (optional)</label>
            <input v-model="songForm.url" class="input" placeholder="Paste a link so others can listen">
          </div>
        </div>
        <div class="flex justify-end gap-2 mt-5">
          <button @click="showAddSong = false" class="btn-secondary">Cancel</button>
          <button @click="addSong" :disabled="!songForm.title.trim() || !songForm.artist.trim() || submitting" class="btn-primary">
            {{ submitting ? 'Adding...' : 'Add to Playlist' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Create/Edit Playlist Modal -->
    <div v-if="showCreatePlaylist" class="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4" @click.self="showCreatePlaylist = false">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-sm p-6 animate-[slideUp_0.2s_ease-out]">
        <div class="flex items-center gap-3 mb-5">
          <div class="w-10 h-10 rounded-xl bg-leaf-100 flex items-center justify-center text-xl">🎧</div>
          <div>
            <h2 class="text-lg font-bold text-slate-900">{{ editingPlaylistId ? 'Edit Playlist' : 'New Playlist' }}</h2>
            <p class="text-xs text-slate-500">{{ editingPlaylistId ? 'Update your playlist details' : 'Give your playlist a mood or theme' }}</p>
          </div>
        </div>
        <div>
          <label class="block text-xs font-medium text-slate-600 mb-1">Playlist Name / Theme</label>
          <input v-model="playlistForm.theme" class="input" placeholder="e.g. Chill Vibes, Workout Jams, Afrobeats Friday">
        </div>
        <div class="flex justify-end gap-2 mt-5">
          <button @click="showCreatePlaylist = false; editingPlaylistId = null" class="btn-secondary">Cancel</button>
          <button @click="editingPlaylistId ? editMyPlaylist() : createMyPlaylist()" :disabled="!playlistForm.theme.trim() || submitting" class="btn-primary">
            {{ editingPlaylistId ? 'Save Changes' : 'Create Playlist' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
@keyframes slideUp {
  from { opacity: 0; transform: translateY(12px); }
  to { opacity: 1; transform: translateY(0); }
}
</style>
