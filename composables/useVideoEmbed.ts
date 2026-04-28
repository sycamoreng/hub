export function toEmbedUrl(raw: string | null | undefined): string | null {
  if (!raw) return null
  const url = raw.trim()
  if (!url) return null

  try {
    const u = new URL(url)
    const host = u.hostname.replace(/^www\./, '')

    if (host === 'youtu.be') {
      const id = u.pathname.replace(/^\//, '')
      return id ? `https://www.youtube.com/embed/${id}` : null
    }
    if (host.endsWith('youtube.com')) {
      if (u.pathname === '/watch') {
        const id = u.searchParams.get('v')
        return id ? `https://www.youtube.com/embed/${id}` : null
      }
      if (u.pathname.startsWith('/embed/')) return url
      if (u.pathname.startsWith('/shorts/')) {
        const id = u.pathname.split('/')[2]
        return id ? `https://www.youtube.com/embed/${id}` : null
      }
    }
    if (host === 'vimeo.com') {
      const id = u.pathname.replace(/^\//, '').split('/')[0]
      return /^\d+$/.test(id) ? `https://player.vimeo.com/video/${id}` : null
    }
    if (host.endsWith('player.vimeo.com')) return url
    if (host.endsWith('loom.com')) {
      const m = u.pathname.match(/\/share\/([0-9a-f]+)/i) || u.pathname.match(/\/embed\/([0-9a-f]+)/i)
      return m ? `https://www.loom.com/embed/${m[1]}` : null
    }
    return null
  } catch {
    return null
  }
}

export function isEmbeddable(url: string | null | undefined) {
  return toEmbedUrl(url) !== null
}
