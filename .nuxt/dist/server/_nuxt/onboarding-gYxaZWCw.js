import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { _ as __nuxt_component_0 } from "./nuxt-link-nIAPCTWv.js";
import { defineComponent, ref, watch, computed, mergeProps, unref, withCtx, createTextVNode, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderComponent, ssrInterpolate, ssrRenderStyle, ssrRenderList, ssrRenderClass, ssrIncludeBooleanAttr, ssrRenderAttr } from "vue/server-renderer";
import { u as useSupabase } from "./supabase-DXLNwiqO.js";
import { u as useCompanyData } from "./useCompanyData-CSkVUIju.js";
import { u as useAuth } from "./useAuth-DcwruT5Z.js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "../server.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ufo/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/defu/dist/defu.mjs";
import "@supabase/supabase-js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ofetch/dist/node.mjs";
import "#internal/nuxt/paths";
import "/Users/macbookpro/Documents/work/intranet/node_modules/unctx/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/h3/dist/index.mjs";
import "vue-router";
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "onboarding",
  __ssrInlineRender: true,
  setup(__props) {
    const supabase = useSupabase();
    const { fetchOnboardingSteps } = useCompanyData();
    const { user } = useAuth();
    const steps = ref([]);
    const completed = ref({});
    const loading = ref(true);
    const saving = ref({});
    async function loadAll() {
      loading.value = true;
      try {
        steps.value = await fetchOnboardingSteps();
        if (user.value) {
          const { data } = await supabase.from("onboarding_progress").select("step_id").eq("user_id", user.value.id);
          const map = {};
          (data ?? []).forEach((r) => {
            map[r.step_id] = true;
          });
          completed.value = map;
        }
      } finally {
        loading.value = false;
      }
    }
    watch(() => user.value?.id, loadAll);
    const grouped = computed(() => {
      const m = {};
      for (const s of steps.value) {
        const c = s.category || "general";
        (m[c] ||= []).push(s);
      }
      return m;
    });
    const categories = computed(() => Object.keys(grouped.value).sort());
    const stats = computed(() => {
      const total = steps.value.length;
      const required = steps.value.filter((s) => s.is_required).length;
      const done = steps.value.filter((s) => completed.value[s.id]).length;
      const requiredDone = steps.value.filter((s) => s.is_required && completed.value[s.id]).length;
      return { total, required, done, requiredDone, percent: total ? Math.round(done / total * 100) : 0 };
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      const _component_NuxtLink = __nuxt_component_0;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-5xl mx-auto space-y-8" }, _attrs))}><div class="bg-gradient-to-br from-sycamore-700 to-sycamore-900 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden"><div class="relative z-10"><div class="badge bg-white/15 text-white border-white/20 mb-4">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "check" }, null, _parent));
      _push(`<span class="ml-1">Onboarding</span></div><h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">Welcome to Sycamore</h1><p class="text-sycamore-100 max-w-2xl">A guided checklist of everything you should know in your first weeks.</p>`);
      if (unref(user)) {
        _push(`<div class="mt-6 max-w-md"><div class="flex items-center justify-between text-sm mb-2"><span>${ssrInterpolate(unref(stats).done)} of ${ssrInterpolate(unref(stats).total)} completed</span><span class="font-semibold">${ssrInterpolate(unref(stats).percent)}%</span></div><div class="w-full h-2 rounded-full bg-white/15 overflow-hidden"><div class="h-full bg-leaf-400 transition-all" style="${ssrRenderStyle({ width: `${unref(stats).percent}%` })}"></div></div><div class="text-xs text-sycamore-100/80 mt-2">${ssrInterpolate(unref(stats).requiredDone)} / ${ssrInterpolate(unref(stats).required)} required steps done</div></div>`);
      } else {
        _push(`<div class="mt-6">`);
        _push(ssrRenderComponent(_component_NuxtLink, {
          to: "/login?redirect=/onboarding",
          class: "inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-white text-sycamore-700 font-medium text-sm"
        }, {
          default: withCtx((_, _push2, _parent2, _scopeId) => {
            if (_push2) {
              _push2(` Sign in to track progress `);
            } else {
              return [
                createTextVNode(" Sign in to track progress ")
              ];
            }
          }),
          _: 1
        }, _parent));
        _push(`</div>`);
      }
      _push(`</div><div class="absolute -right-16 -bottom-16 w-80 h-80 rounded-full bg-white/5"></div></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading onboarding checklist...</div>`);
      } else if (unref(steps).length === 0) {
        _push(`<div class="card p-8 text-center text-slate-500"> No onboarding steps have been set up yet. </div>`);
      } else {
        _push(`<div class="space-y-8"><!--[-->`);
        ssrRenderList(unref(categories), (cat) => {
          _push(`<section><h2 class="section-title capitalize mb-4">${ssrInterpolate(cat)}</h2><div class="space-y-3"><!--[-->`);
          ssrRenderList(unref(grouped)[cat], (s) => {
            _push(`<article class="${ssrRenderClass([unref(completed)[s.id] ? "bg-leaf-50/50 border-leaf-200" : "", "card p-5 flex items-start gap-4"])}"><button type="button"${ssrIncludeBooleanAttr(unref(saving)[s.id]) ? " disabled" : ""} class="${ssrRenderClass([
              "flex-shrink-0 w-6 h-6 rounded-full border-2 flex items-center justify-center transition-colors mt-0.5",
              unref(completed)[s.id] ? "bg-leaf-600 border-leaf-600 text-white" : "border-slate-300 hover:border-sycamore-500"
            ])}"${ssrRenderAttr("aria-label", unref(completed)[s.id] ? "Mark incomplete" : "Mark complete")}>`);
            if (unref(completed)[s.id]) {
              _push(`<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M16.7 5.3a1 1 0 0 1 0 1.4l-7.5 7.5a1 1 0 0 1-1.4 0L3.3 9.7a1 1 0 1 1 1.4-1.4L8.5 12l6.8-6.8a1 1 0 0 1 1.4 0Z" clip-rule="evenodd"></path></svg>`);
            } else {
              _push(`<!---->`);
            }
            _push(`</button><div class="min-w-0 flex-1"><div class="flex items-center gap-2 flex-wrap"><h3 class="font-semibold text-slate-900">${ssrInterpolate(s.title)}</h3>`);
            if (s.is_required) {
              _push(`<span class="badge badge-amber">Required</span>`);
            } else {
              _push(`<span class="badge badge-slate">Optional</span>`);
            }
            _push(`</div>`);
            if (s.description) {
              _push(`<p class="text-sm text-slate-600 mt-1">${ssrInterpolate(s.description)}</p>`);
            } else {
              _push(`<!---->`);
            }
            if (s.resource_url) {
              _push(`<a${ssrRenderAttr("href", s.resource_url)} target="_blank" rel="noopener" class="text-xs text-sycamore-600 hover:underline mt-2 inline-flex items-center gap-1"> Open resource `);
              _push(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent));
              _push(`</a>`);
            } else {
              _push(`<!---->`);
            }
            _push(`</div></article>`);
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/onboarding.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=onboarding-gYxaZWCw.js.map
