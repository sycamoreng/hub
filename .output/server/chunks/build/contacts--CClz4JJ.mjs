import { _ as _sfc_main$1 } from './SidebarIcon-B7VkmqYS.mjs';
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent, ssrRenderList, ssrInterpolate, ssrRenderAttr } from 'vue/server-renderer';
import { u as useCompanyData } from './useCompanyData-CSkVUIju.mjs';
import './supabase-DXLNwiqO.mjs';
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
  __name: "contacts",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const contacts = ref([]);
    const loading = ref(true);
    const emergency = computed(() => contacts.value.filter((c) => c.is_emergency));
    const regular = computed(() => contacts.value.filter((c) => !c.is_emergency));
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-5xl mx-auto space-y-8" }, _attrs))}><div><h1 class="section-title">Key Contacts</h1><p class="section-subtitle">Know who to reach out to for what.</p></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading contacts...</div>`);
      } else {
        _push(`<!---->`);
      }
      if (!unref(loading) && unref(emergency).length) {
        _push(`<section class="rounded-2xl border-2 border-rose-200 bg-rose-50 p-6"><div class="flex items-center gap-2 mb-4"><div class="w-9 h-9 rounded-lg bg-rose-600 text-white flex items-center justify-center">`);
        _push(ssrRenderComponent(_component_SidebarIcon, { name: "alert" }, null, _parent));
        _push(`</div><h2 class="text-lg font-bold text-rose-900">Emergency Contacts</h2></div><div class="grid sm:grid-cols-2 gap-3"><!--[-->`);
        ssrRenderList(unref(emergency), (c) => {
          _push(`<article class="bg-white rounded-lg p-4 border border-rose-100"><h3 class="font-semibold text-slate-900">${ssrInterpolate(c.name)}</h3><div class="text-sm text-slate-600">${ssrInterpolate(c.role)}</div><div class="text-sm space-y-1 mt-3">`);
          if (c.phone) {
            _push(`<a${ssrRenderAttr("href", `tel:${c.phone}`)} class="flex items-center gap-2 text-rose-700 font-semibold">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "phone" }, null, _parent));
            _push(` ${ssrInterpolate(c.phone)}</a>`);
          } else {
            _push(`<!---->`);
          }
          if (c.email) {
            _push(`<a${ssrRenderAttr("href", `mailto:${c.email}`)} class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "mail" }, null, _parent));
            _push(` ${ssrInterpolate(c.email)}</a>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div></article>`);
        });
        _push(`<!--]--></div></section>`);
      } else {
        _push(`<!---->`);
      }
      if (!unref(loading) && unref(regular).length) {
        _push(`<section><h2 class="text-lg font-bold text-slate-900 mb-4">Department Contacts</h2><div class="grid sm:grid-cols-2 gap-4"><!--[-->`);
        ssrRenderList(unref(regular), (c) => {
          _push(`<article class="card p-5"><div class="flex items-start justify-between mb-2"><h3 class="font-semibold text-slate-900">${ssrInterpolate(c.name)}</h3>`);
          if (c.department) {
            _push(`<span class="badge badge-green">${ssrInterpolate(c.department)}</span>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div><div class="text-sm text-slate-600">${ssrInterpolate(c.role)}</div><div class="text-sm space-y-1 mt-3 pt-3 border-t border-slate-100">`);
          if (c.email) {
            _push(`<a${ssrRenderAttr("href", `mailto:${c.email}`)} class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "mail" }, null, _parent));
            _push(` ${ssrInterpolate(c.email)}</a>`);
          } else {
            _push(`<!---->`);
          }
          if (c.phone) {
            _push(`<a${ssrRenderAttr("href", `tel:${c.phone}`)} class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "phone" }, null, _parent));
            _push(` ${ssrInterpolate(c.phone)}</a>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div></article>`);
        });
        _push(`<!--]--></div></section>`);
      } else {
        _push(`<!---->`);
      }
      _push(`</div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/contacts.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=contacts--CClz4JJ.mjs.map
