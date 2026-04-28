import { _ as _sfc_main$1 } from './SidebarIcon-B7VkmqYS.mjs';
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderList, ssrRenderClass, ssrInterpolate, ssrRenderAttr, ssrRenderComponent } from 'vue/server-renderer';
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
  __name: "locations",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const locations = ref([]);
    const selectedCountry = ref("All");
    const loading = ref(true);
    const countries = computed(() => ["All", ...new Set(locations.value.map((l) => l.country))]);
    const filtered = computed(
      () => selectedCountry.value === "All" ? locations.value : locations.value.filter((l) => l.country === selectedCountry.value)
    );
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto" }, _attrs))}><div class="mb-8"><h1 class="section-title">Our Locations</h1><p class="section-subtitle">Sycamore offices across the world.</p></div><div class="flex flex-wrap gap-2 mb-6"><!--[-->`);
      ssrRenderList(unref(countries), (c) => {
        _push(`<button class="${ssrRenderClass([
          "px-4 py-2 rounded-lg text-sm font-medium transition-colors",
          unref(selectedCountry) === c ? "bg-sycamore-600 text-white" : "bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300"
        ])}">${ssrInterpolate(c)}</button>`);
      });
      _push(`<!--]--></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading locations...</div>`);
      } else {
        _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5"><!--[-->`);
        ssrRenderList(unref(filtered), (l) => {
          _push(`<article class="card card-hover p-6"><div class="flex items-center gap-2 mb-3 flex-wrap">`);
          if (l.is_headquarters) {
            _push(`<span class="badge badge-green">Headquarters</span>`);
          } else {
            _push(`<!---->`);
          }
          _push(`<span class="badge badge-slate capitalize">${ssrInterpolate(l.location_type)}</span><span class="badge badge-blue">${ssrInterpolate(l.staff_count)} staff</span></div><h3 class="text-lg font-bold text-slate-900">${ssrInterpolate(l.name)}</h3><div class="text-sm text-slate-600 mt-2"><div>${ssrInterpolate(l.address)}</div><div>${ssrInterpolate(l.city)}`);
          if (l.state) {
            _push(`<span>, ${ssrInterpolate(l.state)}</span>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div><div class="text-slate-500">${ssrInterpolate(l.country)}</div></div><div class="mt-4 pt-4 border-t border-slate-100 space-y-1.5 text-sm">`);
          if (l.phone) {
            _push(`<a${ssrRenderAttr("href", `tel:${l.phone}`)} class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "phone" }, null, _parent));
            _push(` ${ssrInterpolate(l.phone)}</a>`);
          } else {
            _push(`<!---->`);
          }
          if (l.email) {
            _push(`<a${ssrRenderAttr("href", `mailto:${l.email}`)} class="flex items-center gap-2 text-slate-700 hover:text-sycamore-700">`);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "mail" }, null, _parent));
            _push(` ${ssrInterpolate(l.email)}</a>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div></article>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/locations.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=locations-CN-lCNLN.mjs.map
