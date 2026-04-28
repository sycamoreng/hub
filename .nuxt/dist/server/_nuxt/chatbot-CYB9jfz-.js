import { _ as _sfc_main$1 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, ref, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrIncludeBooleanAttr, ssrLooseContain, ssrInterpolate, ssrRenderAttr, ssrRenderClass, ssrRenderComponent } from "vue/server-renderer";
import { u as useSupabase } from "./supabase-DXLNwiqO.js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "@supabase/supabase-js";
import "../server.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ofetch/dist/node.mjs";
import "#internal/nuxt/paths";
import "/Users/macbookpro/Documents/work/intranet/node_modules/unctx/dist/index.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/h3/dist/index.mjs";
import "vue-router";
import "/Users/macbookpro/Documents/work/intranet/node_modules/defu/dist/defu.mjs";
import "/Users/macbookpro/Documents/work/intranet/node_modules/ufo/dist/index.mjs";
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "chatbot",
  __ssrInlineRender: true,
  setup(__props) {
    useSupabase();
    const settings = ref(null);
    const loading = ref(true);
    const saving = ref(false);
    const message = ref("");
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$1;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-3xl" }, _attrs))}><div class="mb-8"><h1 class="section-title">Chatbot settings</h1><p class="section-subtitle">Control how the AI assistant behaves for staff.</p></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading settings...</div>`);
      } else if (unref(settings)) {
        _push(`<form class="card p-6 space-y-5"><label class="flex items-start gap-3"><input type="checkbox"${ssrIncludeBooleanAttr(Array.isArray(unref(settings).is_enabled) ? ssrLooseContain(unref(settings).is_enabled, null) : unref(settings).is_enabled) ? " checked" : ""} class="mt-1 h-4 w-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-500"><span><span class="font-medium text-slate-900 block">Chatbot enabled</span><span class="text-xs text-slate-500">When off, the floating chat widget is hidden for everyone.</span></span></label><div><label class="block text-sm font-medium text-slate-800 mb-1">Welcome message</label><textarea rows="2" class="input">${ssrInterpolate(unref(settings).welcome_message)}</textarea><p class="text-xs text-slate-500 mt-1">Shown when a user opens the chat for the first time.</p></div><div><label class="block text-sm font-medium text-slate-800 mb-1">System prompt</label><textarea rows="6" class="input font-mono text-xs">${ssrInterpolate(unref(settings).system_prompt)}</textarea><p class="text-xs text-slate-500 mt-1">The base instruction the AI follows. Knowledgebase context is appended automatically.</p></div><div class="grid sm:grid-cols-2 gap-4"><div><label class="block text-sm font-medium text-slate-800 mb-1">Allowed topics</label><textarea rows="3" class="input">${ssrInterpolate(unref(settings).allowed_topics)}</textarea></div><div><label class="block text-sm font-medium text-slate-800 mb-1">Blocked topics</label><textarea rows="3" class="input">${ssrInterpolate(unref(settings).blocked_topics)}</textarea></div></div><div class="grid sm:grid-cols-2 gap-4"><div><label class="block text-sm font-medium text-slate-800 mb-1">Response tone</label><input${ssrRenderAttr("value", unref(settings).response_tone)} type="text" class="input" placeholder="e.g. friendly and professional"></div><div><label class="block text-sm font-medium text-slate-800 mb-1">Max messages / user / day</label><input${ssrRenderAttr("value", unref(settings).max_messages_per_user_per_day)} type="number" min="0" class="input"></div></div><div class="flex items-center justify-between pt-3 border-t border-slate-100"><div class="${ssrRenderClass([unref(message).startsWith("Settings saved") ? "text-leaf-700" : "text-rose-600", "text-sm"])}">${ssrInterpolate(unref(message))}</div><button type="submit"${ssrIncludeBooleanAttr(unref(saving)) ? " disabled" : ""} class="btn-primary">${ssrInterpolate(unref(saving) ? "Saving..." : "Save settings")}</button></div></form>`);
      } else {
        _push(`<!---->`);
      }
      _push(`<div class="card p-6 mt-6 bg-amber-50 border-amber-200"><div class="flex items-start gap-3"><div class="text-amber-700 mt-0.5">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "alert" }, null, _parent));
      _push(`</div><div><div class="font-semibold text-amber-900">API key required</div><p class="text-sm text-amber-800 mt-1">The chatbot uses Anthropic&#39;s Claude. Add an <code class="px-1 bg-white rounded">ANTHROPIC_API_KEY</code> secret in your Supabase project&#39;s edge function environment for the bot to respond.</p></div></div></div></div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/chatbot.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=chatbot-CYB9jfz-.js.map
