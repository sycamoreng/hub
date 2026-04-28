import { _ as _sfc_main$1 } from './SidebarIcon-B7VkmqYS.mjs';
import { _ as __nuxt_component_0 } from './nuxt-link-nIAPCTWv.mjs';
import { defineComponent, mergeProps, unref, withCtx, createTextVNode, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent, ssrInterpolate } from 'vue/server-renderer';
import { u as useAuth } from './useAuth-DcwruT5Z.mjs';
import '../nitro/nitro.mjs';
import 'node:http';
import 'node:https';
import 'node:events';
import 'node:buffer';
import 'node:fs';
import 'node:path';
import 'node:crypto';
import 'node:url';
import './server.mjs';
import '../routes/renderer.mjs';
import 'vue-bundle-renderer/runtime';
import 'unhead/server';
import 'devalue';
import 'unhead/utils';
import 'unhead/plugins';
import 'vue-router';
import './supabase-DXLNwiqO.mjs';
import '@supabase/supabase-js';

const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "forbidden",
  __ssrInlineRender: true,
  setup(__props) {
    const { profile } = useAuth();
    return (_ctx, _push, _parent, _attrs) => {
      var _a, _b;
      const _component_SidebarIcon = _sfc_main$1;
      const _component_NuxtLink = __nuxt_component_0;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-2xl mx-auto py-12" }, _attrs))}><div class="card p-10 text-center"><div class="w-14 h-14 rounded-full bg-rose-50 text-rose-600 flex items-center justify-center mx-auto mb-5">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "alert" }, null, _parent));
      _push(`</div><h1 class="text-2xl font-bold text-slate-900 mb-2">Access restricted</h1><p class="text-slate-600 mb-1"> Hello ${ssrInterpolate(((_a = unref(profile)) == null ? void 0 : _a.name) || ((_b = unref(profile)) == null ? void 0 : _b.email) || "there")}, your account does not have admin permissions for this area. </p><p class="text-slate-500 text-sm mb-8"> If you believe you should have access, please contact a super-admin to request the appropriate role. </p><div class="flex items-center justify-center gap-3">`);
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/",
        class: "px-4 py-2 rounded-lg bg-sycamore-600 text-white text-sm font-medium hover:bg-sycamore-700"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`Back to hub`);
          } else {
            return [
              createTextVNode("Back to hub")
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(`<button class="px-4 py-2 rounded-lg border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50">Sign out</button></div></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/forbidden.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=forbidden-BY8zRkMn.mjs.map
