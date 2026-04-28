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
  __name: "benefits",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const benefits = ref([]);
    const selectedCat = ref("All");
    const loading = ref(true);
    const categories = computed(() => ["All", ...new Set(benefits.value.map((b) => b.category))]);
    const filtered = computed(
      () => selectedCat.value === "All" ? benefits.value : benefits.value.filter((b) => b.category === selectedCat.value)
    );
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl mx-auto" }, _attrs))}><div class="mb-8"><h1 class="section-title">Benefits &amp; Perks</h1><p class="section-subtitle">We invest in you. Here&#39;s what that looks like.</p></div><div class="flex flex-wrap gap-2 mb-6"><!--[-->`);
      ssrRenderList(unref(categories), (c) => {
        _push(`<button class="${ssrRenderClass([
          "px-4 py-2 rounded-lg text-sm font-medium capitalize transition-colors",
          unref(selectedCat) === c ? "bg-sycamore-600 text-white" : "bg-white border border-slate-200 text-slate-700 hover:border-sycamore-300"
        ])}">${ssrInterpolate(c)}</button>`);
      });
      _push(`<!--]--></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading benefits...</div>`);
      } else {
        _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5"><!--[-->`);
        ssrRenderList(unref(filtered), (b) => {
          _push(`<article class="card card-hover p-6"><div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center mb-4">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "gift" }, null, _parent));
          _push(`</div><h3 class="font-bold text-slate-900">${ssrInterpolate(b.title)}</h3><p class="text-sm text-slate-600 mt-2">${ssrInterpolate(b.description)}</p><div class="mt-4 pt-4 border-t border-slate-100 flex items-center justify-between text-xs"><span class="badge badge-green capitalize">${ssrInterpolate(b.category)}</span><span class="text-slate-500">${ssrInterpolate(b.eligibility)}</span></div></article>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/benefits.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=benefits-B8PmWuUI.js.map
