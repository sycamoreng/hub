<script setup lang="ts">
const props = defineProps<{
  open: boolean
  src: string | null
  aspect: number
  outputWidth?: number
}>()
const emit = defineEmits<{ (e: 'cancel'): void; (e: 'confirm', blob: Blob): void }>()

const VIEW_W = 300
const viewH = computed(() => Math.round(VIEW_W / (props.aspect || 1)))

const imgEl = ref<HTMLImageElement | null>(null)
const previewCanvas = ref<HTMLCanvasElement | null>(null)
const natW = ref(0)
const natH = ref(0)
const minScale = ref(1)
const scale = ref(1)
const offsetX = ref(0)
const offsetY = ref(0)
const ready = ref(false)

const removeBg = ref(false)
const sensitivity = ref(35)

const dragging = ref(false)
let startX = 0
let startY = 0
let startOffX = 0
let startOffY = 0

function clampOffsets() {
  const w = natW.value * scale.value
  const h = natH.value * scale.value
  offsetX.value = Math.min(0, Math.max(VIEW_W - w, offsetX.value))
  offsetY.value = Math.min(0, Math.max(viewH.value - h, offsetY.value))
}

function initFromImage() {
  const img = imgEl.value
  if (!img) return
  natW.value = img.naturalWidth
  natH.value = img.naturalHeight
  const cover = Math.max(VIEW_W / natW.value, viewH.value / natH.value)
  minScale.value = cover
  scale.value = cover
  const w = natW.value * cover
  const h = natH.value * cover
  offsetX.value = (VIEW_W - w) / 2
  offsetY.value = (viewH.value - h) / 2
  ready.value = true
  schedulePreview()
}

function onImgLoad() {
  initFromImage()
}

function onZoom(e: Event) {
  const next = Number((e.target as HTMLInputElement).value)
  const cx = VIEW_W / 2
  const cy = viewH.value / 2
  const ratio = next / scale.value
  offsetX.value = cx - (cx - offsetX.value) * ratio
  offsetY.value = cy - (cy - offsetY.value) * ratio
  scale.value = next
  clampOffsets()
  schedulePreview()
}

function onPointerDown(e: PointerEvent) {
  if (!ready.value) return
  dragging.value = true
  startX = e.clientX
  startY = e.clientY
  startOffX = offsetX.value
  startOffY = offsetY.value
  ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
}
function onPointerMove(e: PointerEvent) {
  if (!dragging.value) return
  offsetX.value = startOffX + (e.clientX - startX)
  offsetY.value = startOffY + (e.clientY - startY)
  clampOffsets()
  schedulePreview()
}
function onPointerUp() {
  dragging.value = false
  schedulePreview()
}

const maxScale = computed(() => minScale.value * 4)

const imgStyle = computed(() => ({
  width: `${natW.value * scale.value}px`,
  height: `${natH.value * scale.value}px`,
  transform: `translate(${offsetX.value}px, ${offsetY.value}px)`
}))

// Flood-fill from the outer edges, replacing background-coloured pixels with
// solid white. Works best on photos with a fairly plain backdrop.
function removeBackgroundToWhite(data: Uint8ClampedArray, w: number, h: number, tol: number) {
  const corners = [0, w - 1, (h - 1) * w, h * w - 1]
  let sr = 0, sg = 0, sb = 0
  for (const p of corners) { const i = p * 4; sr += data[i]; sg += data[i + 1]; sb += data[i + 2] }
  sr /= 4; sg /= 4; sb /= 4
  const tol2 = tol * tol
  const visited = new Uint8Array(w * h)
  const stack: number[] = []
  const pushIf = (x: number, y: number) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return
    const p = y * w + x
    if (visited[p]) return
    visited[p] = 1
    stack.push(p)
  }
  for (let x = 0; x < w; x++) { pushIf(x, 0); pushIf(x, h - 1) }
  for (let y = 0; y < h; y++) { pushIf(0, y); pushIf(w - 1, y) }
  while (stack.length) {
    const p = stack.pop() as number
    const i = p * 4
    const dr = data[i] - sr, dg = data[i + 1] - sg, db = data[i + 2] - sb
    if (dr * dr + dg * dg + db * db > tol2) continue
    data[i] = 255; data[i + 1] = 255; data[i + 2] = 255; data[i + 3] = 255
    const x = p % w
    const y = (p - x) / w
    pushIf(x + 1, y); pushIf(x - 1, y); pushIf(x, y + 1); pushIf(x, y - 1)
  }
}

