<script setup lang="ts">
import { findTemplate, type PostMention, type PostRow } from '~/composables/useFeed'

const props = defineProps<{
  post: PostRow
  authorName?: string
  authorAvatar?: string | null
  authorStaffId?: string | null
  authorInitials?: string
  mentions?: PostMention[]
  formattedTime?: string
  variant?: 'feed' | 'compact'
}>()

const emit = defineEmits<{ (e: 'delete'): void }>()

const template = computed(() => findTemplate(props.post.post_kind))
const variant = computed(() => props.variant ?? 'feed')

const showHeaderBanner = computed(() => !!template.value)
</script>

<template>
  <article class="card overflow-hidden">
    <div
      v-if="showHeaderBanner && template"
      :class="['px-5 py-3 text-white text-xs font-semibold tracking-wide uppercase flex items-center gap-2 bg-gradient-to-r', template.accent]"
    >
      <span class="text-base leading-none">{{ template.emoji }}</span>
      <span>{{ template.badge }}</span>
      <span v-if="post.template_data?.years" class="ml-auto bg-white/20 rounded-full px-2 py-0.5 text-[10px]">{{ post.template_data.years }} yrs</span>
    </div>

    <div class="p-5">
      <div class="flex items-start gap-3">
        <NuxtLink
          v-if="authorStaffId"
          :to="`/profile/${authorStaffId}`"
          class="flex-shrink-0"
        >
          <img
            v-if="authorAvatar"
            :src="authorAvatar"
            :alt="authorName"
            referrerpolicy="no-referrer"
            class="w-11 h-11 rounded-full object-cover border border-slate-200"
          />
          <div v-else class="w-11 h-11 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-sm font-semibold">
            {{ authorInitials || '?' }}
          </div>
        </NuxtLink>
        <div v-else class="flex-shrink-0">
          <img
            v-if="authorAvatar"
            :src="authorAvatar"
            :alt="authorName"
            referrerpolicy="no-referrer"
            class="w-11 h-11 rounded-full object-cover border border-slate-200"
          />
          <div v-else class="w-11 h-11 rounded-full bg-sycamore-100 text-sycamore-700 flex items-center justify-center text-sm font-semibold">
            {{ authorInitials || '?' }}
          </div>
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex items-center justify-between gap-3">
            <div class="min-w-0">
              <NuxtLink
                v-if="authorStaffId"
                :to="`/profile/${authorStaffId}`"
                class="font-semibold text-slate-900 text-sm hover:text-sycamore-700 truncate"
              >{{ authorName }}</NuxtLink>
              <span v-else class="font-semibold text-slate-900 text-sm truncate">
                {{ authorName || 'Sycamore staff' }}
              </span>
              <div class="text-xs text-slate-400">{{ formattedTime }}</div>
            </div>
            <slot name="actions" />
          </div>

          <PostBody class="block text-sm text-slate-700 mt-2" :content="post.content" :mentions="mentions" />

          <figure v-if="post.image_url" class="mt-3 -mx-1 overflow-hidden rounded-xl border border-slate-100">
            <img :src="post.image_url" :alt="''" class="w-full max-h-[28rem] object-cover" />
          </figure>

          <slot name="footer" />
        </div>
      </div>
    </div>
  </article>
</template>
