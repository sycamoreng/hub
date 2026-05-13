import { useSupabase } from '~/utils/supabase'

export type AppointmentStatus =
  | 'scheduled'
  | 'checked_in'
  | 'in_meeting'
  | 'checked_out'
  | 'no_show'
  | 'cancelled'

export interface Appointment {
  id: string
  created_by_staff_id: string | null
  created_by_user_id: string | null
  location_id: string | null
  guest_name: string
  guest_company: string
  guest_email: string
  guest_phone: string
  guest_count: number
  purpose: string
  scheduled_date: string
  scheduled_start: string
  scheduled_end: string | null
  status: AppointmentStatus
  current_location_note: string
  checked_in_at: string | null
  checked_out_at: string | null
  host_notified_at: string | null
  badge_number: string
  notes: string
  created_at: string
  updated_at: string
  location?: { id: string; name: string; city: string | null } | null
  host?: { id: string; full_name: string; email: string | null; role: string | null } | null
}

export interface AppointmentEvent {
  id: string
  appointment_id: string
  actor_staff_id: string | null
  event_type: 'created' | 'status_changed' | 'location_updated' | 'note_added' | 'edited' | 'deleted'
  from_value: string
  to_value: string
  note: string
  created_at: string
  actor?: { id: string; full_name: string } | null
}

export const APPOINTMENT_STATUS_LABELS: Record<AppointmentStatus, string> = {
  scheduled: 'Scheduled',
  checked_in: 'Checked in',
  in_meeting: 'In meeting',
  checked_out: 'Checked out',
  no_show: 'No show',
  cancelled: 'Cancelled'
}

export const APPOINTMENT_STATUS_BADGE: Record<AppointmentStatus, string> = {
  scheduled: 'badge-slate',
  checked_in: 'badge-blue',
  in_meeting: 'badge-amber',
  checked_out: 'badge-green',
  no_show: 'badge-rose',
  cancelled: 'badge-slate'
}

const APPT_SELECT =
  '*, location:locations(id,name,city), host:staff_members!appointments_created_by_staff_id_fkey(id, full_name, email, role)'

