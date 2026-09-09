<script setup lang="ts">
import type { IdCardConfig } from '~/composables/useIdCard'

const props = defineProps<{
  config: IdCardConfig
  side: 'front' | 'back'
  photoUrl?: string | null
  fullName?: string | null
  email?: string | null
  staffId?: string | null
  scale?: number
}>()

const scale = computed(() => props.scale ?? 1)
const width = computed(() => Math.round(props.config.card_width_px * scale.value))
const height = computed(() => Math.round(props.config.card_height_px * scale.value))
const templateUrl = computed(() =>
  props.side === 'front' ? props.config.front_template_url : props.config.back_template_url
)

const photoStyle = computed(() => {
  const c = props.config
  const style: Record<string, string> = {
    left: `${c.photo_x}%`,
    width: `${c.photo_width}%`,
    height: `${c.photo_height}%`
  }
  if (c.photo_anchor === 'bottom') {
    style.bottom = `${100 - c.photo_y}%`
  } else {
    style.top = `${c.photo_y}%`
  }
  if (c.photo_shape === 'circle') style.borderRadius = '50%'
  return style
})

const photoImgClass = computed(() =>
  props.config.photo_fit === 'contain' ? 'w-full h-full object-contain' : 'w-full h-full object-cover'
)

const photoImgStyle = computed(() => ({
  objectPosition: `center ${props.config.photo_position ?? 'center'}`
}))

const logoStyle = computed(() => {
  const c = props.config
  return {
    left: `${c.logo_x}%`,
    top: `${c.logo_y}%`,
    width: `${c.logo_width}%`
  } as Record<string, string>
})

const sizeRatio = computed(() => width.value / (props.config.card_width_px || 400))

const textBoxStyle = computed(() => {
  const c = props.config
  return {
    left: `${c.text_x}%`,
    top: `${c.text_y}%`,
    width: `${c.text_width}%`,
    color: c.text_color,
    textAlign: c.text_align
  } as Record<string, string>
})

const nameStyle = computed(() => ({
  fontSize: `${props.config.text_name_size * sizeRatio.value}px`,
  lineHeight: 1.15,
  fontWeight: 700
}))
const emailStyle = computed(() => ({
  fontSize: `${props.config.text_email_size * sizeRatio.value}px`,
  lineHeight: 1.25,
  fontWeight: 500
}))
const staffIdStyle = computed(() => ({
  fontSize: `${props.config.text_staff_id_size * sizeRatio.value}px`,
  lineHeight: 1.25,
  fontWeight: 500
}))

const gapPx = computed(() => Math.max(4, Math.round(8 * sizeRatio.value)))
</script>

<template>
  <div
    class="relative rounded-xl overflow-hidden bg-slate-200 shadow-lg"
    :style="{ width: width + 'px', height: height + 'px' }"
  >
    <img
      v-if="templateUrl"
      :src="templateUrl"
      :alt="`ID card ${side}`"
      class="absolute inset-0 w-full h-full object-cover select-none pointer-events-none"
      draggable="false"
    >
    <div
      v-else
      class="absolute inset-0 flex items-center justify-center text-xs font-medium text-slate-500 bg-gradient-to-br from-slate-100 to-slate-200"
    >
      {{ side === 'front' ? 'Front template not uploaded yet' : 'Back template not uploaded yet' }}
    </div>

    <template v-if="side === 'front'">
      <img
        v-if="config.logo_show && config.logo_url"
        :src="config.logo_url"
        alt="Company logo"
        class="absolute h-auto object-contain select-none pointer-events-none"
        :style="logoStyle"
        draggable="false"
      >

      <div
        class="absolute overflow-hidden bg-white ring-1 ring-slate-300/70"
        :style="photoStyle"
      >
        <img
          v-if="photoUrl"
          :src="photoUrl"
          alt="Staff photo"
          :class="photoImgClass"
          :style="photoImgStyle"
          draggable="false"
        >
        <div
          v-else
          class="w-full h-full flex items-center justify-center text-[10px] font-medium text-slate-600 text-center px-1"
        >
          Photo goes here
        </div>
      </div>

      <div
        class="absolute pointer-events-none flex flex-col items-stretch"
        :style="textBoxStyle"
      >
        <div :style="nameStyle" class="truncate">
          {{ fullName || 'Full Name' }}
        </div>
        <div :style="{ ...emailStyle, marginTop: gapPx + 'px' }" class="truncate">
          {{ email || 'name@sycamore.ng' }}
        </div>
        <div
          v-if="config.text_show_staff_id"
          :style="{ ...staffIdStyle, marginTop: (gapPx * 2) + 'px' }"
          class="truncate"
        >
          {{ staffId || 'SISL-0000-000' }}
        </div>
      </div>
    </template>
  </div>
</template>
