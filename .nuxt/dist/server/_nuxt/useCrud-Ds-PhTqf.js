import { _ as _sfc_main$2 } from "./SidebarIcon-B7VkmqYS.js";
import { defineComponent, useSSRContext, ref, watch, unref } from "vue";
import { ssrRenderAttrs, ssrInterpolate, ssrRenderComponent, ssrRenderList, ssrRenderClass, ssrRenderTeleport, ssrRenderAttr, ssrIncludeBooleanAttr, ssrLooseContain, ssrLooseEqual, ssrRenderDynamicModel } from "vue/server-renderer";
import { u as useSupabase } from "./supabase-DXLNwiqO.js";
const _sfc_main$1 = /* @__PURE__ */ defineComponent({
  __name: "AdminList",
  __ssrInlineRender: true,
  props: {
    title: {},
    description: {},
    columns: {},
    rows: {},
    loading: { type: Boolean },
    newLabel: {}
  },
  emits: ["new", "edit", "delete"],
  setup(__props, { emit: __emit }) {
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$2;
      _push(`<div${ssrRenderAttrs(_attrs)}><div class="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-6"><div><h1 class="section-title">${ssrInterpolate(__props.title)}</h1>`);
      if (__props.description) {
        _push(`<p class="section-subtitle">${ssrInterpolate(__props.description)}</p>`);
      } else {
        _push(`<!---->`);
      }
      _push(`</div><button class="btn-primary">`);
      _push(ssrRenderComponent(_component_SidebarIcon, { name: "plus" }, null, _parent));
      _push(` ${ssrInterpolate(__props.newLabel ?? "New")}</button></div><div class="card overflow-hidden">`);
      if (__props.loading) {
        _push(`<div class="p-8 text-center text-slate-400 text-sm">Loading...</div>`);
      } else if (__props.rows.length === 0) {
        _push(`<div class="p-8 text-center text-slate-400 text-sm">No items yet. Create one to get started.</div>`);
      } else {
        _push(`<div><!--[-->`);
        ssrRenderList(__props.rows, (row) => {
          _push(`<div class="flex items-center gap-4 px-5 py-4 border-b border-slate-100 last:border-0 hover:bg-slate-50"><div class="flex-1 grid grid-cols-1 md:grid-cols-4 gap-2 md:gap-4 min-w-0"><!--[-->`);
          ssrRenderList(__props.columns, (c) => {
            _push(`<div class="text-sm text-slate-700 min-w-0"><div class="md:hidden text-xs text-slate-400 mb-0.5">${ssrInterpolate(c.label)}</div><div class="${ssrRenderClass([{ "font-medium text-slate-900": c.key === __props.columns[0].key }, "truncate"])}">${ssrInterpolate(c.render ? c.render(row) : row[c.key])}</div></div>`);
          });
          _push(`<!--]--></div><div class="flex gap-1 shrink-0"><button class="p-2 rounded-lg hover:bg-sycamore-50 text-slate-600 hover:text-sycamore-700" aria-label="Edit">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "edit" }, null, _parent));
          _push(`</button><button class="p-2 rounded-lg hover:bg-rose-50 text-slate-600 hover:text-rose-700" aria-label="Delete">`);
          _push(ssrRenderComponent(_component_SidebarIcon, { name: "trash" }, null, _parent));
          _push(`</button></div></div>`);
        });
        _push(`<!--]--></div>`);
      }
      _push(`</div></div>`);
    };
  }
});
const _sfc_setup$1 = _sfc_main$1.setup;
_sfc_main$1.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("components/AdminList.vue");
  return _sfc_setup$1 ? _sfc_setup$1(props, ctx) : void 0;
};
const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "AdminEditor",
  __ssrInlineRender: true,
  props: {
    open: { type: Boolean },
    title: {},
    fields: {},
    initial: {},
    saving: { type: Boolean }
  },
  emits: ["close", "save"],
  setup(__props, { emit: __emit }) {
    const props = __props;
    const form = ref({});
    const errors = ref({});
    watch(() => [props.open, props.initial], () => {
      if (props.open) {
        form.value = {};
        for (const f of props.fields) {
          const v = props.initial?.[f.key];
          form.value[f.key] = v ?? (f.type === "checkbox" ? false : "");
        }
        errors.value = {};
      }
    }, { immediate: true });
    return (_ctx, _push, _parent, _attrs) => {
      const _component_SidebarIcon = _sfc_main$2;
      ssrRenderTeleport(_push, (_push2) => {
        if (__props.open) {
          _push2(`<div class="fixed inset-0 z-50 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center p-4"><div class="bg-white rounded-2xl shadow-xl max-w-2xl w-full max-h-[90vh] flex flex-col"><header class="flex items-center justify-between p-6 border-b border-slate-100"><h2 class="text-xl font-bold text-slate-900">${ssrInterpolate(__props.title)}</h2><button class="p-2 rounded-lg hover:bg-slate-100" aria-label="Close">`);
          _push2(ssrRenderComponent(_component_SidebarIcon, { name: "close" }, null, _parent));
          _push2(`</button></header><form class="flex-1 overflow-y-auto p-6 space-y-5"><!--[-->`);
          ssrRenderList(__props.fields, (f) => {
            _push2(`<div><label${ssrRenderAttr("for", `f-${f.key}`)} class="block text-sm font-medium text-slate-700 mb-1.5">${ssrInterpolate(f.label)}`);
            if (f.required) {
              _push2(`<span class="text-rose-600 ml-0.5">*</span>`);
            } else {
              _push2(`<!---->`);
            }
            _push2(`</label>`);
            if (f.type === "textarea") {
              _push2(`<textarea${ssrRenderAttr("id", `f-${f.key}`)}${ssrRenderAttr("placeholder", f.placeholder)} rows="5" class="input">${ssrInterpolate(unref(form)[f.key])}</textarea>`);
            } else if (f.type === "select") {
              _push2(`<select${ssrRenderAttr("id", `f-${f.key}`)} class="input"><option value="" disabled${ssrIncludeBooleanAttr(Array.isArray(unref(form)[f.key]) ? ssrLooseContain(unref(form)[f.key], "") : ssrLooseEqual(unref(form)[f.key], "")) ? " selected" : ""}>Select...</option><!--[-->`);
              ssrRenderList(f.options, (o) => {
                _push2(`<option${ssrRenderAttr("value", o.value)}${ssrIncludeBooleanAttr(Array.isArray(unref(form)[f.key]) ? ssrLooseContain(unref(form)[f.key], o.value) : ssrLooseEqual(unref(form)[f.key], o.value)) ? " selected" : ""}>${ssrInterpolate(o.label)}</option>`);
              });
              _push2(`<!--]--></select>`);
            } else if (f.type === "checkbox") {
              _push2(`<label class="flex items-center gap-2 select-none cursor-pointer"><input${ssrRenderAttr("id", `f-${f.key}`)} type="checkbox"${ssrIncludeBooleanAttr(Array.isArray(unref(form)[f.key]) ? ssrLooseContain(unref(form)[f.key], null) : unref(form)[f.key]) ? " checked" : ""} class="w-4 h-4 rounded border-slate-300 text-sycamore-600 focus:ring-sycamore-300"><span class="text-sm text-slate-700">${ssrInterpolate(f.placeholder ?? "Enabled")}</span></label>`);
            } else {
              _push2(`<input${ssrRenderAttr("id", `f-${f.key}`)}${ssrRenderAttr("type", f.type ?? "text")}${ssrRenderDynamicModel(f.type ?? "text", unref(form)[f.key], null)}${ssrRenderAttr("placeholder", f.placeholder)} class="input">`);
            }
            if (unref(errors)[f.key]) {
              _push2(`<p class="text-xs text-rose-600 mt-1.5">${ssrInterpolate(unref(errors)[f.key])}</p>`);
            } else if (f.hint) {
              _push2(`<p class="text-xs text-slate-500 mt-1.5">${ssrInterpolate(f.hint)}</p>`);
            } else {
              _push2(`<!---->`);
            }
            _push2(`</div>`);
          });
          _push2(`<!--]--></form><footer class="flex items-center justify-end gap-3 p-6 border-t border-slate-100"><button type="button" class="btn-secondary">Cancel</button><button type="button" class="btn-primary"${ssrIncludeBooleanAttr(__props.saving) ? " disabled" : ""}>`);
          if (__props.saving) {
            _push2(`<span>Saving...</span>`);
          } else {
            _push2(`<span>Save</span>`);
          }
          _push2(`</button></footer></div></div>`);
        } else {
          _push2(`<!---->`);
        }
      }, "body", false, _parent);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("components/AdminEditor.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
function useCrud(table) {
  const supabase = useSupabase();
  const items = ref([]);
  const loading = ref(false);
  const error = ref(null);
  async function load(orderBy = [{ column: "created_at", ascending: false }]) {
    loading.value = true;
    error.value = null;
    try {
      let q = supabase.from(table).select("*");
      for (const o of orderBy) q = q.order(o.column, { ascending: o.ascending ?? true });
      const { data, error: e } = await q;
      if (e) throw e;
      items.value = data ?? [];
    } catch (e) {
      error.value = e.message ?? "Failed to load";
    } finally {
      loading.value = false;
    }
  }
  async function create(payload) {
    const { data, error: e } = await supabase.from(table).insert(payload).select().maybeSingle();
    if (e) throw e;
    if (data) items.value.unshift(data);
    return data;
  }
  async function update(id, payload) {
    const { data, error: e } = await supabase.from(table).update(payload).eq("id", id).select().maybeSingle();
    if (e) throw e;
    if (data) {
      const idx = items.value.findIndex((i) => i.id === id);
      if (idx >= 0) items.value[idx] = data;
    }
    return data;
  }
  async function remove(id) {
    const { error: e } = await supabase.from(table).delete().eq("id", id);
    if (e) throw e;
    items.value = items.value.filter((i) => i.id !== id);
  }
  return { items, loading, error, load, create, update, remove };
}
export {
  _sfc_main$1 as _,
  _sfc_main as a,
  useCrud as u
};
//# sourceMappingURL=useCrud-Ds-PhTqf.js.map
