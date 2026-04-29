<script setup lang="ts">
definePageMeta({ layout: false })

const route = useRoute()
const state = ref<'loading' | 'ok' | 'error' | 'missing'>('loading')
const errorMessage = ref('')

async function run() {
  const token = (route.query.token || '').toString()
  if (!token) { state.value = 'missing'; return }
  try {
    const url = `${import.meta.env.VITE_SUPABASE_URL}/functions/v1/email/unsubscribe?token=${encodeURIComponent(token)}`
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${import.meta.env.VITE_SUPABASE_ANON_KEY}`
      }
    })
    const body = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(body.error || `Request failed (${res.status})`)
    state.value = 'ok'
  } catch (e: any) {
    errorMessage.value = e.message ?? 'Something went wrong'
    state.value = 'error'
  }
}

onMounted(run)
</script>

<template>
  <div class="min-h-screen bg-slate-50 flex items-center justify-center p-6">
    <div class="max-w-md w-full card p-8 text-center">
      <img src="/logo-icon.png" alt="Sycamore" class="w-12 h-12 mx-auto mb-4" />
      <div v-if="state === 'loading'">
        <h1 class="text-xl font-semibold text-slate-900">Updating your preferences...</h1>
        <p class="text-sm text-slate-500 mt-2">Hold on a moment.</p>
      </div>
      <div v-else-if="state === 'ok'">
        <h1 class="text-xl font-semibold text-slate-900">You're unsubscribed.</h1>
        <p class="text-sm text-slate-500 mt-2">You won't receive any more email notifications from the Sycamore Info Hub. You can re-enable them any time from your notification settings on the Hub.</p>
        <NuxtLink to="/login" class="btn-primary mt-5 inline-flex">Open the Hub</NuxtLink>
      </div>
      <div v-else-if="state === 'missing'">
        <h1 class="text-xl font-semibold text-slate-900">Missing link</h1>
        <p class="text-sm text-slate-500 mt-2">This unsubscribe link is incomplete. Try the link from the bottom of a Sycamore email.</p>
      </div>
      <div v-else>
        <h1 class="text-xl font-semibold text-slate-900">We couldn't unsubscribe you</h1>
        <p class="text-sm text-rose-600 mt-2">{{ errorMessage }}</p>
        <p class="text-sm text-slate-500 mt-3">You can also open the Hub and manage preferences yourself.</p>
        <NuxtLink to="/login" class="btn-secondary mt-5 inline-flex">Open the Hub</NuxtLink>
      </div>
    </div>
  </div>
</template>
