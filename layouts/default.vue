<script setup lang="ts">
const sidebarOpen = ref(false)
const route = useRoute()
watch(() => route.fullPath, () => { sidebarOpen.value = false })

const { profile, isAuthenticated, signOut } = useAuth()
const avatarOk = ref(true)
watch(() => profile.value?.avatarUrl, () => { avatarOk.value = true })

async function handleSignOut() {
  await signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-screen flex">
    <aside class="hidden lg:flex flex-col w-64 bg-white border-r border-slate-200 fixed inset-y-0 left-0 z-30">
      <div class="h-16 flex items-center gap-3 px-5 border-b border-slate-200">
        <NuxtLink to="/" class="flex items-center gap-2.5">
          <img src="/logo-icon.png" alt="Sycamore" class="w-9 h-9" />
          <div>
            <div class="font-bold text-slate-900 text-sm leading-tight">Sycamore</div>
            <div class="text-xs text-slate-500 leading-tight">Information Hub</div>
          </div>
        </NuxtLink>
      </div>
      <div class="flex-1 overflow-y-auto p-3">
        <SidebarNav />
      </div>
      <div class="p-4 border-t border-slate-200 space-y-3">
        <ClientOnly>
        <template v-if="isAuthenticated && profile">
          <div class="flex items-center gap-3 p-2 rounded-lg bg-slate-50">
            <img
              v-if="profile.avatarUrl && avatarOk"
              :src="profile.avatarUrl"
              :alt="profile.name"
              referrerpolicy="no-referrer"
              class="w-9 h-9 rounded-full object-cover flex-shrink-0"
              @error="avatarOk = false"
            />
            <div v-else class="w-9 h-9 rounded-full bg-sycamore-600 text-white flex items-center justify-center text-xs font-semibold flex-shrink-0">
              {{ profile.initials }}
            </div>
            <div class="min-w-0 flex-1">
              <div class="text-xs font-semibold text-slate-900 truncate">{{ profile.name }}</div>
              <div class="text-[11px] text-slate-500 truncate">{{ profile.email }}</div>
            </div>
          </div>
          <NuxtLink to="/profile" class="flex items-center justify-center gap-1.5 px-2 py-2 rounded-lg bg-slate-50 border border-slate-200 text-slate-700 text-xs font-medium hover:bg-slate-100 transition-colors">
            My profile
          </NuxtLink>
          <div class="grid grid-cols-2 gap-2">
            <NuxtLink to="/admin" class="flex items-center justify-center gap-1.5 px-2 py-2 rounded-lg bg-slate-900 text-white text-xs font-medium hover:bg-slate-800 transition-colors">
              <SidebarIcon name="edit" /> Admin
            </NuxtLink>
            <button @click="handleSignOut" class="flex items-center justify-center gap-1.5 px-2 py-2 rounded-lg border border-slate-200 text-slate-700 text-xs font-medium hover:bg-slate-50 transition-colors">
              Sign out
            </button>
          </div>
        </template>
        <template v-else>
          <NuxtLink to="/login" class="flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-sycamore-600 text-white text-xs font-medium hover:bg-sycamore-700 transition-colors">
            Sign in with Google
          </NuxtLink>
        </template>
        <template #fallback>
          <div class="h-9 rounded-lg bg-slate-50 animate-pulse" />
        </template>
        </ClientOnly>
        <div class="text-xs text-slate-400">Sycamore &copy; {{ new Date().getFullYear() }}</div>
      </div>
    </aside>

    <div v-if="sidebarOpen" class="lg:hidden fixed inset-0 bg-slate-900/50 z-40" @click="sidebarOpen = false" />
    <aside
      v-if="sidebarOpen"
      class="lg:hidden fixed inset-y-0 left-0 w-64 bg-white z-50 flex flex-col"
    >
      <div class="h-16 flex items-center justify-between px-4 border-b border-slate-200">
        <div class="flex items-center gap-2.5">
          <img src="/logo-icon.png" alt="Sycamore" class="w-9 h-9" />
          <div class="font-bold text-slate-900 text-sm">Sycamore</div>
        </div>
        <button class="p-2 rounded-lg hover:bg-slate-100" @click="sidebarOpen = false">
          <SidebarIcon name="close" />
        </button>
      </div>
      <div class="flex-1 overflow-y-auto p-3">
        <SidebarNav />
      </div>
    </aside>

    <div class="flex-1 lg:ml-64 flex flex-col min-w-0">
      <header class="lg:hidden sticky top-0 h-16 bg-white border-b border-slate-200 flex items-center justify-between px-4 z-20">
        <div class="flex items-center gap-2.5">
          <img src="/logo-icon.png" alt="Sycamore" class="w-8 h-8" />
          <span class="font-bold text-slate-900 text-sm">Sycamore Hub</span>
        </div>
        <div class="flex items-center gap-2">
          <ClientOnly>
          <NuxtLink v-if="isAuthenticated && profile" to="/admin" class="hidden sm:block">
            <img
              v-if="profile.avatarUrl && avatarOk"
              :src="profile.avatarUrl"
              :alt="profile.name"
              referrerpolicy="no-referrer"
              class="w-8 h-8 rounded-full object-cover"
              @error="avatarOk = false"
            />
            <div v-else class="w-8 h-8 rounded-full bg-sycamore-600 text-white flex items-center justify-center text-[11px] font-semibold">
              {{ profile.initials }}
            </div>
          </NuxtLink>
          <NuxtLink v-else to="/login" class="hidden sm:inline-flex items-center px-3 py-1.5 rounded-lg bg-sycamore-600 text-white text-xs font-medium">Sign in</NuxtLink>
          </ClientOnly>
          <button class="p-2 rounded-lg hover:bg-slate-100" @click="sidebarOpen = true">
            <SidebarIcon name="menu" />
          </button>
        </div>
      </header>
      <main class="flex-1 p-4 sm:p-6 lg:p-10">
        <slot />
      </main>
    </div>
    <ClientOnly>
      <ChatWidget />
    </ClientOnly>
  </div>
</template>
