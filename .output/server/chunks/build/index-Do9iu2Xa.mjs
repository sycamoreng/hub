import { _ as _sfc_main$1 } from './SidebarIcon-B7VkmqYS.mjs';
import { _ as __nuxt_component_0 } from './nuxt-link-nIAPCTWv.mjs';
import { defineComponent, ref, computed, mergeProps, unref, withCtx, createVNode, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent, ssrInterpolate, ssrRenderList, ssrRenderClass } from 'vue/server-renderer';
import { u as useCompanyData } from './useCompanyData-CSkVUIju.mjs';
import '../nitro/nitro.mjs';
import 'node:http';
import 'node:https';
import 'node:events';
import 'node:buffer';
import 'node:fs';
import 'node:path';
import 'node:crypto';
import 'node:url';
import './server.mjs';
import '../routes/renderer.mjs';
import 'vue-bundle-renderer/runtime';
import 'unhead/server';
import 'devalue';
import 'unhead/utils';
import 'unhead/plugins';
import 'vue-router';
import './supabase-DXLNwiqO.mjs';
import '@supabase/supabase-js';

const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "index",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const companyInfo = ref([]);
    const departments = ref([]);
    const locations = ref([]);
    const staff = ref([]);
    const announcements = ref([]);
    const events = ref([]);
    const loading = ref(true);
    const infoMap = computed(() => {
      const m = {};
      for (const i of companyInfo.value) m[i.info_key] = i.info_value;
      return m;
    });
    const upcomingEvents = computed(() => {
      const today = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
      return events.value.filter((e) => e.event_date >= today).slice(0, 5);
    });
    const stats = computed(() => [
      { label: "Departments", value: departments.value.length, icon: "building" },
      { label: "Locations", value: locations.value.length, icon: "map" },
      { label: "Staff Members", value: staff.value.length, icon: "users" },
      { label: "Upcoming Events", value: upcomingEvents.value.length, icon: "calendar" }
    ]);
    function parseEventDate(d) {
      const parts = (d || "").slice(0, 10).split("-").map(Number);
      if (parts.length === 3 && parts.every((n) => !Number.isNaN(n))) {
        return new Date(parts[0], parts[1] - 1, parts[2]);
      }
      return new Date(d);
    }
    function formatDate(d) {
      return new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
    }
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      const _component_NuxtLink = __nuxt_component_0;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto space-y-8" }, _attrs))}><div class="bg-gradient-to-br from-sycamore-600 to-sycamore-800 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden"><div class="relative z-10"><div class="badge bg-white/15 text-white border-white/20 mb-4">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "dot" }, null, _parent));
      _push(`<span class="ml-1">Welcome to Sycamore</span></div><h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">${ssrInterpolate(unref(infoMap).tagline || "Nurturing Growth, Building Futures")}</h1><p class="text-sycamore-50 max-w-2xl">${ssrInterpolate(unref(infoMap).about || "Your central hub for everything you need to know about working at Sycamore.")}</p></div><div class="absolute -right-16 -bottom-16 w-80 h-80 rounded-full bg-white/5"></div><div class="absolute -right-8 -top-8 w-48 h-48 rounded-full bg-white/5"></div></div><div class="grid grid-cols-2 lg:grid-cols-4 gap-4"><!--[-->`);
      ssrRenderList(unref(stats), (s) => {
        _push(`<div class="card p-5"><div class="flex items-start justify-between"><div><div class="text-sm text-slate-500">${ssrInterpolate(s.label)}</div><div class="text-3xl font-bold text-slate-900 mt-1">${ssrInterpolate(s.value)}</div></div><div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">`);
        _push(ssrRenderComponent(_component_SidebarIcon, {
          name: s.icon
        }, null, _parent));
        _push(`</div></div></div>`);
      });
      _push(`<!--]--></div><div class="grid lg:grid-cols-3 gap-6"><div class="lg:col-span-2 card p-6"><div class="flex items-center justify-between mb-5"><div><h2 class="text-lg font-bold text-slate-900">Announcements</h2><p class="text-sm text-slate-500">Latest company-wide updates</p></div>`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "info" }, null, _parent));
      _push(`</div>`);
      if (unref(loading)) {
        _push(`<div class="text-sm text-slate-400">Loading...</div>`);
      } else if (unref(announcements).length === 0) {
        _push(`<div class="text-sm text-slate-400">No announcements.</div>`);
      } else {
        _push(`<div class="space-y-4"><!--[-->`);
        ssrRenderList(unref(announcements), (a) => {
          _push(`<article class="flex gap-4 p-4 rounded-lg bg-slate-50 border border-slate-100"><div class="flex-shrink-0"><span class="${ssrRenderClass([
            "badge",
            a.priority === "high" ? "badge-rose" : a.priority === "medium" ? "badge-amber" : "badge-slate"
          ])}">${ssrInterpolate(a.priority)}</span></div><div class="min-w-0"><h3 class="font-semibold text-slate-900">${ssrInterpolate(a.title)}</h3><p class="text-sm text-slate-600 mt-1">${ssrInterpolate(a.content)}</p><div class="text-xs text-slate-400 mt-2">${ssrInterpolate(formatDate(a.created_at))}</div></div></article>`);
        });
        _push(`<!--]--></div>`);
      }
      _push(`</div><div class="card p-6"><div class="flex items-center justify-between mb-5"><div><h2 class="text-lg font-bold text-slate-900">Upcoming Events</h2><p class="text-sm text-slate-500">Don&#39;t miss these</p></div>`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "calendar" }, null, _parent));
      _push(`</div>`);
      if (unref(upcomingEvents).length === 0) {
        _push(`<div class="text-sm text-slate-400">No upcoming events.</div>`);
      } else {
        _push(`<ul class="space-y-3"><!--[-->`);
        ssrRenderList(unref(upcomingEvents), (e) => {
          _push(`<li class="flex items-start gap-3 p-3 rounded-lg hover:bg-slate-50"><div class="flex-shrink-0 w-12 text-center"><div class="text-xs font-medium text-sycamore-600 uppercase">${ssrInterpolate(parseEventDate(e.event_date).toLocaleString("en-GB", { month: "short" }))}</div><div class="text-xl font-bold text-slate-900">${ssrInterpolate(parseEventDate(e.event_date).getDate())}</div></div><div class="min-w-0"><div class="font-medium text-slate-900 text-sm">${ssrInterpolate(e.title)}</div><div class="text-xs text-slate-500 truncate">${ssrInterpolate(e.description)}</div><span class="badge badge-green mt-1.5">${ssrInterpolate(e.event_type)}</span></div></li>`);
        });
        _push(`<!--]--></ul>`);
      }
      _push(`</div></div><div class="card p-6"><h2 class="text-lg font-bold text-slate-900 mb-5">Quick Links</h2><div class="grid sm:grid-cols-2 lg:grid-cols-4 gap-3">`);
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/staff",
        class: "group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`<div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"${_scopeId}>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "users" }, null, _parent2, _scopeId));
            _push2(`</div><div class="flex-1 text-sm font-medium text-slate-800"${_scopeId}>Find a colleague</div>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent2, _scopeId));
          } else {
            return [
              createVNode("div", { class: "w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center" }, [
                createVNode(_component_SidebarIcon, { name: "users" })
              ]),
              createVNode("div", { class: "flex-1 text-sm font-medium text-slate-800" }, "Find a colleague"),
              createVNode(_component_SidebarIcon, { name: "arrow-right" })
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/policies",
        class: "group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`<div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"${_scopeId}>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "book" }, null, _parent2, _scopeId));
            _push2(`</div><div class="flex-1 text-sm font-medium text-slate-800"${_scopeId}>Read policies</div>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent2, _scopeId));
          } else {
            return [
              createVNode("div", { class: "w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center" }, [
                createVNode(_component_SidebarIcon, { name: "book" })
              ]),
              createVNode("div", { class: "flex-1 text-sm font-medium text-slate-800" }, "Read policies"),
              createVNode(_component_SidebarIcon, { name: "arrow-right" })
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/benefits",
        class: "group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`<div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"${_scopeId}>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "gift" }, null, _parent2, _scopeId));
            _push2(`</div><div class="flex-1 text-sm font-medium text-slate-800"${_scopeId}>Your benefits</div>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent2, _scopeId));
          } else {
            return [
              createVNode("div", { class: "w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center" }, [
                createVNode(_component_SidebarIcon, { name: "gift" })
              ]),
              createVNode("div", { class: "flex-1 text-sm font-medium text-slate-800" }, "Your benefits"),
              createVNode(_component_SidebarIcon, { name: "arrow-right" })
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/contacts",
        class: "group flex items-center gap-3 p-4 rounded-lg border border-slate-200 hover:border-sycamore-300 hover:bg-sycamore-50 transition-colors"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`<div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center"${_scopeId}>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "phone" }, null, _parent2, _scopeId));
            _push2(`</div><div class="flex-1 text-sm font-medium text-slate-800"${_scopeId}>Key contacts</div>`);
            _push2(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent2, _scopeId));
          } else {
            return [
              createVNode("div", { class: "w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 group-hover:bg-white flex items-center justify-center" }, [
                createVNode(_component_SidebarIcon, { name: "phone" })
              ]),
              createVNode("div", { class: "flex-1 text-sm font-medium text-slate-800" }, "Key contacts"),
              createVNode(_component_SidebarIcon, { name: "arrow-right" })
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(`</div></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/index.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=index-Do9iu2Xa.mjs.map
