<script setup lang="ts">
import type { PostMention } from '~/composables/useFeed'

const props = defineProps<{ content: string; mentions?: PostMention[] }>()

interface Part {
  text: string
  href?: string
}

const parts = computed<Part[]>(() => {
  const text = props.content || ''
  const mentions = (props.mentions || []).filter(m => m.full_name && m.staff_id)
  if (mentions.length === 0) return [{ text }]

  const sorted = [...mentions].sort((a, b) => b.full_name.length - a.full_name.length)
  const tokens: { needle: string; href: string }[] = sorted.map(m => ({
    needle: '@' + m.full_name,
    href: `/profile/${m.staff_id}`
  }))

  const out: Part[] = []
  let i = 0
  while (i < text.length) {
    let matched: { needle: string; href: string } | null = null
    if (text[i] === '@') {
      for (const t of tokens) {
        if (text.startsWith(t.needle, i)) { matched = t; break }
      }
    }
    if (matched) {
      out.push({ text: matched.needle, href: matched.href })
      i += matched.needle.length
    } else {
      const last = out[out.length - 1]
      if (last && !last.href) last.text += text[i]
      else out.push({ text: text[i] })
      i += 1
    }
  }
  return out
})
</script>

<template>
  <span class="whitespace-pre-line">
    <template v-for="(p, idx) in parts" :key="idx">
      <NuxtLink
        v-if="p.href"
        :to="p.href"
        class="text-sycamore-700 font-medium hover:underline"
        @click.stop
      >{{ p.text }}</NuxtLink>
      <template v-else>{{ p.text }}</template>
    </template>
  </span>
</template>
