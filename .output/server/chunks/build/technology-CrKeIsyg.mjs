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
  __name: "technology",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("tech_stack");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "name", label: "Technology", required: true },
      {
        key: "category",
        label: "Category",
        type: "select",
        required: true,
        options: [
          { value: "language", label: "Language" },
          { value: "framework", label: "Framework" },
          { value: "database", label: "Database" },
          { value: "cloud", label: "Cloud / infra" },
          { value: "devops", label: "DevOps" },
          { value: "data", label: "Data & analytics" },
          { value: "security", label: "Security" },
          { value: "observability", label: "Observability" },
          { value: "tooling", label: "Tooling" },
          { value: "general", label: "General" }
        ]
      },
      { key: "description", label: "Description", type: "textarea" },
      { key: "used_for", label: "Used for", placeholder: "e.g. Backend services for payments" },
      { key: "url", label: "Reference URL", placeholder: "https://..." },
      { key: "display_order", label: "Display order", type: "number" },
      { key: "is_active", label: "Active", type: "checkbox" }
    ];
    const columns = [
      { key: "name", label: "Name" },
      { key: "category", label: "Category" },
      { key: "used_for", label: "Used for" },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "category", ascending: true }, { column: "display_order", ascending: true }, { column: "name", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = { is_active: true, category: "general", display_order: 0 };
      editorOpen.value = true;
    }
    function openEdit(row) {
      editing.value = { ...row };
      editorOpen.value = true;
    }
    async function save(payload) {
      var _a, _b, _c, _d, _e;
      saving.value = true;
      try {
        const data = {
          name: payload.name,
          category: payload.category || "general",
          description: (_a = payload.description) != null ? _a : "",
          used_for: (_b = payload.used_for) != null ? _b : "",
          url: (_c = payload.url) != null ? _c : "",
          display_order: Number(payload.display_order) || 0,
          is_active: payload.is_active === void 0 ? true : !!payload.is_active
        };
        if ((_d = editing.value) == null ? void 0 : _d.id) await update(editing.value.id, data);
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert((_e = e.message) != null ? _e : "Failed to save");
      } finally {
        saving.value = false;
      }
    }
    async function del(row) {
      var _a;
      if (!confirm(`Delete "${row.name}"?`)) return;
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
        title: "Technology stack",
        description: "The tools and platforms our teams use.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New technology",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: ((_a = unref(editing)) == null ? void 0 : _a.id) ? "Edit technology" : "New technology",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/technology.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=technology-CrKeIsyg.mjs.map