function computeCropCanvas(): HTMLCanvasElement | null {
  const img = imgEl.value
  if (!img || !ready.value) return null
  const outW = props.outputWidth ?? 600
  const outH = Math.round(outW / (props.aspect || 1))
  const canvas = document.createElement('canvas')
  canvas.width = outW
  canvas.height = outH
  const ctx = canvas.getContext('2d')
  if (!ctx) return null
  const sx = -offsetX.value / scale.value
  const sy = -offsetY.value / scale.value
  const sw = VIEW_W / scale.value
  const sh = viewH.value / scale.value
  ctx.imageSmoothingQuality = 'high'
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, outW, outH)
  ctx.drawImage(img, sx, sy, sw, sh, 0, 0, outW, outH)
  if (removeBg.value) {
    const tol = 20 + (sensitivity.value / 100) * 160
    const id = ctx.getImageData(0, 0, outW, outH)
    removeBackgroundToWhite(id.data, outW, outH, tol)
    ctx.putImageData(id, 0, 0)
  }
  return canvas
}

let rafId = 0
function schedulePreview() {
  if (rafId) cancelAnimationFrame(rafId)
  rafId = requestAnimationFrame(() => {
    rafId = 0
    const target = previewCanvas.value
    const src = computeCropCanvas()
    if (!target || !src) return
    target.width = src.width
    target.height = src.height
    const ctx = target.getContext('2d')
    if (ctx) ctx.drawImage(src, 0, 0)
  })
}

watch([removeBg, sensitivity], schedulePreview)

async function confirm() {
  const canvas = computeCropCanvas()
  if (!canvas) return
  const blob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.92)
  )
  if (blob) emit('confirm', blob)
}

watch(() => props.open, (o) => {
  if (o) {
    ready.value = false
    removeBg.value = false
    sensitivity.value = 35
    requestAnimationFrame(() => {
      if (imgEl.value?.complete && imgEl.value.naturalWidth) initFromImage()
    })
  }
})
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    @click.self="emit('cancel')"
  >
    <div class="bg-white rounded-2xl shadow-xl w-full max-w-sm overflow-hidden max-h-[92vh] overflow-y-auto">
      <div class="px-5 py-4 border-b border-slate-100">
        <h3 class="text-base font-bold text-slate-900">Position your photo</h3>
        <p class="text-xs text-slate-500 mt-0.5">Drag to move, use the slider to zoom. The area inside the frame is what appears on your card.</p>
      </div>

      <div class="p-5 flex flex-col items-center gap-4">
        <div
          class="relative overflow-hidden bg-white rounded-lg ring-1 ring-slate-200 touch-none select-none cursor-move"
          :style="{ width: VIEW_W + 'px', height: viewH + 'px' }"
          @pointerdown="onPointerDown"
          @pointermove="onPointerMove"
          @pointerup="onPointerUp"
          @pointercancel="onPointerUp"
        >
          <img
            v-if="src"
            ref="imgEl"
            :src="src"
            alt="Crop preview"
            class="absolute top-0 left-0 max-w-none pointer-events-none"
            :style="imgStyle"
            draggable="false"
            @load="onImgLoad"
          >
          <div class="absolute inset-0 pointer-events-none ring-2 ring-white/80 rounded-lg"></div>
        </div>

        <div class="w-full flex items-center gap-3">
          <span class="text-xs text-slate-400">Zoom</span>
          <input
            type="range"
            :min="minScale"
            :max="maxScale"
            step="0.01"
            :value="scale"
            :disabled="!ready"
            @input="onZoom"
            class="flex-1 accent-sycamore-600"
          >
        </div>

        <div class="w-full border-t border-slate-100 pt-4 space-y-3">
          <label class="flex items-center gap-2 text-sm text-slate-700 cursor-pointer">
            <input v-model="removeBg" type="checkbox" class="accent-sycamore-600 w-4 h-4">
            Remove background (make it white)
          </label>

          <div v-if="removeBg" class="space-y-3">
            <div class="flex items-center gap-3">
              <span class="text-xs text-slate-400 whitespace-nowrap">Strength</span>
              <input
                v-model.number="sensitivity"
                type="range"
                min="5"
                max="90"
                step="1"
                class="flex-1 accent-sycamore-600"
              >
            </div>
            <div class="flex flex-col items-center gap-1">
              <span class="text-xs text-slate-400">Result preview</span>
              <div class="rounded-lg ring-1 ring-slate-200 overflow-hidden bg-white" :style="{ width: VIEW_W + 'px' }">
                <canvas ref="previewCanvas" class="block w-full h-auto"></canvas>
              </div>
            </div>
            <p class="text-xs text-slate-400 leading-relaxed">Works best when the background behind you is fairly plain. Increase the strength if some background is left, lower it if part of you disappears.</p>
          </div>
        </div>
      </div>

      <div class="px-5 py-4 border-t border-slate-100 flex justify-end gap-2 sticky bottom-0 bg-white">
        <button
          @click="emit('cancel')"
          class="px-4 py-2 rounded-lg bg-white border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50 transition-colors"
        >
          Cancel
        </button>
        <button
          @click="confirm"
          :disabled="!ready"
          class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700 disabled:opacity-50 transition-colors"
        >
          Use this photo
        </button>
      </div>
    </div>
  </div>
</template>
