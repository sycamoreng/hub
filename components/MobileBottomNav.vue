<script setup lang="ts">
const route = useRoute()
const { isAuthenticated } = useAuth()

const tabs = [
  { to: '/', label: 'Home', icon: 'home' },
  { to: '/feed', label: 'Feed', icon: 'chat' },
  { to: '/attendance', label: 'Clock in', icon: 'clock' },
  { to: '/recognition', label: 'Kudos', icon: 'star' },
  { to: '/profile', label: 'Profile', icon: 'users' },
]

function isActive(to: string) {
  if (to === '/') return route.path === '/'
  return route.path.startsWith(to)
}
</script>

<template>
  <nav v-if="isAuthenticated" class="lg:hidden fixed bottom-0 left-0 right-0 z-40 bg-white border-t border-slate-200 safe-bottom">
    <div class="flex items-stretch justify-around h-14">
      <NuxtLink
        v-for="tab in tabs"
        :key="tab.to"
        :to="tab.to"
        class="flex flex-col items-center justify-center flex-1 gap-0.5 transition-colors relative"
        :class="isActive(tab.to) ? 'text-sycamore-600' : 'text-slate-400'"
      >
        <div v-if="isActive(tab.to)" class="absolute top-0 left-1/2 -translate-x-1/2 w-8 h-0.5 rounded-full bg-sycamore-600" />
        <SidebarIcon :name="tab.icon" />
        <span class="text-[10px] font-medium leading-none">{{ tab.label }}</span>
      </NuxtLink>
    </div>
  </nav>
</template>

<style scoped>
.safe-bottom {
  padding-bottom: env(safe-area-inset-bottom, 0px);
}
</style>
