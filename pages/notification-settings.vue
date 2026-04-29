<script setup lang="ts">
definePageMeta({ middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const { user } = useAuth()
const supabase = useSupabase()
const toast = useToast()

const prefs = ref<any>(null)
const loading = ref(true)
const saving = ref(false)

async function load() {
  if (!user.value) return
  loading.value = true
  const { data } = await supabase
    .from('notification_preferences')
    .select('*')
    .eq('user_id', user.value.id)
    .maybeSingle()
  if (data) {
    prefs.value = data
  } else {
    const { data: created } = await supabase
      .from('notification_preferences')
      .insert({ user_id: user.value.id })
      .select('*')
      .maybeSingle()
    prefs.value = created
  }
  loading.value = false
}

watch(user, () => load(), { immediate: true })

async function save() {
  if (!prefs.value) return
  saving.value = true
  try {
    const payload = {
      email_mentions: !!prefs.value.email_mentions,
      email_announcements: !!prefs.value.email_announcements,
      email_weekly_digest: !!prefs.value.email_weekly_digest,
      email_event_reminders: !!prefs.value.email_event_reminders,
      email_broadcasts: !!prefs.value.email_broadcasts,
      updated_at: new Date().toISOString()
    }
    await supabase.from('notification_preferences').update(payload).eq('id', prefs.value.id)
    toast.success('Preferences saved')
  } catch (e: any) {
    toast.error(e.message ?? 'Failed to save')
  } finally {
    saving.value = false
  }
}

const options = computed(() => [
  { key: 'email_mentions', label: 'When someone mentions me', hint: 'Posts and announcements that @ mention you.' },
  { key: 'email_announcements', label: 'New company announcements', hint: 'Only when an admin opts to email an announcement.' },
  { key: 'email_event_reminders', label: 'Upcoming holidays & events', hint: 'Reminders a few days before an event.' },
  { key: 'email_weekly_digest', label: 'Weekly activity roundup', hint: 'A Monday summary of the past week on the Hub.' },
  { key: 'email_broadcasts', label: 'Admin broadcasts', hint: 'One-off emails your admins send to staff.' }
])
</script>

<template>
  <div class="max-w-2xl mx-auto py-10 px-4 space-y-6">
    <header>
      <h1 class="text-2xl font-bold text-slate-900">Email notifications</h1>
      <p class="text-sm text-slate-500 mt-1">Choose which emails from the Hub land in your inbox. You can change these any time.</p>
    </header>

    <div v-if="loading" class="text-sm text-slate-400">Loading...</div>
    <section v-else-if="prefs" class="card p-6 divide-y divide-slate-100">
      <label v-for="o in options" :key="o.key" class="flex items-start justify-between gap-4 py-4 first:pt-0 last:pb-0 cursor-pointer">
        <div class="min-w-0">
          <div class="text-sm font-medium text-slate-900">{{ o.label }}</div>
          <div class="text-xs text-slate-500 mt-0.5">{{ o.hint }}</div>
        </div>
        <input type="checkbox" v-model="prefs[o.key]" class="mt-1 w-5 h-5 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-300" />
      </label>
    </section>

    <div class="flex justify-end">
      <button class="btn-primary" :disabled="saving" @click="save"><span v-if="saving">Saving...</span><span v-else>Save preferences</span></button>
    </div>
  </div>
</template>
