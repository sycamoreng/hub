import { _ as _sfc_main$1 } from './SidebarIcon-B7VkmqYS.mjs';
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderList, ssrInterpolate, ssrRenderComponent, ssrRenderAttr } from 'vue/server-renderer';
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
  __name: "communication",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const tools = ref([]);
    const loading = ref(true);
    const grouped = computed(() => {
      const m = {};
      for (const t of tools.value) {
        const key = t.category || "general";
        (m[key] = m[key] || []).push(t);
      }
      return m;
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl mx-auto" }, _attrs))}><div class="mb-8"><h1 class="section-title">Communication Tools</h1><p class="section-subtitle">Platforms and channels we use to stay connected.</p></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading tools...</div>`);
      } else {
        _push(`<div class="space-y-8"><!--[-->`);
        ssrRenderList(unref(grouped), (items, cat) => {
          _push(`<section><h2 class="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3 capitalize">${ssrInterpolate(cat)}</h2><div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4"><!--[-->`);
          ssrRenderList(items, (t) => {
            _push(`<article class="card card-hover p-5"><div class="flex items-start justify-between mb-3"><div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "chat" }, null, _parent));
            _push(`</div>`);
            if (t.is_primary) {
              _push(`<span class="badge badge-green">Primary</span>`);
            } else {
              _push(`<!---->`);
            }
            _push(`</div><h3 class="font-semibold text-slate-900">${ssrInterpolate(t.name)}</h3><p class="text-sm text-slate-600 mt-1.5 mb-4">${ssrInterpolate(t.description)}</p>`);
            if (t.url) {
              _push(`<a${ssrRenderAttr("href", t.url)} target="_blank" rel="noopener" class="text-sm text-sycamore-600 hover:underline inline-flex items-center gap-1"> Open `);
              _push(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent));
              _push(`</a>`);
            } else {
              _push(`<!---->`);
            }
            _push(`</article>`);
          });
          _push(`<!--]--></div></section>`);
        });
        _push(`<!--]--></div>`);
      }
      _push(`</div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/communication.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=communication-9c7biL-Y.mjs.map
