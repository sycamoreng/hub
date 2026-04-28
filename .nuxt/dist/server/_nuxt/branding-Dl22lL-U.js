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
  __name: "branding",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const guidelines = ref([]);
    ref(true);
    const grouped = computed(() => {
      const m = {};
      for (const g of guidelines.value) {
        const key = g.category || "visual";
        (m[key] = m[key] || []).push(g);
      }
      return m;
    });
    const palette = [
      { name: "Sycamore 600", hex: "#2f6f2f", cls: "bg-sycamore-600" },
      { name: "Sycamore 500", hex: "#3D8B3D", cls: "bg-sycamore-500" },
      { name: "Sycamore 400", hex: "#62a862", cls: "bg-sycamore-400" },
      { name: "Sycamore 100", hex: "#dceddc", cls: "bg-sycamore-100" },
      { name: "Slate 900", hex: "#0f172a", cls: "bg-slate-900" },
      { name: "Slate 500", hex: "#64748b", cls: "bg-slate-500" }
    ];
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl mx-auto space-y-10" }, _attrs))}><div><h1 class="section-title">Branding Guidelines</h1><p class="section-subtitle">How we present Sycamore to the world.</p></div><section class="card p-6"><h2 class="text-lg font-bold text-slate-900 mb-5">Color Palette</h2><div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3"><!--[-->`);
      ssrRenderList(palette, (c) => {
        _push(`<div><div class="${ssrRenderClass(["aspect-square rounded-xl", c.cls])}"></div><div class="mt-2 text-xs font-medium text-slate-900">${ssrInterpolate(c.name)}</div><div class="text-xs text-slate-500 font-mono">${ssrInterpolate(c.hex)}</div></div>`);
      });
      _push(`<!--]--></div></section><!--[-->`);
      ssrRenderList(unref(grouped), (items, cat) => {
        _push(`<section><h2 class="text-lg font-bold text-slate-900 mb-4 capitalize">${ssrInterpolate(cat)} Guidelines</h2><div class="grid md:grid-cols-2 gap-4"><!--[-->`);
        ssrRenderList(items, (g) => {
          _push(`<article class="card p-6"><h3 class="font-semibold text-slate-900 flex items-center gap-2">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "palette" }, null, _parent));
          _push(` ${ssrInterpolate(g.element_name)}</h3><p class="text-sm text-slate-600 mt-2">${ssrInterpolate(g.description)}</p>`);
          if (g.guidelines) {
            _push(`<div class="mt-4 p-3 bg-slate-50 rounded-lg text-sm text-slate-700 whitespace-pre-line border border-slate-100">${ssrInterpolate(g.guidelines)}</div>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</article>`);
        });
        _push(`<!--]--></div></section>`);
      });
      _push(`<!--]--></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/branding.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=branding-Dl22lL-U.js.map
