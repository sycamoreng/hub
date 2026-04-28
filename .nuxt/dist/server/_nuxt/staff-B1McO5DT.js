import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderAttr, ssrRenderComponent, ssrIncludeBooleanAttr, ssrLooseContain, ssrLooseEqual, ssrRenderList, ssrInterpolate } from "vue/server-renderer";
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
  __name: "staff",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const staff = ref([]);
    const departments = ref([]);
    const search = ref("");
    const selectedDept = ref("All");
    const loading = ref(true);
    const filtered = computed(() => {
      const q = search.value.trim().toLowerCase();
      return staff.value.filter((s) => {
        const deptOk = selectedDept.value === "All" || s.departments?.name === selectedDept.value;
        if (!deptOk) return false;
        if (!q) return true;
        return s.full_name.toLowerCase().includes(q) || s.role.toLowerCase().includes(q) || s.email.toLowerCase().includes(q);
      });
    });
    function initials(name) {
      return name.split(" ").map((n) => n[0]).join("").slice(0, 2).toUpperCase();
    }
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto" }, _attrs))}><div class="mb-8"><h1 class="section-title">Staff Directory</h1><p class="section-subtitle">Meet the people who make Sycamore thrive.</p></div><div class="card p-4 mb-6 flex flex-col sm:flex-row gap-3"><div class="relative flex-1"><input${ssrRenderAttr("value", unref(search))} type="text" placeholder="Search by name, role, or email..." class="input pl-10"><div class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "search" }, null, _parent));
      _push(`</div></div><select class="input sm:w-56"><option value="All"${ssrIncludeBooleanAttr(Array.isArray(unref(selectedDept)) ? ssrLooseContain(unref(selectedDept), "All") : ssrLooseEqual(unref(selectedDept), "All")) ? " selected" : ""}>All departments</option><!--[-->`);
      ssrRenderList(unref(departments), (d) => {
        _push(`<option${ssrRenderAttr("value", d.name)}${ssrIncludeBooleanAttr(Array.isArray(unref(selectedDept)) ? ssrLooseContain(unref(selectedDept), d.name) : ssrLooseEqual(unref(selectedDept), d.name)) ? " selected" : ""}>${ssrInterpolate(d.name)}</option>`);
      });
      _push(`<!--]--></select></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading staff...</div>`);
      } else if (unref(filtered).length === 0) {
        _push(`<div class="text-slate-400">No staff match your filters.</div>`);
      } else {
        _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4"><!--[-->`);
        ssrRenderList(unref(filtered), (s) => {
          _push(`<article class="card card-hover p-5 flex gap-4"><div class="w-14 h-14 rounded-full bg-gradient-to-br from-sycamore-400 to-sycamore-700 text-white flex items-center justify-center font-bold text-lg flex-shrink-0">${ssrInterpolate(initials(s.full_name))}</div><div class="min-w-0 flex-1"><h3 class="font-semibold text-slate-900 truncate">${ssrInterpolate(s.full_name)}</h3><div class="text-sm text-slate-600 truncate">${ssrInterpolate(s.role)}</div><div class="text-xs text-slate-500 mt-1">`);
          if (s.departments?.name) {
            _push(`<span class="badge badge-green">${ssrInterpolate(s.departments.name)}</span>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div><div class="text-xs text-slate-500 mt-2 truncate"><a${ssrRenderAttr("href", `mailto:${s.email}`)} class="hover:text-sycamore-700">${ssrInterpolate(s.email)}</a></div>`);
          if (s.locations) {
            _push(`<div class="text-xs text-slate-400 mt-0.5">${ssrInterpolate(s.locations.city)}</div>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/staff.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=staff-B1McO5DT.js.map
