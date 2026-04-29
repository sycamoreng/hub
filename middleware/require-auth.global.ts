export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return
  if (to.path === '/login' || to.path === '/unsubscribe') return

  const { isAuthenticated, init } = useAuth()
  await init()

  if (!isAuthenticated.value) {
    return navigateTo(`/login?redirect=${encodeURIComponent(to.fullPath)}`)
  }
})
