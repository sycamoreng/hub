import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderList, ssrRenderClass, ssrInterpolate, ssrRenderComponent } from "vue/server-renderer";
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
  __name: "policies",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const policies = ref([]);
    const expanded = ref({});
    const selectedCat = ref("All");
    const loading = ref(true);
    const categories = computed(() => ["All", ...new Set(policies.value.map((p) => p.category))]);
    const filtered = computed(
      () => selectedCat.value === "All" ? policies.value : policies.value.filter((p) => p.category === selectedCat.value)
    );
    function formatDate(d) {
      return new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
    }
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-5xl mx-auto" }, _attrs))}><div class="mb-8"><h1 class="section-title">Policies</h1><p class="section-subtitle">Guidelines that shape how we work at Sycamore.</p></div><div class="flex flex-wrap gap-2 mb-6"><!--[-->`);
      ssrRenderList(unref(categories), (c) => {
        _push(`<button class="${ssrRenderClass([
          "px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors",
          unref(selectedCat) === c ? "bg-sycamore-600 text-white" : "bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300"
        ])}">${ssrInterpolate(c)}</button>`);
      });
      _push(`<!--]--></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading policies...</div>`);
      } else {
        _push(`<div class="space-y-3"><!--[-->`);
        ssrRenderList(unref(filtered), (p) => {
          _push(`<article class="card"><button class="w-full p-5 flex items-center gap-4 text-left"><div class="w-10 h-10 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center flex-shrink-0">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "book" }, null, _parent));
          _push(`</div><div class="flex-1 min-w-0"><h3 class="font-semibold text-slate-900">${ssrInterpolate(p.title)}</h3><div class="flex flex-wrap items-center gap-2 mt-1 text-xs text-slate-500"><span class="badge badge-slate capitalize">${ssrInterpolate(p.category)}</span><span>Effective ${ssrInterpolate(formatDate(p.effective_date))}</span></div></div><svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="${ssrRenderClass([{ "rotate-180": unref(expanded)[p.id] }, "w-5 h-5 text-slate-400 transition-transform"])}"><path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5"></path></svg></button>`);
          if (unref(expanded)[p.id]) {
            _push(`<div class="px-5 pb-5 pl-[74px] text-sm text-slate-700 whitespace-pre-line border-t border-slate-100 pt-4">${ssrInterpolate(p.content)}</div>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/policies.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=policies-DA1UgYMY.js.map
