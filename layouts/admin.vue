<script setup lang="ts">
const sidebarOpen = ref(false)
const route = useRoute()
const { user, signOut } = useAuth()
watch(() => route.fullPath, () => { sidebarOpen.value = false })

async function handleSignOut() {
  await signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="min-h-screen flex bg-slate-50">
    <aside class="hidden lg:flex flex-col w-64 bg-slate-900 text-slate-200 fixed inset-y-0 left-0 z-30">
      <div class="h-16 flex items-center gap-3 px-5 border-b border-slate-800">
        <img src="/logo.png" alt="Sycamore" class="h-7 w-auto brightness-0 invert" />
        <div class="text-xs text-slate-400 border-l border-slate-700 pl-3">Admin</div>
      </div>
      <div class="flex-1 overflow-y-auto p-3">
        <AdminNav />
      </div>
      <div class="p-4 border-t border-slate-800 text-xs">
        <div class="text-slate-400 truncate mb-2">{{ user?.email }}</div>
        <div class="flex gap-2">
          <NuxtLink to="/" class="flex-1 text-center px-2 py-1.5 rounded-md bg-slate-800 hover:bg-slate-700 text-slate-200">View site</NuxtLink>
          <button @click="handleSignOut" class="flex-1 text-center px-2 py-1.5 rounded-md bg-slate-800 hover:bg-slate-700 text-slate-200">Sign out</button>
        </div>
      </div>
    </aside>

    <div v-if="sidebarOpen" class="lg:hidden fixed inset-0 bg-slate-900/50 z-40" @click="sidebarOpen = false" />
    <aside v-if="sidebarOpen" class="lg:hidden fixed inset-y-0 left-0 w-64 bg-slate-900 text-slate-200 z-50 flex flex-col">
      <div class="h-16 flex items-center justify-between px-4 border-b border-slate-800">
        <div class="font-bold text-white text-sm">Sycamore Admin</div>
        <button class="p-2 rounded-lg hover:bg-slate-800" @click="sidebarOpen = false"><SidebarIcon name="close" /></button>
      </div>
      <div class="flex-1 overflow-y-auto p-3"><AdminNav /></div>
      <div class="p-4 border-t border-slate-800 text-xs">
        <div class="text-slate-400 truncate mb-2">{{ user?.email }}</div>
        <button @click="handleSignOut" class="w-full px-2 py-1.5 rounded-md bg-slate-800 text-slate-200">Sign out</button>
      </div>
    </aside>

    <div class="flex-1 lg:ml-64 flex flex-col min-w-0">
      <header class="lg:hidden sticky top-0 h-16 bg-white border-b border-slate-200 flex items-center justify-between px-4 z-20">
        <div class="font-bold text-slate-900 text-sm">Admin</div>
        <button class="p-2 rounded-lg hover:bg-slate-100" @click="sidebarOpen = true"><SidebarIcon name="menu" /></button>
      </header>
      <main class="flex-1 p-4 sm:p-6 lg:p-10">
        <slot />
      </main>
    </div>
  </div>
</template>