export function useAppointments() {
  const supabase = useSupabase()

  async function loadAppointments(params: {
    onlyMine?: boolean
    myUserId?: string
    locationIds?: string[]
    fromDate?: string
    toDate?: string
    status?: AppointmentStatus | 'all'
    limit?: number
  } = {}): Promise<Appointment[]> {
    let q = supabase.from('appointments').select(APPT_SELECT)
    if (params.onlyMine && params.myUserId) q = q.eq('created_by_user_id', params.myUserId)
    if (params.locationIds && params.locationIds.length) q = q.in('location_id', params.locationIds)
    if (params.fromDate) q = q.gte('scheduled_date', params.fromDate)
    if (params.toDate) q = q.lte('scheduled_date', params.toDate)
    if (params.status && params.status !== 'all') q = q.eq('status', params.status)
    q = q.order('scheduled_date', { ascending: true }).order('scheduled_start', { ascending: true })
    if (params.limit) q = q.limit(params.limit)
    const { data, error } = await q
    if (error) throw error
    return (data ?? []) as any
  }

  async function getAppointment(id: string): Promise<Appointment | null> {
    const { data, error } = await supabase
      .from('appointments')
      .select(APPT_SELECT)
      .eq('id', id)
      .maybeSingle()
    if (error) throw error
    return data as any
  }

  async function createAppointment(input: Partial<Appointment>): Promise<Appointment> {
    const { data, error } = await supabase
      .from('appointments')
      .insert(input as any)
      .select(APPT_SELECT)
      .maybeSingle()
    if (error) throw error
    if (data) {
      await logEvent(data.id as string, {
        event_type: 'created',
        to_value: (data as any).status ?? 'scheduled',
        note: ''
      })
    }
    return data as any
  }

  async function updateAppointment(id: string, patch: Partial<Appointment>, eventNote = ''): Promise<Appointment> {
    const { data, error } = await supabase
      .from('appointments')
      .update(patch as any)
      .eq('id', id)
      .select(APPT_SELECT)
      .maybeSingle()
    if (error) throw error
    if (data) {
      await logEvent(id, { event_type: 'edited', note: eventNote || describePatch(patch) })
    }
    return data as any
  }

  async function changeStatus(id: string, from: AppointmentStatus, to: AppointmentStatus, patch: Partial<Appointment> = {}): Promise<Appointment> {
    const merged: Partial<Appointment> = { status: to, ...patch }
    const { data, error } = await supabase
      .from('appointments')
      .update(merged as any)
      .eq('id', id)
      .select(APPT_SELECT)
      .maybeSingle()
    if (error) throw error
    await logEvent(id, { event_type: 'status_changed', from_value: from, to_value: to })
    return data as any
  }

  async function updateCurrentLocation(id: string, fromNote: string, toNote: string): Promise<void> {
    const { error } = await supabase
      .from('appointments')
      .update({ current_location_note: toNote })
      .eq('id', id)
    if (error) throw error
    await logEvent(id, { event_type: 'location_updated', from_value: fromNote, to_value: toNote })
  }

  async function deleteAppointment(id: string): Promise<void> {
    await logEvent(id, { event_type: 'deleted', note: 'Appointment deleted' })
    const { error } = await supabase.from('appointments').delete().eq('id', id)
    if (error) throw error
  }

  async function loadEvents(appointmentId: string): Promise<AppointmentEvent[]> {
    const { data, error } = await supabase
      .from('appointment_events')
      .select('*, actor:staff_members!appointment_events_actor_staff_id_fkey(id, full_name)')
      .eq('appointment_id', appointmentId)
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []) as any
  }

  async function logEvent(appointmentId: string, payload: {
    event_type: AppointmentEvent['event_type']
    from_value?: string
    to_value?: string
    note?: string
  }): Promise<void> {
    const { data: userRes } = await supabase.auth.getUser()
    const uid = userRes?.user?.id
    let staffId: string | null = null
    if (uid) {
      const { data: staff } = await supabase
        .from('staff_members')
        .select('id')
        .eq('auth_user_id', uid)
        .maybeSingle()
      staffId = (staff as any)?.id ?? null
    }
    await supabase.from('appointment_events').insert({
      appointment_id: appointmentId,
      actor_user_id: uid ?? null,
      actor_staff_id: staffId,
      event_type: payload.event_type,
      from_value: payload.from_value ?? '',
      to_value: payload.to_value ?? '',
      note: payload.note ?? ''
    })
  }

  async function loadFrontDesk(): Promise<Array<{ id: string; staff_id: string; location_id: string | null; staff?: any; location?: any }>> {
    const { data, error } = await supabase
      .from('appointment_front_desk')
      .select('id, staff_id, location_id, staff:staff_members(id, full_name, email, role), location:locations(id, name, city)')
      .order('created_at', { ascending: false })
    if (error) throw error
    return (data ?? []) as any
  }

  async function addFrontDesk(staffId: string, locationId: string | null): Promise<void> {
    const { error } = await supabase
      .from('appointment_front_desk')
      .insert({ staff_id: staffId, location_id: locationId })
    if (error) throw error
  }

  async function removeFrontDesk(id: string): Promise<void> {
    const { error } = await supabase.from('appointment_front_desk').delete().eq('id', id)
    if (error) throw error
  }

  async function loadMyFrontDeskLocations(authUserId: string): Promise<{ all: boolean; locationIds: string[] }> {
    const { data: staff } = await supabase
      .from('staff_members')
      .select('id')
      .eq('auth_user_id', authUserId)
      .maybeSingle()
    const staffId = (staff as any)?.id
    if (!staffId) return { all: false, locationIds: [] }
    const { data } = await supabase
      .from('appointment_front_desk')
      .select('location_id')
      .eq('staff_id', staffId)
    const rows = (data ?? []) as any[]
    const all = rows.some(r => !r.location_id)
    const locationIds = rows.map(r => r.location_id).filter(Boolean)
    return { all, locationIds }
  }

  function describePatch(patch: Partial<Appointment>): string {
    const keys = Object.keys(patch)
    if (keys.length === 0) return ''
    if (keys.length === 1) return `Updated ${prettyField(keys[0])}`
    return `Updated ${keys.map(prettyField).join(', ')}`
  }

  function prettyField(key: string): string {
    return key.replace(/_/g, ' ')
  }

  return {
    loadAppointments,
    getAppointment,
    createAppointment,
    updateAppointment,
    changeStatus,
    updateCurrentLocation,
    deleteAppointment,
    loadEvents,
    loadFrontDesk,
    addFrontDesk,
    removeFrontDesk,
    loadMyFrontDeskLocations
  }
}
