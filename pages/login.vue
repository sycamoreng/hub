<script setup lang="ts">
definePageMeta({ layout: false })

const { signInWithGoogle, init, isAuthenticated, domainError, clearDomainError } = useAuth()
const route = useRoute()

const error = ref<string | null>(null)
const loading = ref(false)

const REDIRECT_KEY = 'sycamore.postLoginRedirect'

watchEffect(() => {
  if (domainError.value) error.value = domainError.value
})

function sanitize(path: string | null | undefined): string | null {
  if (!path || typeof path !== 'string') return null
  if (!path.startsWith('/') || path.startsWith('//')) return null
  if (path === '/login') return null
  return path
}

function resolveRedirect(): string {
  const raw = route.query.redirect
  const fromQuery = Array.isArray(raw) ? raw[0] : raw
  const queryPath = sanitize(typeof fromQuery === 'string' ? fromQuery : null)
  if (queryPath) return queryPath
  if (typeof window !== 'undefined') {
    const stored = sanitize(window.sessionStorage.getItem(REDIRECT_KEY))
    if (stored) return stored
  }
  return '/'
}

function rememberRedirect(path: string) {
  if (typeof window === 'undefined') return
  const clean = sanitize(path)
  if (clean) window.sessionStorage.setItem(REDIRECT_KEY, clean)
}

function clearStoredRedirect() {
  if (typeof window === 'undefined') return
  window.sessionStorage.removeItem(REDIRECT_KEY)
}

async function doRedirect() {
  const target = resolveRedirect()
  clearStoredRedirect()
  await navigateTo(target, { replace: true })
}

onMounted(async () => {
  await init()
  if (isAuthenticated.value) {
    await doRedirect()
  }
})

watch(isAuthenticated, async (val) => {
  if (val) await doRedirect()
})

onBeforeUnmount(() => clearDomainError())

async function googleSignIn() {
  error.value = null
  loading.value = true
  try {
    const target = resolveRedirect()
    rememberRedirect(target)
    await signInWithGoogle(target)
  } catch (e: any) {
    error.value = e.message || 'Google sign-in failed.'
    loading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen flex bg-slate-50">
    <div class="hidden lg:flex flex-col justify-between w-1/2 bg-gradient-to-br from-sycamore-700 to-sycamore-900 text-white p-12 relative overflow-hidden">
      <div class="relative z-10">
        <div class="mb-12">
          <img src="/logo.png" alt="Sycamore" class="h-9 w-auto brightness-0 invert" />
        </div>
        <h1 class="text-4xl font-bold tracking-tight mb-4 max-w-md">Welcome to the Sycamore Information Hub.</h1>
        <p class="text-sycamore-50 max-w-md">Sign in with your Sycamore Google account to access company knowledge, products, policies, and more.</p>
      </div>
      <div class="relative z-10 text-sm text-sycamore-100/80">Sycamore &copy; {{ new Date().getFullYear() }}</div>
      <div class="absolute -right-24 -bottom-24 w-96 h-96 rounded-full bg-white/5" />
      <div class="absolute -right-8 top-32 w-48 h-48 rounded-full bg-white/5" />
    </div>

    <div class="flex-1 flex items-center justify-center p-6">
      <div class="w-full max-w-md">
        <div class="lg:hidden mb-8 flex justify-center">
          <img src="/logo.png" alt="Sycamore" class="h-9 w-auto" />
        </div>

        <div class="card p-8 sm:p-10">
          <div class="w-14 h-14 rounded-full bg-sycamore-50 flex items-center justify-center mx-auto mb-5">
            <img src="/logo-icon.png" alt="" class="w-9 h-9" />
          </div>
          <h2 class="text-2xl font-bold text-slate-900 text-center mb-2">Sign in to continue</h2>
          <p class="text-sm text-slate-500 text-center mb-8">Use your Sycamore Google account to access the hub.</p>

          <button
            type="button"
            @click="googleSignIn"
            :disabled="loading"
            class="w-full flex items-center justify-center gap-3 px-4 py-3 rounded-lg border border-slate-300 bg-white text-slate-800 text-sm font-semibold hover:bg-slate-50 disabled:opacity-60 transition-colors"
          >
            <svg class="w-5 h-5" viewBox="0 0 48 48" aria-hidden="true">
              <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"/>
              <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 16.1 19 13 24 13c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4c-7.6 0-14.2 4.3-17.7 10.7z"/>
              <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.7 39.7 16.3 44 24 44z"/>
              <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.3-2.2 4.2-4.1 5.6l6.2 5.2C41.1 35.7 44 30.3 44 24c0-1.3-.1-2.4-.4-3.5z"/>
            </svg>
            {{ loading ? 'Redirecting to Google...' : 'Continue with Google' }}
          </button>

          <div v-if="error" class="mt-4 text-sm text-rose-700 bg-rose-50 border border-rose-200 rounded-lg p-3">{{ error }}</div>

          <p class="text-xs text-slate-400 text-center mt-6">
            Access is limited to <span class="font-semibold text-slate-500">@sycamore.ng</span> and <span class="font-semibold text-slate-500">@sycamoreglobal.co.uk</span> Google accounts.
          </p>
        </div>

        <div class="mt-6 text-center">
          <NuxtLink to="/" class="text-xs text-slate-500 hover:text-slate-700">&larr; Back to information hub</NuxtLink>
        </div>
      </div>
    </div>
  </div>
</template>
