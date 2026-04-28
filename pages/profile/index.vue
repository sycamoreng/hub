<script setup lang="ts">
import { PROFILE_THEMES, getThemeGradient, type UserProfile } from '~/composables/useProfile'

const { user, profile, ready } = useAuth()
const { ensureOwnProfile, saveOwnProfile, fetchStaffByAuthUser } = useProfile()

const loading = ref(true)
const saving = ref(false)
const saved = ref(false)
const error = ref<string | null>(null)
const data = ref<UserProfile | null>(null)
const staff = ref<any | null>(null)

async function load() {
  if (!user.value) return
  loading.value = true
  error.value = null
  try {
    const [p, s] = await Promise.all([
      ensureOwnProfile(user.value.id),
      fetchStaffByAuthUser(user.value.id)
    ])
    data.value = p
    staff.value = s
  } catch (e: any) {
    error.value = e.message ?? 'Failed to load profile'
  } finally {
    loading.value = false
  }
}

watch([ready, user], () => { if (ready.value) load() }, { immediate: true })

async function save() {
  if (!data.value) return
  saving.value = true
  saved.value = false
  error.value = null
  try {
    const next = await saveOwnProfile(data.value)
    data.value = next
    saved.value = true
    setTimeout(() => { saved.value = false }, 2000)
  } catch (e: any) {
    error.value = e.message ?? 'Failed to save profile'
  } finally {
    saving.value = false
  }
}

definePageMeta({ title: 'My Profile' })
</script>

<template>
  <div class="max-w-4xl mx-auto space-y-6">
    <div v-if="!ready || loading" class="text-sm text-slate-400">Loading profile...</div>

    <template v-else-if="!user">
      <div class="card p-8 text-center">
        <h2 class="text-lg font-semibold text-slate-900">Sign in required</h2>
        <p class="text-sm text-slate-500 mt-1">You need to be signed in to view and edit your profile.</p>
        <NuxtLink to="/login" class="btn-primary inline-flex mt-4">Sign in</NuxtLink>
      </div>
    </template>

    <template v-else-if="data">
      <div :class="['rounded-2xl p-6 sm:p-8 text-white relative overflow-hidden bg-gradient-to-br', getThemeGradient(data.theme)]">
        <div class="flex items-center gap-4 relative z-10">
          <img
            v-if="profile?.avatarUrl"
            :src="profile.avatarUrl"
            :alt="profile.name"
            referrerpolicy="no-referrer"
            class="w-16 h-16 rounded-full object-cover border-2 border-white/30"
          />
          <div v-else class="w-16 h-16 rounded-full bg-white/20 flex items-center justify-center text-xl font-semibold">
            {{ profile?.initials }}
          </div>
          <div class="min-w-0">
            <div class="text-xl sm:text-2xl font-bold">{{ profile?.name }}</div>
            <div class="text-sm text-white/80">{{ profile?.email }}</div>
            <div v-if="staff?.role" class="text-xs text-white/70 mt-0.5">{{ staff.role }}</div>
          </div>
        </div>
        <div class="absolute -right-16 -bottom-16 w-72 h-72 rounded-full bg-white/5" />
      </div>

      <div class="card p-6 space-y-5">
        <div>
          <h3 class="text-sm font-semibold text-slate-900 mb-1">Identity</h3>
          <p class="text-xs text-slate-500">Name, email and phone are managed centrally and can only be changed by an administrator.</p>
        </div>
        <div class="grid sm:grid-cols-2 gap-4">
          <div>
            <label class="text-xs font-medium text-slate-600">Full name</label>
            <input :value="profile?.name || staff?.full_name || ''" disabled class="input mt-1 bg-slate-50 text-slate-500" />
          </div>
          <div>
            <label class="text-xs font-medium text-slate-600">Email</label>
            <input :value="profile?.email || staff?.email || ''" disabled class="input mt-1 bg-slate-50 text-slate-500" />
          </div>
          <div>
            <label class="text-xs font-medium text-slate-600">Phone</label>
            <input :value="staff?.phone || 'Not on record'" disabled class="input mt-1 bg-slate-50 text-slate-500" />
          </div>
          <div>
            <label class="text-xs font-medium text-slate-600">Role</label>
            <input :value="staff?.role || 'Not on record'" disabled class="input mt-1 bg-slate-50 text-slate-500" />
          </div>
        </div>
      </div>

      <div class="card p-6 space-y-5">
        <div>
          <h3 class="text-sm font-semibold text-slate-900 mb-1">Theme</h3>
          <p class="text-xs text-slate-500">Pick the colour theme for your profile header.</p>
        </div>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <button
            v-for="t in PROFILE_THEMES"
            :key="t.key"
            type="button"
            class="rounded-xl p-3 border-2 transition-all text-left"
            :class="data.theme === t.key ? 'border-sycamore-500 ring-2 ring-sycamore-100' : 'border-slate-200 hover:border-slate-300'"
            @click="data.theme = t.key"
          >
            <div :class="['h-12 rounded-lg bg-gradient-to-br', t.gradient]" />
            <div class="text-xs font-medium text-slate-700 mt-2">{{ t.label }}</div>
          </button>
        </div>
      </div>

      <div class="card p-6 space-y-5">
        <div>
          <h3 class="text-sm font-semibold text-slate-900 mb-1">Bio</h3>
          <p class="text-xs text-slate-500">Tell colleagues a bit about you. Plain text, up to 1,000 characters.</p>
        </div>
        <textarea
          v-model="data.bio"
          maxlength="1000"
          rows="5"
          class="input"
          placeholder="A few sentences about your role, what you're working on, or things you're interested in."
        />
        <div class="text-xs text-slate-400 text-right">{{ (data.bio || '').length }} / 1000</div>
      </div>

      <div class="card p-6 space-y-5">
        <div>
          <h3 class="text-sm font-semibold text-slate-900 mb-1">Socials</h3>
          <p class="text-xs text-slate-500">Optional links shown on your public profile.</p>
        </div>
        <div class="grid sm:grid-cols-2 gap-4">
          <div>
            <label class="text-xs font-medium text-slate-600">LinkedIn</label>
            <input v-model="data.linkedin_url" type="url" placeholder="https://linkedin.com/in/..." class="input mt-1" />
          </div>
          <div>
            <label class="text-xs font-medium text-slate-600">X / Twitter</label>
            <input v-model="data.twitter_url" type="url" placeholder="https://x.com/..." class="input mt-1" />
          </div>
          <div>
            <label class="text-xs font-medium text-slate-600">GitHub</label>
            <input v-model="data.github_url" type="url" placeholder="https://github.com/..." class="input mt-1" />
          </div>
          <div>
            <label class="text-xs font-medium text-slate-600">Instagram</label>
            <input v-model="data.instagram_url" type="url" placeholder="https://instagram.com/..." class="input mt-1" />
          </div>
          <div class="sm:col-span-2">
            <label class="text-xs font-medium text-slate-600">Personal website</label>
            <input v-model="data.website_url" type="url" placeholder="https://..." class="input mt-1" />
          </div>
        </div>
      </div>

      <div class="flex items-center justify-end gap-3">
        <p v-if="error" class="text-xs text-rose-600 mr-auto">{{ error }}</p>
        <p v-else-if="saved" class="text-xs text-emerald-600 mr-auto">Saved.</p>
        <NuxtLink v-if="staff?.id" :to="`/profile/${staff.id}`" class="btn-secondary">View public profile</NuxtLink>
        <button type="button" class="btn-primary" :disabled="saving" @click="save">
          {{ saving ? 'Saving...' : 'Save changes' }}
        </button>
      </div>
    </template>
  </div>
</template>
