import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderAttr, ssrRenderComponent, ssrRenderList, ssrRenderClass, ssrInterpolate } from "vue/server-renderer";
import { u as useCompanyData } from "./useCompanyData-CSkVUIju.js";
import "./supabase-DXLNwiqO.js";
import "@supabase/supabase-js";
import "../server.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ofetch/dist/node.mjs";
import "#internal/nuxt/paths";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/unctx/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/h3/dist/index.mjs";
import "vue-router";
import "/Users/macbookpro/Documents/work/intranet/node_modules/defu/dist/defu.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ufo/dist/index.mjs";
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "products",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const products = ref([]);
    const search = ref("");
    const loading = ref(true);
    const filtered = computed(() => {
      const q = search.value.trim().toLowerCase();
      if (!q) return products.value;
      return products.value.filter(
        (p) => p.name.toLowerCase().includes(q) || (p.tagline ?? "").toLowerCase().includes(q) || (p.description ?? "").toLowerCase().includes(q) || (p.category ?? "").toLowerCase().includes(q)
      );
    });
    const statusBadge = {
      live: "badge-green",
      beta: "badge-blue",
      internal: "badge-slate",
      retired: "badge-rose"
    };
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto" }, _attrs))}><div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-8"><div><h1 class="section-title">Our Products</h1><p class="section-subtitle">The fintech offerings we build, ship, and support.</p></div><div class="relative sm:w-72"><input${ssrRenderAttr("value", unref(search))} type="text" placeholder="Search products..." class="input pl-10"><div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "search" }, null, _parent));
      _push(`</div></div></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading products...</div>`);
      } else if (unref(filtered).length === 0) {
        _push(`<div class="card p-8 text-center text-slate-500">No products match.</div>`);
      } else {
        _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5"><!--[-->`);
        ssrRenderList(unref(filtered), (p) => {
          _push(`<article class="card card-hover p-6 flex flex-col"><div class="flex items-start justify-between gap-3 mb-3"><span class="${ssrRenderClass(["badge capitalize", statusBadge[p.status] ?? "badge-slate"])}">${ssrInterpolate(p.status)}</span>`);
          if (p.category) {
            _push(`<span class="badge badge-slate capitalize">${ssrInterpolate(p.category)}</span>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div><h3 class="text-lg font-bold text-slate-900">${ssrInterpolate(p.name)}</h3>`);
          if (p.tagline) {
            _push(`<p class="text-sm text-sycamore-700 font-medium mt-0.5">${ssrInterpolate(p.tagline)}</p>`);
          } else {
            _push(`<!---->`);
          }
          _push(`<p class="text-sm text-slate-600 mt-3 line-clamp-4 flex-1">${ssrInterpolate(p.description)}</p>`);
          if (p.target_market) {
            _push(`<div class="mt-3 pt-3 border-t border-slate-100"><div class="text-xs text-slate-400 uppercase tracking-wide">Target market</div><div class="text-sm text-slate-700">${ssrInterpolate(p.target_market)}</div></div>`);
          } else {
            _push(`<!---->`);
          }
          if (p.url) {
            _push(`<a${ssrRenderAttr("href", p.url)} target="_blank" rel="noopener" class="text-xs text-sycamore-600 hover:underline mt-3 inline-flex items-center gap-1"> Learn more `);
            _push(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent));
            _push(`</a>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</article>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/products.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=products-dXFh8e6W.js.map
