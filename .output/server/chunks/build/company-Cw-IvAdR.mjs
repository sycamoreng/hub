import { u as useCrud, _ as _sfc_main$1, a as _sfc_main$2 } from './useCrud-Ds-PhTqf.mjs';
import { defineComponent, ref, withAsyncContext, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent } from 'vue/server-renderer';
import './SidebarIcon-B7VkmqYS.mjs';
import './supabase-DXLNwiqO.mjs';
import '@supabase/supabase-js';
import './server.mjs';
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
import 'vue-router';

const _sfc_main = /* @__PURE__ */ defineComponent({
  __name: "company",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("company_info");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "info_key", label: "Key", required: true, placeholder: "e.g. tagline, mission, founded_year", hint: "Identifier used in the app. Use snake_case." },
      { key: "info_value", label: "Value", type: "textarea", required: true },
      {
        key: "category",
        label: "Category",
        type: "select",
        options: [
          { value: "general", label: "General" },
          { value: "about", label: "About" },
          { value: "mission", label: "Mission & vision" },
          { value: "history", label: "History" },
          { value: "leadership", label: "Leadership" }
        ]
      },
      { key: "display_order", label: "Display order", type: "number" }
    ];
    const columns = [
      { key: "info_key", label: "Key" },
      { key: "category", label: "Category" },
      { key: "info_value", label: "Value", render: (r) => (r.info_value || "").slice(0, 80) + ((r.info_value || "").length > 80 ? "..." : "") }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "display_order", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = null;
      editorOpen.value = true;
    }
    function openEdit(row) {
      editing.value = { ...row };
      editorOpen.value = true;
    }
    async function save(payload) {
      var _a, _b;
      saving.value = true;
      try {
        const data = { info_key: payload.info_key, info_value: payload.info_value, category: payload.category || "general", display_order: Number(payload.display_order) || 0 };
        if ((_a = editing.value) == null ? void 0 : _a.id) await update(editing.value.id, { ...data, updated_at: (/* @__PURE__ */ new Date()).toISOString() });
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert((_b = e.message) != null ? _b : "Failed to save");
      } finally {
        saving.value = false;
      }
    }
    async function del(row) {
      var _a;
      if (!confirm(`Delete "${row.info_key}"?`)) return;
      try {
        await remove(row.id);
      } catch (e) {
        alert((_a = e.message) != null ? _a : "Failed to delete");
      }
    }
    return (_ctx, _push, _parent, _attrs) => {
      const _component_AdminList = _sfc_main$1;
      const _component_AdminEditor = _sfc_main$2;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-5xl" }, _attrs))}>`);
      _push(ssrRenderComponent(_component_AdminList, {
        title: "Company info",
        description: "Key-value content shown across the hub.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New info",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit info" : "New info",
        fields,
        initial: unref(editing),
        saving: unref(saving),
        onClose: ($event) => editorOpen.value = false,
        onSave: save
      }, null, _parent));
      _push(`</div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/company.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=company-Cw-IvAdR.mjs.map
