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
  __name: "branding",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("branding_guidelines");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "element_name", label: "Element name", required: true },
      { key: "description", label: "Description", type: "textarea" },
      { key: "guidelines", label: "Guidelines", type: "textarea", placeholder: "Detailed guidelines." },
      {
        key: "category",
        label: "Category",
        type: "select",
        required: true,
        options: [
          { value: "visual", label: "Visual" },
          { value: "communication", label: "Communication" },
          { value: "template", label: "Template" }
        ]
      },
      { key: "display_order", label: "Display order", type: "number" }
    ];
    const columns = [
      { key: "element_name", label: "Element" },
      { key: "category", label: "Category" },
      { key: "display_order", label: "Order" }
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
      var _a, _b, _c, _d;
      saving.value = true;
      try {
        const data = { element_name: payload.element_name, description: (_a = payload.description) != null ? _a : "", guidelines: (_b = payload.guidelines) != null ? _b : "", category: payload.category, display_order: Number(payload.display_order) || 0 };
        if ((_c = editing.value) == null ? void 0 : _c.id) await update(editing.value.id, data);
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert((_d = e.message) != null ? _d : "Failed to save");
      } finally {
        saving.value = false;
      }
    }
    async function del(row) {
      var _a;
      if (!confirm(`Delete "${row.element_name}"?`)) return;
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
        title: "Branding guidelines",
        description: "Visual, communication and template guidelines.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New guideline",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit guideline" : "New guideline",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/branding.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=branding-zQv8n5gb.mjs.map
