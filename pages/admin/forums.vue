<script setup lang="ts">
definePageMeta({ layout: 'admin', middleware: ['auth'] })
import { useSupabase } from '~/utils/supabase'

const supabase = useSupabase()
const toast = useToast()
const { log: auditLog } = useAuditLog()

interface Category {
  id: string
  name: string
  description: string
  slug: string
  icon: string
  color: string
  sort_order: number
  is_active: boolean
}

const loading = ref(true)
const categories = ref<Category[]>([])
const editing = ref<Category | null>(null)
const showForm = ref(false)

const form = ref({ name: '', description: '', slug: '', icon: '💬', color: '#3087b9', sort_order: 0, is_active: true })

async function load() {
  loading.value = true
  const { data } = await supabase
    .from('forum_categories')
    .select('*')
    .order('sort_order')
  categories.value = (data ?? []) as Category[]
  loading.value = false
}

function openNew() {
  editing.value = null
  form.value = { name: '', description: '', slug: '', icon: '💬', color: '#3087b9', sort_order: categories.value.length + 1, is_active: true }
  showForm.value = true
}

function openEdit(cat: Category) {
  editing.value = cat
  form.value = { name: cat.name, description: cat.description, slug: cat.slug, icon: cat.icon, color: cat.color, sort_order: cat.sort_order, is_active: cat.is_active }
  showForm.value = true
}

function slugify(text: string) {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')
}

watch(() => form.value.name, (val) => {
  if (!editing.value) form.value.slug = slugify(val)
})

async function save() {
  if (!form.value.name.trim()) { toast.error('Name is required'); return }
  if (!form.value.slug.trim()) { toast.error('Slug is required'); return }

  if (editing.value) {
    const { error } = await supabase
      .from('forum_categories')
      .update({
        name: form.value.name,
        description: form.value.description,
        slug: form.value.slug,
        icon: form.value.icon,
        color: form.value.color,
        sort_order: form.value.sort_order,
        is_active: form.value.is_active
      })
      .eq('id', editing.value.id)
    if (error) { toast.error(error.message); return }
    auditLog({ action: 'update_forum_category', target_type: 'forum_category', target_label: form.value.name })
    toast.success('Category updated')
  } else {
    const { error } = await supabase
      .from('forum_categories')
      .insert({
        name: form.value.name,
        description: form.value.description,
        slug: form.value.slug,
        icon: form.value.icon,
        color: form.value.color,
        sort_order: form.value.sort_order,
        is_active: form.value.is_active
      })
    if (error) { toast.error(error.message); return }
    auditLog({ action: 'create_forum_category', target_type: 'forum_category', target_label: form.value.name })
    toast.success('Category created')
  }
  showForm.value = false
  await load()
}

async function toggleActive(cat: Category) {
  await supabase.from('forum_categories').update({ is_active: !cat.is_active }).eq('id', cat.id)
  cat.is_active = !cat.is_active
  toast.success(cat.is_active ? 'Category activated' : 'Category hidden')
}

await load()
</script>

<template>
  <div class="max-w-3xl mx-auto">
    <div class="flex items-center justify-between mb-6">
      <div>
        <h1 class="text-2xl font-bold text-slate-900">Forum Categories</h1>
        <p class="text-sm text-slate-500 mt-1">Manage discussion categories for the forums</p>
      </div>
      <button @click="openNew" class="btn-primary">Add Category</button>
    </div>

    <div v-if="loading" class="card p-12 text-center text-slate-400">Loading...</div>

    <div v-else class="space-y-2">
      <div
        v-for="cat in categories"
        :key="cat.id"
        class="card p-4 flex items-center gap-4 transition-all"
        :class="cat.is_active ? '' : 'opacity-50'"
      >
        <div
          class="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
          :style="{ backgroundColor: cat.color + '18' }"
        >{{ cat.icon }}</div>
        <div class="flex-1 min-w-0">
          <h3 class="font-semibold text-slate-900 text-sm">{{ cat.name }}</h3>
          <p class="text-xs text-slate-500 truncate">{{ cat.description }}</p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <button @click="toggleActive(cat)" class="text-xs px-2 py-1 rounded hover:bg-slate-100 text-slate-500">
            {{ cat.is_active ? 'Hide' : 'Show' }}
          </button>
          <button @click="openEdit(cat)" class="text-xs px-2 py-1 rounded hover:bg-slate-100 text-slate-600 font-medium">
            Edit
          </button>
        </div>
      </div>
      <p v-if="categories.length === 0" class="text-center py-10 text-slate-400 text-sm">No categories yet.</p>
    </div>

    <!-- Form Modal -->
    <div v-if="showForm" class="fixed inset-0 bg-black/50 backdrop-blur-sm flex items-center justify-center z-50 p-4" @click.self="showForm = false">
      <div class="bg-white rounded-2xl shadow-2xl w-full max-w-md">
        <div class="flex items-center justify-between p-5 border-b">
          <h2 class="text-lg font-bold text-slate-900">{{ editing ? 'Edit' : 'New' }} Category</h2>
          <button @click="showForm = false" class="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-5 h-5"><path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" /></svg>
          </button>
        </div>
        <div class="p-5 space-y-4">
          <div class="grid grid-cols-[auto_1fr] gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Icon</label>
              <input v-model="form.icon" class="input w-14 text-center text-lg" maxlength="4" />
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Name</label>
              <input v-model="form.name" class="input" placeholder="e.g. General Discussion" />
            </div>
          </div>
          <div>
            <label class="block text-xs font-medium text-slate-600 mb-1">Description</label>
            <input v-model="form.description" class="input" placeholder="Short description" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Slug</label>
              <input v-model="form.slug" class="input" placeholder="url-slug" />
            </div>
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Color</label>
              <input v-model="form.color" type="color" class="input h-9 p-1" />
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-xs font-medium text-slate-600 mb-1">Sort Order</label>
              <input v-model.number="form.sort_order" type="number" class="input" />
            </div>
            <div class="flex items-end pb-1">
              <label class="flex items-center gap-2 cursor-pointer">
                <input type="checkbox" v-model="form.is_active" class="form-checkbox h-4 w-4 rounded border-slate-300 text-sycamore-600">
                <span class="text-sm text-slate-700">Active</span>
              </label>
            </div>
          </div>
        </div>
        <div class="flex justify-end gap-2 p-5 border-t">
          <button @click="showForm = false" class="btn-secondary">Cancel</button>
          <button @click="save" class="btn-primary">{{ editing ? 'Save' : 'Create' }}</button>
        </div>
      </div>
    </div>
  </div>
</template>
