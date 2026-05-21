<script setup lang="ts">
const toast = useToast()
const { state, loading, submitting, photoUrl, photoLoading, error, revealedClues, guessesRemaining, load, submitGuess, usePhotoHint } = useGuessWho()

const firstName = ref('')
const lastName = ref('')
const showPhotoConfirm = ref(false)

onMounted(load)

async function handleSubmit() {
  if (!firstName.value.trim() || !lastName.value.trim()) {
    toast.error('Please enter both first and last name')
    return
  }
  await submitGuess(firstName.value.trim(), lastName.value.trim())
  if (!state.value?.completed) {
    firstName.value = ''
    lastName.value = ''
  }
}

async function confirmPhotoHint() {
  showPhotoConfirm.value = false
  await usePhotoHint()
  if (error.value) {
    toast.error(error.value)
    error.value = ''
  }
}

watch(error, (v) => {
  if (v && v !== 'no_photo') {
    toast.error(v)
    error.value = ''
  }
})
</script>

<template>
  <div class="max-w-2xl mx-auto">
    <div class="mb-8">
      <h1 class="section-title">Guess Who</h1>
      <p class="section-subtitle">A mystery colleague is described below. Can you figure out who it is?</p>
    </div>

    <!-- Loading state -->
    <div v-if="loading" class="card p-8 text-center">
      <div class="animate-pulse space-y-3">
        <div class="h-4 bg-slate-200 rounded w-3/4 mx-auto"></div>
        <div class="h-4 bg-slate-200 rounded w-1/2 mx-auto"></div>
      </div>
      <p class="text-sm text-slate-500 mt-4">Loading today's puzzle...</p>
    </div>

    <!-- No puzzle today -->
    <div v-else-if="!state" class="card p-8 text-center">
      <div class="w-14 h-14 mx-auto rounded-full bg-amber-50 text-amber-600 flex items-center justify-center mb-4">
        <SidebarIcon name="sparkle" class="w-7 h-7" />
      </div>
      <h2 class="text-lg font-semibold text-slate-900">No puzzle today</h2>
      <p class="text-sm text-slate-500 mt-1">Check back tomorrow for a new mystery colleague!</p>
    </div>

    <!-- Active game -->
    <template v-else>
      <!-- Clues card -->
      <article class="card p-6 mb-5">
        <div class="flex items-center gap-2 mb-4">
          <div class="w-8 h-8 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center">
            <SidebarIcon name="sparkle" class="w-4 h-4" />
          </div>
          <h2 class="text-base font-semibold text-slate-900">Clues</h2>
          <span class="ml-auto text-xs text-slate-400">{{ revealedClues.length }} / {{ state.clues.length }}</span>
        </div>

        <ol class="space-y-3">
          <li
            v-for="(clue, i) in revealedClues"
            :key="i"
            class="flex gap-3 items-start"
          >
            <span class="shrink-0 w-6 h-6 rounded-full bg-slate-100 text-slate-600 flex items-center justify-center text-xs font-bold mt-0.5">{{ i + 1 }}</span>
            <p class="text-sm text-slate-700 leading-relaxed">{{ clue }}</p>
          </li>
          <li v-if="!state.completed && revealedClues.length < state.clues.length" class="flex gap-3 items-start opacity-50">
            <span class="shrink-0 w-6 h-6 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center text-xs font-bold mt-0.5">{{ revealedClues.length + 1 }}</span>
            <p class="text-sm text-slate-400 italic">Make a guess to unlock the next clue...</p>
          </li>
        </ol>
      </article>

      <!-- Blurred photo hint -->
      <div v-if="photoUrl && !state.completed" class="card p-5 mb-5">
        <p class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">Photo Hint (-3 pts)</p>
        <div class="w-24 h-24 rounded-full mx-auto overflow-hidden border-2 border-slate-200">
          <img
            :src="photoUrl"
            alt="Blurred photo hint"
            class="w-full h-full object-cover"
            style="filter: blur(8px); transform: scale(1.2);"
          />
        </div>
      </div>

      <!-- Photo hint button (if available and not used) -->
      <div v-if="state.has_avatar && !state.used_photo_hint && !state.completed && !photoUrl" class="mb-5">
        <button
          type="button"
          class="btn-secondary w-full justify-center text-amber-700 border-amber-200 hover:bg-amber-50"
          @click="showPhotoConfirm = true"
        >
          <SidebarIcon name="image" class="w-4 h-4" />
          Reveal blurred photo (-3 points)
        </button>
      </div>

      <!-- No avatar notice -->
      <div v-if="!state.has_avatar && !state.completed" class="mb-5 px-4 py-3 rounded-lg bg-slate-50 border border-slate-200 text-xs text-slate-500">
        No photo available for today's mystery person.
      </div>

      <!-- Guess history -->
      <div v-if="state.guesses.length > 0" class="card p-5 mb-5">
        <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">Your Guesses</h3>
        <ul class="space-y-2">
          <li
            v-for="(g, i) in state.guesses"
            :key="i"
            class="flex items-center gap-3 px-3 py-2 rounded-lg"
            :class="g.correct ? 'bg-emerald-50 border border-emerald-200' : 'bg-rose-50 border border-rose-200'"
          >
            <span
              class="shrink-0 w-5 h-5 rounded-full flex items-center justify-center text-xs font-bold text-white"
              :class="g.correct ? 'bg-emerald-500' : 'bg-rose-400'"
            >{{ g.correct ? '&#10003;' : '&#10005;' }}</span>
            <span class="text-sm font-medium" :class="g.correct ? 'text-emerald-800' : 'text-rose-800'">
              {{ g.first_name }} {{ g.last_name }}
            </span>
          </li>
        </ul>
      </div>

      <!-- Submit form (if game is still active) -->
      <form v-if="!state.completed" class="card p-5 mb-5" @submit.prevent="handleSubmit">
        <h3 class="text-xs font-semibold text-slate-500 uppercase tracking-wide mb-3">
          Make a Guess
          <span class="ml-2 text-sycamore-600">({{ guessesRemaining }} remaining)</span>
        </h3>
        <div class="grid grid-cols-2 gap-3 mb-4">
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">First Name</label>
            <input
              v-model="firstName"
              type="text"
              class="input"
              placeholder="e.g. John"
              :disabled="submitting"
              autocomplete="off"
            />
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Last Name</label>
            <input
              v-model="lastName"
              type="text"
              class="input"
              placeholder="e.g. Doe"
              :disabled="submitting"
              autocomplete="off"
            />
          </div>
        </div>
        <button type="submit" class="btn-primary w-full justify-center" :disabled="submitting || !firstName.trim() || !lastName.trim()">
          <span v-if="submitting">Checking...</span>
          <span v-else>Submit Guess</span>
        </button>
      </form>

      <!-- Game over: Won -->
      <div v-if="state.completed && state.won" class="card p-6 text-center border-emerald-200 bg-emerald-50">
        <div class="w-14 h-14 mx-auto rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center mb-3">
          <SidebarIcon name="star" class="w-7 h-7" />
        </div>
        <h2 class="text-lg font-bold text-emerald-800">You got it!</h2>
        <p class="text-sm text-emerald-600 mt-1">
          You earned <span class="font-bold">{{ state.points_awarded }}</span> point{{ state.points_awarded !== 1 ? 's' : '' }}
        </p>
        <div v-if="state.answer" class="mt-5 flex flex-col items-center gap-3">
          <img
            v-if="state.answer.avatar_url"
            :src="state.answer.avatar_url"
            :alt="state.answer.full_name"
            class="w-20 h-20 rounded-full object-cover border-2 border-emerald-200"
          />
          <div>
            <p class="text-base font-bold text-slate-900">{{ state.answer.full_name }}</p>
            <p class="text-sm text-slate-500">{{ state.answer.role }}</p>
            <p v-if="state.answer.department" class="text-xs text-slate-400">{{ state.answer.department }}</p>
          </div>
        </div>
      </div>

      <!-- Game over: Lost -->
      <div v-if="state.completed && !state.won" class="card p-6 text-center border-rose-200 bg-rose-50">
        <div class="w-14 h-14 mx-auto rounded-full bg-rose-100 text-rose-500 flex items-center justify-center mb-3">
          <SidebarIcon name="sparkle" class="w-7 h-7" />
        </div>
        <h2 class="text-lg font-bold text-rose-800">Not this time!</h2>
        <p class="text-sm text-rose-600 mt-1">Better luck tomorrow. The mystery person was:</p>
        <div v-if="state.answer" class="mt-5 flex flex-col items-center gap-3">
          <img
            v-if="state.answer.avatar_url"
            :src="state.answer.avatar_url"
            :alt="state.answer.full_name"
            class="w-20 h-20 rounded-full object-cover border-2 border-rose-200"
          />
          <div>
            <p class="text-base font-bold text-slate-900">{{ state.answer.full_name }}</p>
            <p class="text-sm text-slate-500">{{ state.answer.role }}</p>
            <p v-if="state.answer.department" class="text-xs text-slate-400">{{ state.answer.department }}</p>
          </div>
        </div>
      </div>
    </template>

    <!-- Photo hint confirmation modal -->
    <Teleport to="body">
      <div v-if="showPhotoConfirm" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40" @click.self="showPhotoConfirm = false">
        <div class="card p-6 max-w-sm w-full">
          <h3 class="text-base font-semibold text-slate-900 mb-2">Reveal photo hint?</h3>
          <p class="text-sm text-slate-600 mb-5">You'll see a heavily blurred version of the person's photo. This will cost <span class="font-semibold text-amber-700">3 points</span> from your final score if you guess correctly.</p>
          <div class="flex gap-3">
            <button type="button" class="btn-secondary flex-1 justify-center" @click="showPhotoConfirm = false">Cancel</button>
            <button type="button" class="btn-primary flex-1 justify-center bg-amber-600 hover:bg-amber-700" @click="confirmPhotoHint" :disabled="photoLoading">
              {{ photoLoading ? 'Loading...' : 'Reveal' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
