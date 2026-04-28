import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderList, ssrRenderClass, ssrInterpolate, ssrRenderComponent, ssrRenderAttr } from "vue/server-renderer";
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
  __name: "technology",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const stack = ref([]);
    const loading = ref(true);
    const selected = ref("All");
    const categories = computed(() => ["All", ...Array.from(new Set(stack.value.map((t) => t.category || "general"))).sort()]);
    const filtered = computed(() => selected.value === "All" ? stack.value : stack.value.filter((t) => (t.category || "general") === selected.value));
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto" }, _attrs))}><div class="mb-8"><h1 class="section-title">Technology Stack</h1><p class="section-subtitle">The tools, languages, and platforms powering Sycamore.</p></div><div class="flex flex-wrap gap-2 mb-6"><!--[-->`);
      ssrRenderList(unref(categories), (c) => {
        _push(`<button class="${ssrRenderClass([
          "px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors",
          unref(selected) === c ? "bg-sycamore-600 text-white" : "bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300"
        ])}">${ssrInterpolate(c)}</button>`);
      });
      _push(`<!--]--></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading tech stack...</div>`);
      } else if (unref(filtered).length === 0) {
        _push(`<div class="card p-8 text-center text-slate-500">No technologies listed.</div>`);
      } else {
        _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5"><!--[-->`);
        ssrRenderList(unref(filtered), (t) => {
          _push(`<article class="card card-hover p-6"><div class="flex items-start justify-between mb-3"><div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "palette" }, null, _parent));
          _push(`</div><span class="badge badge-slate capitalize">${ssrInterpolate(t.category)}</span></div><h3 class="text-lg font-bold text-slate-900">${ssrInterpolate(t.name)}</h3>`);
          if (t.description) {
            _push(`<p class="text-sm text-slate-600 mt-2 line-clamp-3">${ssrInterpolate(t.description)}</p>`);
          } else {
            _push(`<!---->`);
          }
          if (t.used_for) {
            _push(`<div class="mt-3 pt-3 border-t border-slate-100"><div class="text-xs text-slate-400 uppercase tracking-wide">Used for</div><div class="text-sm text-slate-700">${ssrInterpolate(t.used_for)}</div></div>`);
          } else {
            _push(`<!---->`);
          }
          if (t.url) {
            _push(`<a${ssrRenderAttr("href", t.url)} target="_blank" rel="noopener" class="text-xs text-sycamore-600 hover:underline mt-3 inline-flex items-center gap-1"> Learn more `);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/technology.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=technology-Cvn4TsiO.js.map
