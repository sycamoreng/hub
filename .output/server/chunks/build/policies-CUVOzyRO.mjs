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
  __name: "policies",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("policies");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "title", label: "Title", required: true },
      { key: "content", label: "Content", type: "textarea", required: true, placeholder: "Full policy text. Line breaks are preserved." },
      {
        key: "category",
        label: "Category",
        type: "select",
        required: true,
        options: [
          { value: "HR", label: "HR" },
          { value: "Finance", label: "Finance" },
          { value: "IT", label: "IT" },
          { value: "Legal", label: "Legal" },
          { value: "Operations", label: "Operations" },
          { value: "Marketing", label: "Marketing" }
        ]
      },
      { key: "effective_date", label: "Effective date", type: "date", required: true },
      { key: "is_active", label: "Active", type: "checkbox", placeholder: "Visible to staff" }
    ];
    const columns = [
      { key: "title", label: "Title" },
      { key: "category", label: "Category" },
      { key: "effective_date", label: "Effective", render: (r) => new Date(r.effective_date).toLocaleDateString("en-GB") },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "category", ascending: true }, { column: "title", ascending: true }])), await __temp, __restore();
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
        const data = { title: payload.title, content: payload.content, category: payload.category, effective_date: payload.effective_date, is_active: !!payload.is_active };
        if ((_a = editing.value) == null ? void 0 : _a.id) await update(editing.value.id, data);
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
      if (!confirm(`Delete "${row.title}"?`)) return;
      try {
        await remove(row.id);
      } catch (e) {
        alert((_a = e.message) != null ? _a : "Failed to delete");
      }
    }
    return (_ctx, _push, _parent, _attrs) => {
      const _component_AdminList = _sfc_main$1;
      const _component_AdminEditor = _sfc_main$2;
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl" }, _attrs))}>`);
      _push(ssrRenderComponent(_component_AdminList, {
        title: "Policies",
        description: "Company policies and guidelines.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New policy",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit policy" : "New policy",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/policies.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=policies-CUVOzyRO.mjs.map
