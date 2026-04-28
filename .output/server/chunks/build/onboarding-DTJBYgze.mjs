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
  __name: "onboarding",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("onboarding_steps");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "title", label: "Title", required: true },
      { key: "description", label: "Description", type: "textarea" },
      {
        key: "category",
        label: "Category",
        type: "select",
        required: true,
        options: [
          { value: "general", label: "General" },
          { value: "paperwork", label: "Paperwork" },
          { value: "systems", label: "Systems & access" },
          { value: "culture", label: "Culture" },
          { value: "training", label: "Training" },
          { value: "product", label: "Product knowledge" },
          { value: "compliance", label: "Compliance" }
        ]
      },
      { key: "resource_url", label: "Resource URL", placeholder: "https://..." },
      { key: "display_order", label: "Display order", type: "number" },
      { key: "is_required", label: "Required step", type: "checkbox" },
      { key: "is_active", label: "Active", type: "checkbox" }
    ];
    const columns = [
      { key: "title", label: "Title" },
      { key: "category", label: "Category" },
      { key: "is_required", label: "Required", render: (r) => r.is_required ? "Yes" : "No" },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "category", ascending: true }, { column: "display_order", ascending: true }, { column: "title", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = { is_required: true, is_active: true, category: "general", display_order: 0 };
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
        const data = {
          title: payload.title,
          description: (_a = payload.description) != null ? _a : "",
          category: payload.category || "general",
          resource_url: (_b = payload.resource_url) != null ? _b : "",
          display_order: Number(payload.display_order) || 0,
          is_required: !!payload.is_required,
          is_active: payload.is_active === void 0 ? true : !!payload.is_active
        };
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
      if (!confirm(`Delete "${row.title}"?`)) return;
      try {
        await remove(row.id);
      } catch (e) {
        alert((_a = e.message) != null ? _a : "Failed to delete");
      }
    }
    return (_ctx, _push, _parent, _attrs) => {
      var _a;
      const _component_AdminList = _sfc_main$1;
      const _component_AdminEditor = _sfc_main$2;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-5xl" }, _attrs))}>`);
      _push(ssrRenderComponent(_component_AdminList, {
        title: "Onboarding steps",
        description: "The checklist new staff work through.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New step",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: ((_a = unref(editing)) == null ? void 0 : _a.id) ? "Edit step" : "New step",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/onboarding.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=onboarding-DTJBYgze.mjs.map
