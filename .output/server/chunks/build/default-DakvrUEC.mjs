import { _ as __nuxt_component_0 } from './nuxt-link-nIAPCTWv.mjs';
import { _ as _sfc_main$2 } from './SidebarIcon-B7VkmqYS.mjs';
import { defineComponent, ref, watch, mergeProps, withCtx, createVNode, unref, computed, toDisplayString, shallowRef, getCurrentInstance, provide, cloneVNode, h, createElementBlock, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent, ssrRenderAttr, ssrRenderSlot, ssrRenderList, ssrInterpolate, ssrRenderClass, ssrRenderStyle } from 'vue/server-renderer';
import { u as useRoute } from './server.mjs';
import { _ as _imports_0 } from './virtual_public-BhHsw8T-.mjs';
import { u as useAuth } from './useAuth-DcwruT5Z.mjs';
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
import './supabase-DXLNwiqO.mjs';
import '@supabase/supabase-js';

const _sfc_main$1 = /* @__PURE__ */ defineComponent({
  __name: "SidebarNav",
  __ssrInlineRender: true,
  setup(__props) {
    const standalone = [
      { to: "/", label: "Home", icon: "home" }
    ];
    const groups = [
      {
        id: "getting-started",
        label: "Getting started",
        icon: "check",
        items: [
          { to: "/onboarding", label: "Onboarding", icon: "check" }
        ]
      },
      {
        id: "company",
        label: "Company",
        icon: "building",
        items: [
          { to: "/leadership", label: "Leadership", icon: "star" },
          { to: "/departments", label: "Departments", icon: "building" },
          { to: "/locations", label: "Locations", icon: "map" },
          { to: "/staff", label: "Staff Directory", icon: "users" }
        ]
      },
      {
        id: "work",
        label: "Products & Tech",
        icon: "gift",
        items: [
          { to: "/products", label: "Products", icon: "gift" },
          { to: "/technology", label: "Technology", icon: "palette" }
        ]
      },
      {
        id: "people",
        label: "People & Culture",
        icon: "users",
        items: [
          { to: "/policies", label: "Policies", icon: "book" },
          { to: "/benefits", label: "Benefits & Perks", icon: "gift" },
          { to: "/branding", label: "Branding", icon: "palette" }
        ]
      },
      {
        id: "comms",
        label: "Communication",
        icon: "chat",
        items: [
          { to: "/communication", label: "Communication", icon: "chat" },
          { to: "/contacts", label: "Key Contacts", icon: "phone" },
          { to: "/calendar", label: "Calendar", icon: "calendar" }
        ]
      }
    ];
    const route = useRoute();
    function groupContainsActive(group) {
      return group.items.some((it) => it.to === "/" ? route.path === "/" : route.path.startsWith(it.to));
    }
    const activeGroupId = computed(() => {
      var _a, _b;
      return (_b = (_a = groups.find(groupContainsActive)) == null ? void 0 : _a.id) != null ? _b : groups[0].id;
    });
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
          class: "nav-link",
          "active-class": "nav-link-active",
          "exact-active-class": "nav-link-active"
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
      ssrRenderList(groups, (group) => {
        _push(`<div class="mb-1"><button type="button" class="${ssrRenderClass([{ "text-sycamore-700": groupContainsActive(group) }, "w-full flex items-center justify-between gap-2 px-3 py-2 rounded-lg text-xs font-semibold uppercase tracking-wide text-slate-500 hover:bg-slate-50 transition-colors"])}"><span class="flex items-center gap-2">`);
        _push(ssrRenderComponent(_component_SidebarIcon, {
          name: group.icon
        }, null, _parent));
        _push(` ${ssrInterpolate(group.label)}</span><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="${ssrRenderClass([unref(openId) === group.id ? "rotate-90" : "", "w-4 h-4 transition-transform"])}"><path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 0 1 0-1.06L10.94 10 7.21 6.29a.75.75 0 0 1 1.08-1.04l4.25 4.25a.75.75 0 0 1 0 1.04l-4.25 4.25a.75.75 0 0 1-1.08-.02Z" clip-rule="evenodd"></path></svg></button><div class="mt-1 ml-2 pl-3 border-l border-slate-100 flex flex-col gap-1" style="${ssrRenderStyle(unref(openId) === group.id ? null : { display: "none" })}"><!--[-->`);
        ssrRenderList(group.items, (item) => {
          _push(ssrRenderComponent(_component_NuxtLink, {
            key: item.to,
            to: item.to,
            class: "nav-link",
            "active-class": "nav-link-active",
            "exact-active-class": "nav-link-active"
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("components/SidebarNav.vue");
  return _sfc_setup$1 ? _sfc_setup$1(props, ctx) : void 0;
};
defineComponent({
  name: "ServerPlaceholder",
  render() {
    return createElementBlock("div");
  }
});
const clientOnlySymbol = /* @__PURE__ */ Symbol.for("nuxt:client-only");
const __nuxt_component_2 = defineComponent({
  name: "ClientOnly",
  inheritAttrs: false,
  props: ["fallback", "placeholder", "placeholderTag", "fallbackTag"],
  ...false,
  setup(props, { slots, attrs }) {
    const mounted = shallowRef(false);
    const vm = getCurrentInstance();
    if (vm) {
      vm._nuxtClientOnly = true;
    }
    provide(clientOnlySymbol, true);
    return () => {
      var _a;
      if (mounted.value) {
        const vnodes = (_a = slots.default) == null ? void 0 : _a.call(slots);
        if (vnodes && vnodes.length === 1) {
          return [cloneVNode(vnodes[0], attrs)];
        }
        return vnodes;
      }
      const slot = slots.fallback || slots.placeholder;
      if (slot) {
        return h(slot);
      }
      const fallbackStr = props.fallback || props.placeholder || "";
      const fallbackTag = props.fallbackTag || props.placeholderTag || "span";
      return createElementBlock(fallbackTag, attrs, fallbackStr);
    };
  }
});
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "default",
  __ssrInlineRender: true,
  setup(__props) {
    const sidebarOpen = ref(false);
    const route = useRoute();
    watch(() => route.fullPath, () => {
      sidebarOpen.value = false;
    });
    const { profile } = useAuth();
    const avatarOk = ref(true);
    watch(() => {
      var _a;
      return (_a = profile.value) == null ? void 0 : _a.avatarUrl;
    }, () => {
      avatarOk.value = true;
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_NuxtLink = __nuxt_component_0;
      const _component_SidebarNav = _sfc_main$1;
      const _component_ClientOnly = __nuxt_component_2;
      const _component_SidebarIcon = _sfc_main$2;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "min-h-screen flex" }, _attrs))}><aside class="hidden lg:flex flex-col w-64 bg-white border-r border-slate-200 fixed inset-y-0 left-0 z-30"><div class="h-16 flex items-center gap-3 px-5 border-b border-slate-200">`);
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/",
        class: "flex items-center gap-2.5"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`<img${ssrRenderAttr("src", _imports_0)} alt="Sycamore" class="w-9 h-9"${_scopeId}><div${_scopeId}><div class="font-bold text-slate-900 text-sm leading-tight"${_scopeId}>Sycamore</div><div class="text-xs text-slate-500 leading-tight"${_scopeId}>Information Hub</div></div>`);
          } else {
            return [
              createVNode("img", {
                src: _imports_0,
                alt: "Sycamore",
                class: "w-9 h-9"
              }),
              createVNode("div", null, [
                createVNode("div", { class: "font-bold text-slate-900 text-sm leading-tight" }, "Sycamore"),
                createVNode("div", { class: "text-xs text-slate-500 leading-tight" }, "Information Hub")
              ])
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(`</div><div class="flex-1 overflow-y-auto p-3">`);
      _push(ssrRenderComponent(_component_SidebarNav, null, null, _parent));
      _push(`</div><div class="p-4 border-t border-slate-200 space-y-3">`);
      _push(ssrRenderComponent(_component_ClientOnly, null, {
        fallback: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`<div class="h-9 rounded-lg bg-slate-50 animate-pulse"${_scopeId}></div>`);
          } else {
            return [
              createVNode("div", { class: "h-9 rounded-lg bg-slate-50 animate-pulse" })
            ];
          }
        })
      }, _parent));
      _push(`<div class="text-xs text-slate-400">sycamore.ng \xA9 2025</div></div></aside>`);
      if (unref(sidebarOpen)) {
        _push(`<div class="lg:hidden fixed inset-0 bg-slate-900/50 z-40"></div>`);
      } else {
        _push(`<!---->`);
      }
      if (unref(sidebarOpen)) {
        _push(`<aside class="lg:hidden fixed inset-y-0 left-0 w-64 bg-white z-50 flex flex-col"><div class="h-16 flex items-center justify-between px-4 border-b border-slate-200"><div class="flex items-center gap-2.5"><img${ssrRenderAttr("src", _imports_0)} alt="Sycamore" class="w-9 h-9"><div class="font-bold text-slate-900 text-sm">Sycamore</div></div><button class="p-2 rounded-lg hover:bg-slate-100">`);
        _push(ssrRenderComponent(_component_SidebarIcon, { name: "close" }, null, _parent));
        _push(`</button></div><div class="flex-1 overflow-y-auto p-3">`);
        _push(ssrRenderComponent(_component_SidebarNav, null, null, _parent));
        _push(`</div></aside>`);
      } else {
        _push(`<!---->`);
      }
      _push(`<div class="flex-1 lg:ml-64 flex flex-col min-w-0"><header class="lg:hidden sticky top-0 h-16 bg-white border-b border-slate-200 flex items-center justify-between px-4 z-20"><div class="flex items-center gap-2.5"><img${ssrRenderAttr("src", _imports_0)} alt="Sycamore" class="w-8 h-8"><span class="font-bold text-slate-900 text-sm">Sycamore Hub</span></div><div class="flex items-center gap-2">`);
      _push(ssrRenderComponent(_component_ClientOnly, null, {}, _parent));
      _push(`<button class="p-2 rounded-lg hover:bg-slate-100">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "menu" }, null, _parent));
      _push(`</button></div></header><main class="flex-1 p-4 sm:p-6 lg:p-10">`);
      ssrRenderSlot(_ctx.$slots, "default", {}, null, _push, _parent);
      _push(`</main></div>`);
      _push(ssrRenderComponent(_component_ClientOnly, null, {}, _parent));
      _push(`</div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("layouts/default.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=default-DakvrUEC.mjs.map
