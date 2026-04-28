import { u as useSupabase } from "./supabase-DXLNwiqO.js";
import { toRef, isRef, computed, readonly } from "vue";
import { b as useNuxtApp } from "../server.mjs";
const useStateKeyPrefix = "$s";
function useState(...args) {
  const autoKey = typeof args[args.length - 1] === "string" ? args.pop() : void 0;
  if (typeof args[0] !== "string") {
    args.unshift(autoKey);
  }
  const [_key, init] = args;
  if (!_key || typeof _key !== "string") {
    throw new TypeError("[nuxt] [useState] key must be a string: " + _key);
  }
  if (init !== void 0 && typeof init !== "function") {
    throw new Error("[nuxt] [useState] init must be a function: " + init);
  }
  const key = useStateKeyPrefix + _key;
  const nuxtApp = useNuxtApp();
  const state = toRef(nuxtApp.payload.state, key);
  if (state.value === void 0 && init) {
    const initialValue = init();
    if (isRef(initialValue)) {
      nuxtApp.payload.state[key] = initialValue;
      return initialValue;
    }
    state.value = initialValue;
  }
  return state;
}
const ALLOWED_EMAIL_DOMAINS = ["sycamore.ng", "sycamoreglobal.co.uk"];
function isEmailAllowed(email) {
  if (!email) return false;
  const domain = email.toLowerCase().split("@")[1];
  return ALLOWED_EMAIL_DOMAINS.includes(domain);
}
function useAuth() {
  const supabase = useSupabase();
  const user = useState("auth.user", () => null);
  const adminRecord = useState("auth.adminRecord", () => null);
  const ready = useState("auth.ready", () => false);
  const domainError = useState("auth.domainError", () => null);
  async function loadAdminRecord(email) {
    if (!email) {
      adminRecord.value = null;
      return;
    }
    const { data } = await supabase.from("admin_users").select("email, role, display_name, title, function, sections, permissions").eq("email", email.toLowerCase()).maybeSingle();
    if (data) {
      adminRecord.value = {
        ...data,
        permissions: data.permissions ?? {}
      };
    } else {
      adminRecord.value = null;
    }
  }
  async function enforceAllowedDomain(currentUser) {
    if (!currentUser) return true;
    if (isEmailAllowed(currentUser.email)) return true;
    const blocked = currentUser.email || "this account";
    await supabase.auth.signOut();
    user.value = null;
    adminRecord.value = null;
    domainError.value = `Sign-in restricted: ${blocked} is not on an allowed Sycamore domain. Please use a @${ALLOWED_EMAIL_DOMAINS[0]} or @${ALLOWED_EMAIL_DOMAINS[1]} account.`;
    return false;
  }
  async function init() {
    if (ready.value) return;
    const { data } = await supabase.auth.getSession();
    user.value = data.session?.user ?? null;
    const ok = await enforceAllowedDomain(user.value);
    if (ok) {
      await loadAdminRecord(user.value?.email);
    }
    supabase.auth.onAuthStateChange((_event, session) => {
      user.value = session?.user ?? null;
      (async () => {
        const allowed = await enforceAllowedDomain(user.value);
        if (allowed) {
          domainError.value = null;
          await loadAdminRecord(user.value?.email);
        }
      })();
    });
    ready.value = true;
  }
  async function signInWithGoogle(redirectPath = "/") {
    const redirectTo = void 0;
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo }
    });
    if (error) throw error;
  }
  async function signOut() {
    await supabase.auth.signOut();
    user.value = null;
    adminRecord.value = null;
  }
  const profile = computed(() => {
    const u = user.value;
    if (!u) return null;
    const meta = u.user_metadata ?? {};
    const name = meta.full_name || meta.name || [meta.given_name, meta.family_name].filter(Boolean).join(" ") || u.email || "";
    const email = u.email || meta.email || "";
    const avatarUrl = meta.avatar_url || meta.picture || "";
    const initials = (name || email).split(/[\s@]+/).filter(Boolean).slice(0, 2).map((s) => s[0]?.toUpperCase() ?? "").join("") || "?";
    return { name, email, avatarUrl, initials };
  });
  const isSuperAdmin = computed(() => adminRecord.value?.role === "super_admin");
  const isAdmin = computed(() => adminRecord.value !== null);
  function canPerform(section, action) {
    const rec = adminRecord.value;
    if (!rec) return false;
    if (rec.role === "super_admin") return true;
    return Boolean(rec.permissions?.[section]?.[action]);
  }
  function canManageSection(section) {
    return canPerform(section, "read");
  }
  return {
    user: readonly(user),
    ready: readonly(ready),
    profile,
    adminRecord: readonly(adminRecord),
    isAuthenticated: computed(() => user.value !== null),
    isAdmin,
    isSuperAdmin,
    canManageSection,
    canPerform,
    init,
    signInWithGoogle,
    signOut,
    domainError: readonly(domainError),
    clearDomainError: () => {
      domainError.value = null;
    },
    refreshAdmin: () => loadAdminRecord(user.value?.email)
  };
}
export {
  useAuth as u
};
//# sourceMappingURL=useAuth-DcwruT5Z.js.map
