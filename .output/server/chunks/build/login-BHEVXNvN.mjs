import { _ as __nuxt_component_0 } from './nuxt-link-nIAPCTWv.mjs';
import { defineComponent, ref, watchEffect, mergeProps, unref, withCtx, createTextVNode, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderAttr, ssrIncludeBooleanAttr, ssrInterpolate, ssrRenderComponent } from 'vue/server-renderer';
import { _ as _imports_0 } from './virtual_public-IWZl7zz2.mjs';
import { _ as _imports_0$1 } from './virtual_public-BhHsw8T-.mjs';
import { u as useAuth } from './useAuth-DcwruT5Z.mjs';
import { u as useRoute } from './server.mjs';
import '../nitro/nitro.mjs';
import 'node:http';
import 'node:https';
import 'node:events';
import 'node:buffer';
import 'node:fs';
import 'node:path';
import 'node:crypto';
import 'node:url';
import '../routes/renderer.mjs';
import 'vue-bundle-renderer/runtime';
import 'unhead/server';
import 'devalue';
import 'unhead/utils';
import 'unhead/plugins';
import './supabase-DXLNwiqO.mjs';
import '@supabase/supabase-js';
import 'vue-router';

const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "login",
  __ssrInlineRender: true,
  setup(__props) {
    const { domainError } = useAuth();
    useRoute();
    const error = ref(null);
    const loading = ref(false);
    watchEffect(() => {
      if (domainError.value) error.value = domainError.value;
    });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_NuxtLink = __nuxt_component_0;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "min-h-screen flex bg-slate-50" }, _attrs))}><div class="hidden lg:flex flex-col justify-between w-1/2 bg-gradient-to-br from-sycamore-700 to-sycamore-900 text-white p-12 relative overflow-hidden"><div class="relative z-10"><div class="mb-12"><img${ssrRenderAttr("src", _imports_0)} alt="Sycamore" class="h-9 w-auto brightness-0 invert"></div><h1 class="text-4xl font-bold tracking-tight mb-4 max-w-md">Welcome to the Sycamore Information Hub.</h1><p class="text-sycamore-50 max-w-md">Sign in with your Sycamore Google account to access company knowledge, products, policies, and more.</p></div><div class="relative z-10 text-sm text-sycamore-100/80">sycamore.ng \xA9 2025</div><div class="absolute -right-24 -bottom-24 w-96 h-96 rounded-full bg-white/5"></div><div class="absolute -right-8 top-32 w-48 h-48 rounded-full bg-white/5"></div></div><div class="flex-1 flex items-center justify-center p-6"><div class="w-full max-w-md"><div class="lg:hidden mb-8 flex justify-center"><img${ssrRenderAttr("src", _imports_0)} alt="Sycamore" class="h-9 w-auto"></div><div class="card p-8 sm:p-10"><div class="w-14 h-14 rounded-full bg-sycamore-50 flex items-center justify-center mx-auto mb-5"><img${ssrRenderAttr("src", _imports_0$1)} alt="" class="w-9 h-9"></div><h2 class="text-2xl font-bold text-slate-900 text-center mb-2">Sign in to continue</h2><p class="text-sm text-slate-500 text-center mb-8">Use your Sycamore Google account to access the hub.</p><button type="button"${ssrIncludeBooleanAttr(unref(loading)) ? " disabled" : ""} class="w-full flex items-center justify-center gap-3 px-4 py-3 rounded-lg border border-slate-300 bg-white text-slate-800 text-sm font-semibold hover:bg-slate-50 disabled:opacity-60 transition-colors"><svg class="w-5 h-5" viewBox="0 0 48 48" aria-hidden="true"><path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z"></path><path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 16.1 19 13 24 13c3 0 5.8 1.1 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4c-7.6 0-14.2 4.3-17.7 10.7z"></path><path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-7.9l-6.5 5C9.7 39.7 16.3 44 24 44z"></path><path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.3-2.2 4.2-4.1 5.6l6.2 5.2C41.1 35.7 44 30.3 44 24c0-1.3-.1-2.4-.4-3.5z"></path></svg> ${ssrInterpolate(unref(loading) ? "Redirecting to Google..." : "Continue with Google")}</button>`);
      if (unref(error)) {
        _push(`<div class="mt-4 text-sm text-rose-700 bg-rose-50 border border-rose-200 rounded-lg p-3">${ssrInterpolate(unref(error))}</div>`);
      } else {
        _push(`<!---->`);
      }
      _push(`<p class="text-xs text-slate-400 text-center mt-6"> Access is limited to <span class="font-semibold text-slate-500">@sycamore.ng</span> and <span class="font-semibold text-slate-500">@sycamoreglobal.co.uk</span> Google accounts. </p></div><div class="mt-6 text-center">`);
      _push(ssrRenderComponent(_component_NuxtLink, {
        to: "/",
        class: "text-xs text-slate-500 hover:text-slate-700"
      }, {
        default: withCtx((_, _push2, _parent2, _scopeId) => {
          if (_push2) {
            _push2(`\u2190 Back to information hub`);
          } else {
            return [
              createTextVNode("\u2190 Back to information hub")
            ];
          }
        }),
        _: 1
      }, _parent));
      _push(`</div></div></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/login.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=login-BHEVXNvN.mjs.map
