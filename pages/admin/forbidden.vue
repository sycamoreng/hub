<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })

const { profile, signOut } = useAuth()

async function handleSignOut() {
  await signOut()
  await navigateTo('/login')
}
</script>

<template>
  <div class="max-w-2xl mx-auto py-12">
    <div class="card p-10 text-center">
      <div class="w-14 h-14 rounded-full bg-rose-50 text-rose-600 flex items-center justify-center mx-auto mb-5">
        <SidebarIcon name="alert" />
      </div>
      <h1 class="text-2xl font-bold text-slate-900 mb-2">Access restricted</h1>
      <p class="text-slate-600 mb-1">
        Hello {{ profile?.name || profile?.email || 'there' }}, your account does not have admin permissions for this area.
      </p>
      <p class="text-slate-500 text-sm mb-8">
        If you believe you should have access, please contact a super-admin to request the appropriate role.
      </p>
      <div class="flex items-center justify-center gap-3">
        <NuxtLink to="/" class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700">Back to hub</NuxtLink>
        <button @click="handleSignOut" class="px-4 py-2 rounded-lg border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50">Sign out</button>
      </div>
    </div>
  </div>
</template>
