import { _ as _sfc_main$1 } from './SidebarIcon-B7VkmqYS.mjs';
import { defineComponent, ref, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent, ssrInterpolate, ssrRenderAttr, ssrIncludeBooleanAttr, ssrRenderList, ssrLooseContain, ssrLooseEqual, ssrRenderClass } from 'vue/server-renderer';
import { u as useSupabase } from './supabase-DXLNwiqO.mjs';
import { u as useAuth } from './useAuth-DcwruT5Z.mjs';
import '@supabase/supabase-js';
import './server.mjs';
import '../nitro/nitro.mjs';
import 'node:http';
import 'node:https';
import 'node:events';
import 'node:buffer';
import 'node:fs';
import 'node:path';
import 'node:crypto';
import 'node:url';
import '../routes/renderer.mjs';
import 'vue-bundle-renderer/runtime';
import 'unhead/server';
import 'devalue';
import 'unhead/utils';
import 'unhead/plugins';
import 'vue-router';

const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "admins",
  __ssrInlineRender: true,
  setup(__props) {
    const SECTIONS = [
      { key: "onboarding", label: "Onboarding" },
      { key: "products", label: "Products" },
      { key: "technology", label: "Technology" },
      { key: "chatbot", label: "Chatbot" },
      { key: "announcements", label: "Announcements" },
      { key: "events", label: "Events & Holidays" },
      { key: "policies", label: "Policies" },
      { key: "staff", label: "Staff" },
      { key: "leadership", label: "Leadership" },
      { key: "departments", label: "Departments" },
      { key: "locations", label: "Locations" },
      { key: "contacts", label: "Key Contacts" },
      { key: "communication", label: "Communication" },
      { key: "branding", label: "Branding" },
      { key: "benefits", label: "Benefits" },
      { key: "company", label: "Company Info" }
    ];
    const ACTIONS = ["create", "read", "update", "delete"];
    useSupabase();
    const { profile } = useAuth();
    const admins = ref([]);
    const presets = ref([]);
    const loading = ref(true);
    const error = ref(null);
    const saving = ref(false);
    const showForm = ref(false);
    const editingEmail = ref(null);
    const form = ref({
      email: "",
      role: "admin",
      display_name: "",
      title: "",
      function: "",
      permissions: {},
      presetId: ""
    });
    function permissionFor(section) {
      return form.value.permissions[section] || {};
    }
    function summarisePermissions(perms) {
      if (!perms) return "None";
      const keys = Object.keys(perms);
      if (!keys.length) return "None";
      return keys.map((k) => {
        var _a;
        const label = ((_a = SECTIONS.find((s) => s.key === k)) == null ? void 0 : _a.label) || k;
        const enabled = ACTIONS.filter((a) => {
          var _a2;
          return (_a2 = perms[k]) == null ? void 0 : _a2[a];
        }).map((a) => a[0].toUpperCase()).join("");
        return `${label} (${enabled || "-"})`;
      }).join(", ");
    }
    function sectionPermissionCount(section) {
      return ACTIONS.filter((a) => permissionFor(section)[a]).length;
    }
    return (_ctx, _push, _parent, _attrs) => {
      var _a;
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl" }, _attrs))}><div class="flex items-start justify-between gap-4 mb-8"><div><h1 class="section-title">Admin Access</h1><p class="section-subtitle">Grant admin permissions by department role and fine-tune CRUD rights per section.</p></div><button class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-semibold hover:bg-sycamore-700 inline-flex items-center gap-2">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "plus" }, null, _parent));
      _push(` Add admin </button></div>`);
      if (unref(error)) {
        _push(`<div class="mb-4 p-3 rounded-lg bg-rose-50 border border-rose-200 text-rose-700 text-sm">${ssrInterpolate(unref(error))}</div>`);
      } else {
        _push(`<!---->`);
      }
      if (unref(showForm)) {
        _push(`<div class="card p-6 mb-6"><h2 class="font-bold text-slate-900 mb-4">${ssrInterpolate(unref(editingEmail) ? "Edit admin" : "New admin")}</h2><div class="grid sm:grid-cols-2 gap-4"><div><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Email</label><input${ssrRenderAttr("value", unref(form).email)} type="email"${ssrIncludeBooleanAttr(!!unref(editingEmail)) ? " disabled" : ""} placeholder="user@sycamore.ng" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500 disabled:bg-slate-50"></div><div><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Apply role preset</label><select${ssrRenderAttr("value", unref(form).presetId)} class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500"><option value="">Custom (no preset)</option><!--[-->`);
        ssrRenderList(unref(presets), (p) => {
          _push(`<option${ssrRenderAttr("value", p.id)}>${ssrInterpolate(p.name)}</option>`);
        });
        _push(`<!--]--></select>`);
        if (unref(form).presetId) {
          _push(`<p class="text-xs text-slate-500 mt-1">${ssrInterpolate((_a = unref(presets).find((p) => p.id === unref(form).presetId)) == null ? void 0 : _a.description)}</p>`);
        } else {
          _push(`<!---->`);
        }
        _push(`</div><div><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Display name</label><input${ssrRenderAttr("value", unref(form).display_name)} type="text" placeholder="Jane Doe" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500"></div><div><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Title</label><input${ssrRenderAttr("value", unref(form).title)} type="text" placeholder="Head of HR" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500"></div><div><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Function / department</label><input${ssrRenderAttr("value", unref(form).function)} type="text" placeholder="Human Resources" class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500"></div><div><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Role</label><select class="mt-1 w-full px-3 py-2 rounded-lg border border-slate-300 focus:outline-none focus:ring-2 focus:ring-sycamore-500"><option value="admin"${ssrIncludeBooleanAttr(Array.isArray(unref(form).role) ? ssrLooseContain(unref(form).role, "admin") : ssrLooseEqual(unref(form).role, "admin")) ? " selected" : ""}>Admin (granular permissions)</option><option value="super_admin"${ssrIncludeBooleanAttr(Array.isArray(unref(form).role) ? ssrLooseContain(unref(form).role, "super_admin") : ssrLooseEqual(unref(form).role, "super_admin")) ? " selected" : ""}>Super admin (full access)</option></select></div></div>`);
        if (unref(form).role === "admin") {
          _push(`<div class="mt-6"><div class="flex items-center justify-between mb-3"><label class="text-xs font-semibold text-slate-600 uppercase tracking-wide">Section permissions</label><span class="text-xs text-slate-400">C = Create \xB7 R = Read \xB7 U = Update \xB7 D = Delete</span></div><div class="overflow-x-auto rounded-lg border border-slate-200"><table class="w-full text-sm"><thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500"><tr><th class="text-left p-3">Section</th><!--[-->`);
          ssrRenderList(ACTIONS, (a) => {
            _push(`<th class="text-center p-3 capitalize">${ssrInterpolate(a)}</th>`);
          });
          _push(`<!--]--><th class="text-right p-3"></th></tr></thead><tbody><!--[-->`);
          ssrRenderList(SECTIONS, (s) => {
            _push(`<tr class="${ssrRenderClass([{ "bg-sycamore-50/40": sectionPermissionCount(s.key) > 0 }, "border-t border-slate-100"])}"><td class="p-3 font-medium text-slate-700">${ssrInterpolate(s.label)}</td><!--[-->`);
            ssrRenderList(ACTIONS, (a) => {
              _push(`<td class="text-center p-3"><input type="checkbox"${ssrIncludeBooleanAttr(!!permissionFor(s.key)[a]) ? " checked" : ""} class="accent-sycamore-600 w-4 h-4"></td>`);
            });
            _push(`<!--]--><td class="p-3 text-right whitespace-nowrap"><button type="button" class="text-xs text-sycamore-700 hover:underline mr-3">Full</button><button type="button" class="text-xs text-slate-500 hover:underline">Clear</button></td></tr>`);
          });
          _push(`<!--]--></tbody></table></div></div>`);
        } else {
          _push(`<div class="mt-4 p-3 rounded-lg bg-amber-50 border border-amber-200 text-sm text-amber-800"> Super admins have full access to every section, including managing other admins and role presets. </div>`);
        }
        _push(`<div class="flex items-center justify-end gap-3 mt-6"><button class="px-4 py-2 rounded-lg border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50">Cancel</button><button${ssrIncludeBooleanAttr(unref(saving)) ? " disabled" : ""} class="px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-semibold hover:bg-sycamore-700 disabled:opacity-60">${ssrInterpolate(unref(saving) ? "Saving..." : unref(editingEmail) ? "Save changes" : "Add admin")}</button></div></div>`);
      } else {
        _push(`<!---->`);
      }
      _push(`<div class="card overflow-hidden">`);
      if (unref(loading)) {
        _push(`<div class="p-10 text-center text-slate-500">Loading admins...</div>`);
      } else {
        _push(`<table class="w-full text-sm"><thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500"><tr><th class="text-left p-4">User</th><th class="text-left p-4">Role</th><th class="text-left p-4">Function</th><th class="text-left p-4">Permissions</th><th class="text-right p-4">Actions</th></tr></thead><tbody><!--[-->`);
        ssrRenderList(unref(admins), (row) => {
          var _a2;
          _push(`<tr class="border-t border-slate-100 align-top"><td class="p-4"><div class="font-semibold text-slate-900">${ssrInterpolate(row.display_name || row.email.split("@")[0])}</div><div class="text-xs text-slate-500">${ssrInterpolate(row.email)}</div>`);
          if (row.title) {
            _push(`<div class="text-xs text-slate-400 mt-0.5">${ssrInterpolate(row.title)}</div>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</td><td class="p-4"><span class="${ssrRenderClass([row.role === "super_admin" ? "bg-amber-50 text-amber-700" : "bg-sycamore-50 text-sycamore-700", "inline-flex px-2 py-1 rounded-full text-xs font-medium"])}">${ssrInterpolate(row.role === "super_admin" ? "Super admin" : "Admin")}</span></td><td class="p-4 text-slate-600">${ssrInterpolate(row.function || "-")}</td><td class="p-4 text-slate-600 max-w-md text-xs leading-relaxed">`);
          if (row.role === "super_admin") {
            _push(`<span class="text-amber-700 font-medium">All sections, full CRUD</span>`);
          } else {
            _push(`<span>${ssrInterpolate(summarisePermissions(row.permissions))}</span>`);
          }
          _push(`</td><td class="p-4 text-right whitespace-nowrap"><button class="text-sycamore-700 hover:underline text-xs font-semibold mr-3">Edit</button><button${ssrIncludeBooleanAttr(row.email === ((_a2 = unref(profile)) == null ? void 0 : _a2.email)) ? " disabled" : ""} class="text-rose-600 hover:underline text-xs font-semibold disabled:opacity-40 disabled:no-underline disabled:cursor-not-allowed"> Remove </button></td></tr>`);
        });
        _push(`<!--]-->`);
        if (!unref(admins).length) {
          _push(`<tr><td colspan="5" class="p-10 text-center text-slate-500">No admins configured.</td></tr>`);
        } else {
          _push(`<!---->`);
        }
        _push(`</tbody></table>`);
      }
      _push(`</div><div class="mt-10"><h2 class="text-lg font-bold text-slate-900 mb-1">Default role presets</h2><p class="text-sm text-slate-500 mb-4">Pre-built permission templates for common departments. Apply them when adding or editing an admin.</p><div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4"><!--[-->`);
      ssrRenderList(unref(presets), (p) => {
        _push(`<div class="card p-5"><div class="flex items-center justify-between mb-1"><div class="font-semibold text-slate-900">${ssrInterpolate(p.name)}</div>`);
        if (p.is_default) {
          _push(`<span class="text-[10px] px-2 py-0.5 rounded-full bg-slate-100 text-slate-500 uppercase tracking-wide">Default</span>`);
        } else {
          _push(`<!---->`);
        }
        _push(`</div><p class="text-xs text-slate-500 mb-3">${ssrInterpolate(p.description)}</p><div class="text-xs text-slate-600 leading-relaxed">${ssrInterpolate(summarisePermissions(p.permissions))}</div></div>`);
      });
      _push(`<!--]--></div></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/admins.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=admins-CGdem1Wd.mjs.map
