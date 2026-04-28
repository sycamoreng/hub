import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderComponent, ssrRenderList, ssrInterpolate, ssrRenderAttr } from "vue/server-renderer";
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
  __name: "leadership",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const leaders = ref([]);
    const loading = ref(true);
    const groups = computed(() => ({
      board: leaders.value.filter((l) => l.tier === "board"),
      executive: leaders.value.filter((l) => l.tier === "executive"),
      senior: leaders.value.filter((l) => l.tier === "senior")
    }));
    const sections = computed(() => [
      { key: "board", title: "Board of Directors", subtitle: "Strategic stewardship and governance.", items: groups.value.board },
      { key: "executive", title: "Executives", subtitle: "Leading day-to-day direction across the business.", items: groups.value.executive },
      { key: "senior", title: "Senior Management", subtitle: "Heads of teams driving execution.", items: groups.value.senior }
    ]);
    function initials(name) {
      return name.split(/\s+/).map((p) => p[0]).slice(0, 2).join("").toUpperCase();
    }
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-7xl mx-auto space-y-10" }, _attrs))}><div class="bg-gradient-to-br from-sycamore-700 to-sycamore-900 rounded-2xl p-6 sm:p-10 text-white relative overflow-hidden"><div class="relative z-10"><div class="badge bg-white/15 text-white border-white/20 mb-4">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "star" }, null, _parent));
      _push(`<span class="ml-1">Leadership</span></div><h1 class="text-3xl sm:text-4xl font-bold tracking-tight mb-3">The people steering Sycamore</h1><p class="text-sycamore-100 max-w-2xl">From the boardroom to senior management, meet the leaders shaping our direction.</p></div><div class="absolute -right-16 -bottom-16 w-80 h-80 rounded-full bg-white/5"></div><div class="absolute -right-8 -top-8 w-48 h-48 rounded-full bg-white/5"></div></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading leadership...</div>`);
      } else {
        _push(`<!--[-->`);
        ssrRenderList(unref(sections), (s) => {
          _push(`<section><div class="flex items-end justify-between mb-5"><div><h2 class="section-title">${ssrInterpolate(s.title)}</h2><p class="section-subtitle">${ssrInterpolate(s.subtitle)}</p></div><span class="badge badge-slate">${ssrInterpolate(s.items.length)}</span></div>`);
          if (s.items.length === 0) {
            _push(`<div class="card p-6 text-sm text-slate-400">No ${ssrInterpolate(s.title.toLowerCase())} listed yet.</div>`);
          } else {
            _push(`<div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-5"><!--[-->`);
            ssrRenderList(s.items, (l) => {
              _push(`<article class="card card-hover p-6"><div class="flex items-start gap-4"><div class="flex-shrink-0">`);
              if (l.photo_url) {
                _push(`<img${ssrRenderAttr("src", l.photo_url)}${ssrRenderAttr("alt", l.full_name)} class="w-16 h-16 rounded-full object-cover border border-slate-200">`);
              } else {
                _push(`<div class="w-16 h-16 rounded-full bg-gradient-to-br from-sycamore-500 to-sycamore-700 text-white flex items-center justify-center font-bold">${ssrInterpolate(initials(l.full_name))}</div>`);
              }
              _push(`</div><div class="min-w-0"><h3 class="font-bold text-slate-900 truncate">${ssrInterpolate(l.full_name)}</h3><div class="text-sm text-sycamore-700 font-medium">${ssrInterpolate(l.title)}</div></div></div>`);
              if (l.bio) {
                _push(`<p class="text-sm text-slate-600 mt-4 line-clamp-4">${ssrInterpolate(l.bio)}</p>`);
              } else {
                _push(`<!---->`);
              }
              if (l.email || l.phone || l.linkedin_url) {
                _push(`<div class="mt-4 pt-4 border-t border-slate-100 flex flex-wrap gap-3 text-xs">`);
                if (l.email) {
                  _push(`<a${ssrRenderAttr("href", `mailto:${l.email}`)} class="inline-flex items-center gap-1.5 text-slate-600 hover:text-sycamore-700">`);
                  _push(ssrRenderComponent(_component_SidebarIcon, { name: "mail" }, null, _parent));
                  _push(` Email </a>`);
                } else {
                  _push(`<!---->`);
                }
                if (l.phone) {
                  _push(`<a${ssrRenderAttr("href", `tel:${l.phone}`)} class="inline-flex items-center gap-1.5 text-slate-600 hover:text-sycamore-700">`);
                  _push(ssrRenderComponent(_component_SidebarIcon, { name: "phone" }, null, _parent));
                  _push(` Call </a>`);
                } else {
                  _push(`<!---->`);
                }
                if (l.linkedin_url) {
                  _push(`<a${ssrRenderAttr("href", l.linkedin_url)} target="_blank" rel="noopener" class="inline-flex items-center gap-1.5 text-slate-600 hover:text-sycamore-700">`);
                  _push(ssrRenderComponent(_component_SidebarIcon, { name: "arrow-right" }, null, _parent));
                  _push(` LinkedIn </a>`);
                } else {
                  _push(`<!---->`);
                }
                _push(`</div>`);
              } else {
                _push(`<!---->`);
              }
              _push(`</article>`);
            });
            _push(`<!--]--></div>`);
          }
          _push(`</section>`);
        });
        _push(`<!--]-->`);
      }
      _push(`</div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/leadership.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=leadership-Blgcu1oI.js.map
