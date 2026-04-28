import { _ as __nuxt_component_0 } from "./nuxt-link-nIAPCTWv.js";
import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, mergeProps, withCtx, unref, createVNode, toDisplayString, createTextVNode, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderList, ssrRenderComponent, ssrInterpolate } from "vue/server-renderer";
import { u as useSupabase } from "./supabase-DXLNwiqO.js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ufo/dist/index.mjs";
import "../server.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ofetch/dist/node.mjs";
import "#internal/nuxt/paths";
import "/Users/macbookpro/Documents/work/intranet/node_modules/unctx/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/h3/dist/index.mjs";
import "vue-router";
import "/Users/macbookpro/Documents/work/intranet/node_modules/defu/dist/defu.mjs";
import "@supabase/supabase-js";
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "index",
  __ssrInlineRender: true,
  setup(__props) {
    useSupabase();
    const counts = ref({});
    ref(true);
    const tables = [
      { table: "onboarding_steps", label: "Onboarding", to: "/admin/onboarding", icon: "check" },
      { table: "products", label: "Products", to: "/admin/products", icon: "gift" },
      { table: "tech_stack", label: "Technology", to: "/admin/technology", icon: "palette" },
      { table: "announcements", label: "Announcements", to: "/admin/announcements", icon: "info" },
      { table: "holidays_events", label: "Events & Holidays", to: "/admin/events", icon: "calendar" },
      { table: "policies", label: "Policies", to: "/admin/policies", icon: "book" },
      { table: "staff_members", label: "Staff", to: "/admin/staff", icon: "users" },
      { table: "leadership", label: "Leadership", to: "/admin/leadership", icon: "star" },
      { table: "departments", label: "Departments", to: "/admin/departments", icon: "building" },
      { table: "locations", label: "Locations", to: "/admin/locations", icon: "map" },
      { table: "key_contacts", label: "Key Contacts", to: "/admin/contacts", icon: "phone" },
      { table: "communication_tools", label: "Communication", to: "/admin/communication", icon: "chat" },
      { table: "branding_guidelines", label: "Branding", to: "/admin/branding", icon: "palette" },
      { table: "benefits_perks", label: "Benefits", to: "/admin/benefits", icon: "gift" },
      { table: "company_info", label: "Company Info", to: "/admin/company", icon: "star" }
    ];
    return (_ctx, _push, _parent, _attrs) => {
      const _component_NuxtLink = __nuxt_component_0;
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl" }, _attrs))}><div class="mb-8"><h1 class="section-title">Admin Overview</h1><p class="section-subtitle">Manage all Sycamore content from here.</p></div><div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4"><!--[-->`);
      ssrRenderList(tables, (t) => {
        _push(ssrRenderComponent(_component_NuxtLink, {
          key: t.table,
          to: t.to,
          class: "card card-hover p-6 group"
        }, {
          default: withCtx((_, _push2, _parent2, _scopeId) => {
            if (_push2) {
              _push2(`<div class="flex items-center justify-between mb-4"${_scopeId}><div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center"${_scopeId}>`);
              _push2(ssrRenderComponent(_component_SidebarIcon, {
                name: t.icon
              }, null, _parent2, _scopeId));
              _push2(`</div><span class="text-2xl font-bold text-slate-900"${_scopeId}>${ssrInterpolate(unref(counts)[t.table] ?? "...")}</span></div><div class="font-semibold text-slate-900"${_scopeId}>${ssrInterpolate(t.label)}</div><div class="text-sm text-sycamore-700 mt-1 inline-flex items-center gap-1"${_scopeId}> Manage `);
              _push2(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent2, _scopeId));
              _push2(`</div>`);
            } else {
              return [
                createVNode("div", { class: "flex items-center justify-between mb-4" }, [
                  createVNode("div", { class: "w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center" }, [
                    createVNode(_component_SidebarIcon, {
                      name: t.icon
                    }, null, 8, ["name"])
                  ]),
                  createVNode("span", { class: "text-2xl font-bold text-slate-900" }, toDisplayString(unref(counts)[t.table] ?? "..."), 1)
                ]),
                createVNode("div", { class: "font-semibold text-slate-900" }, toDisplayString(t.label), 1),
                createVNode("div", { class: "text-sm text-sycamore-700 mt-1 inline-flex items-center gap-1" }, [
                  createTextVNode(" Manage "),
                  createVNode(_component_SidebarIcon, { name: "arrow-right" })
                ])
              ];
            }
          }),
          _: 2
        }, _parent));
      });
      _push(`<!--]--></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/index.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=index-cyQ4PZQK.js.map
