import { useSupabase } from '~/utils/supabase'

export interface IdCardConfig {
  id: number
  front_template_url: string | null
  back_template_url: string | null
  photo_x: number
  photo_y: number
  photo_width: number
  photo_height: number
  photo_shape: 'rectangle' | 'circle'
  photo_fit: 'cover' | 'contain'
  photo_position: 'top' | 'center' | 'bottom'
  photo_anchor: 'top' | 'bottom'
  logo_url: string | null
  logo_show: boolean
  logo_x: number
  logo_y: number
  logo_width: number
  card_width_px: number
  card_height_px: number
  text_x: number
  text_y: number
  text_width: number
  text_align: 'left' | 'center' | 'right'
  text_color: string
  text_name_size: number
  text_email_size: number
  text_staff_id_size: number
  text_show_staff_id: boolean
  updated_at: string
}

export interface StaffIdCardPhoto {
  user_id: string
  photo_url: string
  updated_at: string
}

export const DEFAULT_ID_CARD_CONFIG: IdCardConfig = {
  id: 1,
  front_template_url: null,
  back_template_url: null,
  photo_x: 30,
  photo_y: 20,
  photo_width: 40,
  photo_height: 30,
  photo_shape: 'rectangle',
  photo_fit: 'cover',
  photo_position: 'center',
  photo_anchor: 'top',
  logo_url: '/sycamore-wordmark.png',
  logo_show: true,
  logo_x: 25,
  logo_y: 6,
  logo_width: 50,
  card_width_px: 400,
  card_height_px: 630,
  text_x: 5,
  text_y: 78,
  text_width: 90,
  text_align: 'center',
  text_color: '#0f2946',
  text_name_size: 26,
  text_email_size: 15,
  text_staff_id_size: 15,
  text_show_staff_id: true,
  updated_at: new Date().toISOString()
}

export function useIdCard() {
  const supabase = useSupabase()

  async function loadConfig(): Promise<IdCardConfig> {
    const { data } = await supabase
      .from('id_card_config')
      .select('*')
      .eq('id', 1)
      .maybeSingle()
    if (!data) return { ...DEFAULT_ID_CARD_CONFIG }
    return { ...DEFAULT_ID_CARD_CONFIG, ...(data as IdCardConfig) }
  }

  async function saveConfig(patch: Partial<Omit<IdCardConfig, 'id' | 'updated_at'>>): Promise<IdCardConfig> {
    const payload = { id: 1, ...patch, updated_at: new Date().toISOString() }
    const { data, error } = await supabase
      .from('id_card_config')
      .upsert(payload, { onConflict: 'id' })
      .select('*')
      .maybeSingle()
    if (error) throw error
    return { ...DEFAULT_ID_CARD_CONFIG, ...(data as IdCardConfig) }
  }

  async function loadMyPhoto(userId: string): Promise<StaffIdCardPhoto | null> {
    const { data } = await supabase
      .from('staff_id_card_photos')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle()
    return (data as StaffIdCardPhoto) ?? null
  }

  async function loadPhotosForUsers(userIds: string[]): Promise<Map<string, string>> {
    const map = new Map<string, string>()
    if (userIds.length === 0) return map
    const { data } = await supabase
      .from('staff_id_card_photos')
      .select('user_id, photo_url')
      .in('user_id', userIds)
    if (data) {
      for (const row of data as { user_id: string; photo_url: string }[]) {
        map.set(row.user_id, row.photo_url)
      }
    }
    return map
  }

  async function uploadImage(userId: string, folder: string, file: File): Promise<string> {
    const ext = (file.name.split('.').pop() || 'jpg').toLowerCase()
    const safeExt = ['jpg', 'jpeg', 'png', 'webp', 'gif'].includes(ext) ? ext : 'jpg'
    const path = `${userId}/${folder}/${Date.now()}.${safeExt}`
    const { error } = await supabase.storage.from('uploads').upload(path, file, { upsert: true })
    if (error) throw error
    const { data } = supabase.storage.from('uploads').getPublicUrl(path)
    return data.publicUrl
  }

  async function saveMyPhoto(userId: string, photoUrl: string): Promise<void> {
    const payload = { user_id: userId, photo_url: photoUrl, updated_at: new Date().toISOString() }
    const { error } = await supabase
      .from('staff_id_card_photos')
      .upsert(payload, { onConflict: 'user_id' })
    if (error) throw error
  }

  async function deleteMyPhoto(userId: string): Promise<void> {
    const { error } = await supabase
      .from('staff_id_card_photos')
      .delete()
      .eq('user_id', userId)
    if (error) throw error
  }

  return {
    loadConfig,
    saveConfig,
    loadMyPhoto,
    loadPhotosForUsers,
    uploadImage,
    saveMyPhoto,
    deleteMyPhoto
  }
}
