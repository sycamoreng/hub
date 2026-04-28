import { u as useSupabase } from './supabase-DXLNwiqO.mjs';

function useCompanyData() {
  const supabase = useSupabase();
  async function fetchCompanyInfo() {
    const { data, error } = await supabase.from("company_info").select("*").order("display_order", { ascending: true });
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchDepartments() {
    const { data, error } = await supabase.from("departments").select("*, staff_members(count)").order("name");
    if (error) throw error;
    return (data != null ? data : []).map((d) => {
      var _a, _b, _c;
      return {
        ...d,
        staff_count: (_c = (_b = (_a = d.staff_members) == null ? void 0 : _a[0]) == null ? void 0 : _b.count) != null ? _c : 0
      };
    });
  }
  async function fetchLocations() {
    const { data, error } = await supabase.from("locations").select("*, staff_members(count)").order("is_headquarters", { ascending: false }).order("name");
    if (error) throw error;
    return (data != null ? data : []).map((l) => {
      var _a, _b, _c;
      return {
        ...l,
        staff_count: (_c = (_b = (_a = l.staff_members) == null ? void 0 : _a[0]) == null ? void 0 : _b.count) != null ? _c : 0
      };
    });
  }
  async function fetchStaff() {
    const { data, error } = await supabase.from("staff_members").select("*, departments(name), locations(name, city)").eq("is_active", true).order("full_name");
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchPolicies() {
    const { data, error } = await supabase.from("policies").select("*").eq("is_active", true).order("category").order("title");
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchCommunicationTools() {
    const { data, error } = await supabase.from("communication_tools").select("*").order("is_primary", { ascending: false }).order("name");
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchBrandingGuidelines() {
    const { data, error } = await supabase.from("branding_guidelines").select("*").order("display_order");
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchBenefits() {
    const { data, error } = await supabase.from("benefits_perks").select("*").order("display_order").order("title");
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchKeyContacts() {
    const { data, error } = await supabase.from("key_contacts").select("*").order("is_emergency", { ascending: false }).order("name");
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchAnnouncements() {
    const { data, error } = await supabase.from("announcements").select("*").eq("is_active", true).order("created_at", { ascending: false });
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchOnboardingSteps() {
    const { data, error } = await supabase.from("onboarding_steps").select("*").eq("is_active", true).order("display_order", { ascending: true }).order("title", { ascending: true });
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchProducts() {
    const { data, error } = await supabase.from("products").select("*").eq("is_active", true).order("display_order", { ascending: true }).order("name", { ascending: true });
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchTechStack() {
    const { data, error } = await supabase.from("tech_stack").select("*").eq("is_active", true).order("category", { ascending: true }).order("display_order", { ascending: true }).order("name", { ascending: true });
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchLeadership() {
    const { data, error } = await supabase.from("leadership").select("*").eq("is_active", true).order("display_order", { ascending: true }).order("full_name", { ascending: true });
    if (error) throw error;
    return data != null ? data : [];
  }
  async function fetchHolidaysEvents() {
    const { data, error } = await supabase.from("holidays_events").select("*").order("event_date");
    if (error) throw error;
    return data != null ? data : [];
  }
  return {
    fetchCompanyInfo,
    fetchDepartments,
    fetchLocations,
    fetchStaff,
    fetchPolicies,
    fetchCommunicationTools,
    fetchBrandingGuidelines,
    fetchBenefits,
    fetchKeyContacts,
    fetchAnnouncements,
    fetchHolidaysEvents,
    fetchLeadership,
    fetchOnboardingSteps,
    fetchProducts,
    fetchTechStack
  };
}

export { useCompanyData as u };
//# sourceMappingURL=useCompanyData-CSkVUIju.mjs.map
