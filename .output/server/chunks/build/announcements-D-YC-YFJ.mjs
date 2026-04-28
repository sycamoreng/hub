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
  __name: "announcements",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("announcements");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "title", label: "Title", required: true, placeholder: "e.g. New office grand opening" },
      { key: "content", label: "Content", type: "textarea", required: true, placeholder: "What do you want to announce?" },
      {
        key: "priority",
        label: "Priority",
        type: "select",
        required: true,
        options: [
          { value: "low", label: "Low" },
          { value: "medium", label: "Medium" },
          { value: "high", label: "High" }
        ]
      },
      { key: "is_active", label: "Active", type: "checkbox", placeholder: "Visible on the homepage" },
      { key: "expires_at", label: "Expires at", type: "date", hint: "Optional. Leave blank if it never expires." }
    ];
    const columns = [
      { key: "title", label: "Title" },
      { key: "priority", label: "Priority" },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" },
      { key: "created_at", label: "Created", render: (r) => new Date(r.created_at).toLocaleDateString("en-GB") }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "created_at", ascending: false }])), await __temp, __restore();
    function openNew() {
      editing.value = null;
      editorOpen.value = true;
    }
    function openEdit(row) {
      editing.value = { ...row, expires_at: row.expires_at ? row.expires_at.slice(0, 10) : "" };
      editorOpen.value = true;
    }
    async function save(payload) {
      var _a, _b;
      saving.value = true;
      try {
        const data = {
          title: payload.title,
          content: payload.content,
          priority: payload.priority,
          is_active: !!payload.is_active,
          expires_at: payload.expires_at ? new Date(payload.expires_at).toISOString() : null
        };
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
        title: "Announcements",
        description: "Company-wide updates shown on the dashboard.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New announcement",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit announcement" : "New announcement",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/announcements.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=announcements-D-YC-YFJ.mjs.map
