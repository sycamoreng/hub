import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderAttr, ssrRenderComponent, ssrRenderList, ssrInterpolate } from "vue/server-renderer";
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
  __name: "departments",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const departments = ref([]);
    const search = ref("");
    const loading = ref(true);
    const filtered = computed(() => {
      const q = search.value.trim().toLowerCase();
      if (!q) return departments.value;
      return departments.value.filter(
        (d) => d.name.toLowerCase().includes(q) || d.description.toLowerCase().includes(q) || d.head_name.toLowerCase().includes(q)
      );
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto" }, _attrs))}><div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-8"><div><h1 class="section-title">Departments</h1><p class="section-subtitle">Explore the teams that make Sycamore work.</p></div><div class="relative sm:w-72"><input${ssrRenderAttr("value", unref(search))} type="text" placeholder="Search departments..." class="input pl-10"><div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "search" }, null, _parent));
      _push(`</div></div></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading departments...</div>`);
      } else if (unref(filtered).length === 0) {
        _push(`<div class="text-slate-400">No departments match your search.</div>`);
      } else {
        _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5"><!--[-->`);
        ssrRenderList(unref(filtered), (d) => {
          _push(`<article class="card card-hover p-6"><div class="flex items-start justify-between mb-3"><div class="w-11 h-11 rounded-lg bg-sycamore-50 text-sycamore-600 flex items-center justify-center">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "building" }, null, _parent));
          _push(`</div><span class="badge badge-green">${ssrInterpolate(d.staff_count)} staff</span></div><h3 class="font-bold text-slate-900 text-lg">${ssrInterpolate(d.name)}</h3><p class="text-sm text-slate-600 mt-2 line-clamp-3">${ssrInterpolate(d.description)}</p><div class="mt-4 pt-4 border-t border-slate-100"><div class="text-xs text-slate-400 uppercase tracking-wide mb-1">Department Head</div><div class="text-sm font-semibold text-slate-900">${ssrInterpolate(d.head_name)}</div><div class="text-xs text-slate-500">${ssrInterpolate(d.head_title)}</div>`);
          if (d.head_email) {
            _push(`<a${ssrRenderAttr("href", `mailto:${d.head_email}`)} class="text-xs text-sycamore-600 hover:underline">${ssrInterpolate(d.head_email)}</a>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/departments.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=departments-BUnKL299.js.map
