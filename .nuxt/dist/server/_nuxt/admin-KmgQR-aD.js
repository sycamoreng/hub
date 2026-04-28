import { _ as __nuxt_component_0 } from "./nuxt-link-nIAPCTWv.js";
import { _ as _sfc_main$2 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, computed, ref, watch, mergeProps, withCtx, createVNode, toDisplayString, unref, useSSRContext, createTextVNode } from "vue";
import { ssrRenderAttrs, ssrRenderList, ssrRenderComponent, ssrInterpolate, ssrRenderClass, ssrRenderStyle, ssrRenderAttr, ssrRenderSlot } from "vue/server-renderer";
import { u as useAuth } from "./useAuth-DcwruT5Z.js";
import { u as useRoute } from "../server.mjs";
import { _ as _imports_0 } from "./virtual_public-IWZl7zz2.js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ufo/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/defu/dist/defu.mjs";
import "./supabase-DXLNwiqO.js";
import "@supabase/supabase-js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ofetch/dist/node.mjs";
import "#internal/nuxt/paths";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/unctx/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/h3/dist/index.mjs";
import "vue-router";
const _sfc_main$1 = /* @__PURE__ */ defineComponent({
  __name: "AdminNav",
  __ssrInlineRender: true,
  setup(__props) {
    const { canManageSection, isSuperAdmin } = useAuth();
    const standalone = [
      { to: "/admin", label: "Overview", icon: "home" }
    ];
    const groups = [
      {
        id: "people",
        label: "People",
        icon: "users",
        items: [
          { to: "/admin/staff", label: "Staff", icon: "users", section: "staff" },
          { to: "/admin/leadership", label: "Leadership", icon: "star", section: "leadership" },
          { to: "/admin/departments", label: "Departments", icon: "building", section: "departments" },
          { to: "/admin/onboarding", label: "Onboarding", icon: "check", section: "onboarding" }
        ]
      },
      {
        id: "work",
        label: "Products & Tech",
        icon: "gift",
        items: [
          { to: "/admin/products", label: "Products", icon: "gift", section: "products" },
          { to: "/admin/technology", label: "Technology", icon: "palette", section: "technology" },
          { to: "/admin/chatbot", label: "Chatbot", icon: "chat", section: "chatbot" }
        ]
      },
      {
        id: "comms",
        label: "Communication",
        icon: "chat",
        items: [
          { to: "/admin/announcements", label: "Announcements", icon: "info", section: "announcements" },
          { to: "/admin/events", label: "Events & Holidays", icon: "calendar", section: "events" },
          { to: "/admin/communication", label: "Communication", icon: "chat", section: "communication" },
          { to: "/admin/contacts", label: "Key Contacts", icon: "phone", section: "contacts" }
        ]
      },
      {
        id: "company",
        label: "Company",
        icon: "building",
        items: [
          { to: "/admin/policies", label: "Policies", icon: "book", section: "policies" },
          { to: "/admin/benefits", label: "Benefits", icon: "gift", section: "benefits" },
          { to: "/admin/branding", label: "Branding", icon: "palette", section: "branding" },
          { to: "/admin/locations", label: "Locations", icon: "map", section: "locations" },
          { to: "/admin/company", label: "Company Info", icon: "star", section: "company" }
        ]
      },
      {
        id: "access",
        label: "Access control",
        icon: "star",
        items: [
          { to: "/admin/admins", label: "Admin Access", icon: "users", superAdminOnly: true }
        ]
      }
    ];
    function itemVisible(item) {
      if (item.superAdminOnly) return isSuperAdmin.value;
      if (!item.section) return true;
      return canManageSection(item.section);
    }
    const visibleGroups = computed(
      () => groups.map((g) => ({ ...g, items: g.items.filter(itemVisible) })).filter((g) => g.items.length > 0)
    );
    const route = useRoute();
    function groupContainsActive(group) {
      return group.items.some((it) => it.to === "/admin" ? route.path === "/admin" : route.path.startsWith(it.to));
    }
    const activeGroupId = computed(() => visibleGroups.value.find(groupContainsActive)?.id ?? visibleGroups.value[0]?.id ?? "");
    const openId = ref(activeGroupId.value);
    watch(activeGroupId, (val) => {
      openId.value = val;
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_NuxtLink = __nuxt_component_0;
      const _component_SidebarIcon = _sfc_main$2;
      _push(`<nav${ssrRenderAttrs(mergeProps({ class: "flex flex-col gap-1" }, _attrs))}><!--[-->`);
      ssrRenderList(standalone, (item) => {
        _push(ssrRenderComponent(_component_NuxtLink, {
          key: item.to,
          to: item.to,
          class: "flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-slate-300 hover:bg-slate-800 hover:text-white transition-colors",
          "active-class": "bg-sycamore-600 text-white hover:bg-sycamore-600",
          exact: ""
        }, {
          default: withCtx((_, _push2, _parent2, _scopeId) => {
            if (_push2) {
              _push2(ssrRenderComponent(_component_SidebarIcon, {
                name: item.icon
              }, null, _parent2, _scopeId));
              _push2(`<span${_scopeId}>${ssrInterpolate(item.label)}</span>`);
            } else {
              return [
                createVNode(_component_SidebarIcon, {
                  name: item.icon
                }, null, 8, ["name"]),
                createVNode("span", null, toDisplayString(item.label), 1)
              ];
            }
          }),
          _: 2
        }, _parent));
      });
      _push(`<!--]--><!--[-->`);
      ssrRenderList(unref(visibleGroups), (group) => {
        _push(`<div class="mb-1"><button type="button" class="${ssrRenderClass([{ "text-white": groupContainsActive(group) }, "w-full flex items-center justify-between gap-2 px-3 py-2 rounded-lg text-xs font-semibold uppercase tracking-wide text-slate-400 hover:bg-slate-800 transition-colors"])}"><span class="flex items-center gap-2">`);
        _push(ssrRenderComponent(_component_SidebarIcon, {
          name: group.icon
        }, null, _parent));
        _push(` ${ssrInterpolate(group.label)}</span><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="${ssrRenderClass([unref(openId) === group.id ? "rotate-90" : "", "w-4 h-4 transition-transform"])}"><path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 0-1.06L10.94 10 7.21 6.29a.75.75 0 0 1 1.08-1.04l4.25 4.25a.75.75 0 0 1 0 1.04l-4.25 4.25a.75.75 0 0 1-1.08-.02Z" clip-rule="evenodd"></path></svg></button><div class="mt-1 ml-2 pl-3 border-l border-slate-800 flex flex-col gap-1" style="${ssrRenderStyle(unref(openId) === group.id ? null : { display: "none" })}"><!--[-->`);
        ssrRenderList(group.items, (item) => {
          _push(ssrRenderComponent(_component_NuxtLink, {
            key: item.to,
            to: item.to,
            class: "flex items-center gap-3 px-3 py-2 rounded-lg text-sm text-slate-300 hover:bg-slate-800 hover:text-white transition-colors",
            "active-class": "bg-sycamore-600 text-white hover:bg-sycamore-600",
            exact: item.to === "/admin"
          }, {
            default: withCtx((_, _push2, _parent2, _scopeId) => {
              if (_push2) {
                _push2(ssrRenderComponent(_component_SidebarIcon, {
                  name: item.icon
                }, null, _parent2, _scopeId));
                _push2(`<span${_scopeId}>${ssrInterpolate(item.label)}</span>`);
              } else {
                return [
                  createVNode(_component_SidebarIcon, {
                    name: item.icon
                  }, null, 8, ["name"]),
                  createVNode("span", null, toDisplayString(item.label), 1)
                ];
              }
            }),
            _: 2
          }, _parent));
        });
        _push(`<!--]--></div></div>`);
      });
      _push(`<!--]--></nav>`);
    };
  }
});
const _sfc_setup$1 = _sfc_main$1.setup;
_sfc_main$1.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("components/AdminNav.vue");
  return _sfc_setup$1 ? _sfc_setup$1(props, ctx) : void 0;
};
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "admin",
  __ssrInlineRender: true,
  setup(__props) {
    const sidebarOpen = ref(false);
    const route = useRoute();
    const { user } = useAuth();
    watch(() => route.fullPath, () => {
      sidebarOpen.value = false;
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_AdminNav = _sfc_main$1;
      const _component_NuxtLink = __nuxt_component_0;
      const _component_SidebarIcon = _sfc_main$2;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "min-h-screen flex bg-slate-50" }, _attrs))}><aside class="hidden lg:flex flex-col w-64 bg-slate-900 text-slate-200 fixed inset-y-0 left-0 z-30"><div class="h-16 flex items-center gap-3 px-5 border-b border-slate-800"><img${ssrRenderAttr("src", _imports_0)} alt="Sycamore" class="h-7 w-auto brightness-0 invert"><div class="text-xs text-slate-400 border-l border-slate-700 pl-3">Admin</div></div><div class="flex-1 overflow-y-auto p-3">`);
      _push(ssrRenderComponent(_component_AdminNav, null, null, _parent));
      _push(`</div><div class="p-4 border-t border-slate-800 text-xs"><div class="text-slate-400 truncate mb-2">${ssrInterpolate(unref(user)?.email)}</div><div class="flex gap-2">`);
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/",
        class: "flex-1 text-center px-2 py-1.5 rounded-md bg-slate-800 hover:bg-slate-700 text-slate-200"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`View site`);
          } else {
            return [
              createTextVNode("View site")
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(`<button class="flex-1 text-center px-2 py-1.5 rounded-md bg-slate-800 hover:bg-slate-700 text-slate-200">Sign out</button></div></div></aside>`);
      if (unref(sidebarOpen)) {
        _push(`<div class="lg:hidden fixed inset-0 bg-slate-900/50 z-40"></div>`);
      } else {
        _push(`<!---->`);
      }
      if (unref(sidebarOpen)) {
        _push(`<aside class="lg:hidden fixed inset-y-0 left-0 w-64 bg-slate-900 text-slate-200 z-50 flex flex-col"><div class="h-16 flex items-center justify-between px-4 border-b border-slate-800"><div class="font-bold text-white text-sm">Sycamore Admin</div><button class="p-2 rounded-lg hover:bg-slate-800">`);
        _push(ssrRenderComponent(_component_SidebarIcon, { name: "close" }, null, _parent));
        _push(`</button></div><div class="flex-1 overflow-y-auto p-3">`);
        _push(ssrRenderComponent(_component_AdminNav, null, null, _parent));
        _push(`</div><div class="p-4 border-t border-slate-800 text-xs"><div class="text-slate-400 truncate mb-2">${ssrInterpolate(unref(user)?.email)}</div><button class="w-full px-2 py-1.5 rounded-md bg-slate-800 text-slate-200">Sign out</button></div></aside>`);
      } else {
        _push(`<!---->`);
      }
      _push(`<div class="flex-1 lg:ml-64 flex flex-col min-w-0"><header class="lg:hidden sticky top-0 h-16 bg-white border-b border-slate-200 flex items-center justify-between px-4 z-20"><div class="font-bold text-slate-900 text-sm">Admin</div><button class="p-2 rounded-lg hover:bg-slate-100">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "menu" }, null, _parent));
      _push(`</button></header><main class="flex-1 p-4 sm:p-6 lg:p-10">`);
      ssrRenderSlot(_ctx.$slots, "default", {}, null, _push, _parent);
      _push(`</main></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("layouts/admin.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=admin-KmgQR-aD.js.map
