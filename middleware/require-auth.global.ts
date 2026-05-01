export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return
  if (to.path === '/login' || to.path === '/unsubscribe') return

  const { isAuthenticated, isAdmin, init } = useAuth()
  await init()

  if (!isAuthenticated.value) {
    return navigateTo(`/login?redirect=${encodeURIComponent(to.fullPath)}`)
  }

  if (to.path.startsWith('/admin')) return

  const { load: loadLocks, isLocked } = usePageLocks()
  await loadLocks()
  if (isLocked(to.path) && !isAdmin.value) {
    return navigateTo('/')
  }
})
