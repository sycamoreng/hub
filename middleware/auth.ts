export default defineNuxtRouteMiddleware(async (to) => {
  if (import.meta.server) return
  const { isAuthenticated, isAdmin, isSuperAdmin, canManageSection, init } = useAuth()
  await init()

  if (!isAuthenticated.value) {
    return navigateTo(`/login?redirect=${encodeURIComponent(to.fullPath)}`)
  }

  const path = to.path
  if (path === '/admin/forbidden') return

  if (!isAdmin.value) {
    return navigateTo('/admin/forbidden')
  }

  if (path === '/admin/admins' && !isSuperAdmin.value) {
    return navigateTo('/admin/forbidden')
  }

  const match = path.match(/^\/admin\/([^/]+)/)
  if (match) {
    const section = match[1]
    if (section !== 'forbidden' && section !== 'admins' && !canManageSection(section)) {
      return navigateTo('/admin/forbidden')
    }
  }
})
