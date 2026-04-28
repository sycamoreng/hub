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
  __name: "events",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("holidays_events");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "title", label: "Title", required: true },
      { key: "description", label: "Description", type: "textarea" },
      { key: "event_date", label: "Event date", type: "date", required: true },
      { key: "end_date", label: "End date", type: "date", hint: "Optional. For multi-day events." },
      {
        key: "event_type",
        label: "Type",
        type: "select",
        required: true,
        options: [
          { value: "event", label: "Event" },
          { value: "holiday", label: "Holiday" },
          { value: "company", label: "Company" },
          { value: "training", label: "Training" }
        ]
      },
      { key: "is_recurring", label: "Recurring", type: "checkbox", placeholder: "Repeats annually" }
    ];
    const columns = [
      { key: "title", label: "Title" },
      { key: "event_type", label: "Type" },
      { key: "event_date", label: "Date", render: (r) => new Date(r.event_date).toLocaleDateString("en-GB") },
      { key: "is_recurring", label: "Recurring", render: (r) => r.is_recurring ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "event_date", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = null;
      editorOpen.value = true;
    }
    function openEdit(row) {
      var _a, _b;
      editing.value = { ...row, event_date: (_a = row.event_date) != null ? _a : "", end_date: (_b = row.end_date) != null ? _b : "" };
      editorOpen.value = true;
    }
    async function save(payload) {
      var _a, _b, _c;
      saving.value = true;
      try {
        const data = {
          title: payload.title,
          description: (_a = payload.description) != null ? _a : "",
          event_date: payload.event_date,
          end_date: payload.end_date || null,
          event_type: payload.event_type,
          is_recurring: !!payload.is_recurring
        };
        if ((_b = editing.value) == null ? void 0 : _b.id) await update(editing.value.id, data);
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert((_c = e.message) != null ? _c : "Failed to save");
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
        title: "Events & Holidays",
        description: "Calendar events, public holidays, and important dates.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New event",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit event" : "New event",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/events.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=events-NEjsAMcp.mjs.map
