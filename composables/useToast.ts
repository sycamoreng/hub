export type ToastVariant = 'success' | 'error' | 'info' | 'warning'

export interface ToastItem {
  id: number
  variant: ToastVariant
  title?: string
  message: string
  duration: number
}

export interface ConfirmOptions {
  title?: string
  message: string
  confirmLabel?: string
  cancelLabel?: string
  variant?: 'danger' | 'primary'
}

interface ConfirmState extends ConfirmOptions {
  open: boolean
  resolve: ((ok: boolean) => void) | null
}

let nextId = 1

export function useToast() {
  const items = useState<ToastItem[]>('toast.items', () => [])
  const confirmState = useState<ConfirmState>('toast.confirm', () => ({
    open: false,
    message: '',
    resolve: null
  }))

  function push(variant: ToastVariant, message: string, opts: { title?: string; duration?: number } = {}) {
    const id = nextId++
    const duration = opts.duration ?? (variant === 'error' ? 6000 : 4000)
    items.value = [...items.value, { id, variant, title: opts.title, message, duration }]
    if (duration > 0) setTimeout(() => dismiss(id), duration)
    return id
  }

  function dismiss(id: number) {
    items.value = items.value.filter(t => t.id !== id)
  }

  function confirm(opts: ConfirmOptions): Promise<boolean> {
    return new Promise(resolve => {
      confirmState.value = {
        open: true,
        title: opts.title ?? 'Are you sure?',
        message: opts.message,
        confirmLabel: opts.confirmLabel ?? 'Confirm',
        cancelLabel: opts.cancelLabel ?? 'Cancel',
        variant: opts.variant ?? 'danger',
        resolve
      }
    })
  }

  function resolveConfirm(ok: boolean) {
    confirmState.value.resolve?.(ok)
    confirmState.value = { ...confirmState.value, open: false, resolve: null }
  }

  return {
    items,
    confirmState,
    dismiss,
    confirm,
    resolveConfirm,
    success: (message: string, opts?: { title?: string; duration?: number }) => push('success', message, opts),
    error: (message: string, opts?: { title?: string; duration?: number }) => push('error', message, opts),
    info: (message: string, opts?: { title?: string; duration?: number }) => push('info', message, opts),
    warning: (message: string, opts?: { title?: string; duration?: number }) => push('warning', message, opts)
  }
}
