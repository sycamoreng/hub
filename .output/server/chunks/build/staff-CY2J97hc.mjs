import { u as useCrud, _ as _sfc_main$1, a as _sfc_main$2 } from './useCrud-Ds-PhTqf.mjs';
import { defineComponent, ref, computed, withAsyncContext, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrRenderComponent } from 'vue/server-renderer';
import { u as useSupabase } from './supabase-DXLNwiqO.mjs';
import './SidebarIcon-B7VkmqYS.mjs';
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
  __name: "staff",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const supabase = useSupabase();
    const { items, loading, load, create, update, remove } = useCrud("staff_members");
    const departments = ref([]);
    const locations = ref([]);
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = computed(() => [
      { key: "full_name", label: "Full name", required: true },
      { key: "email", label: "Email", type: "email", required: true },
      { key: "phone", label: "Phone", type: "tel" },
      { key: "role", label: "Role / title", required: true, placeholder: "e.g. Senior Software Engineer" },
      {
        key: "department_id",
        label: "Department",
        type: "select",
        options: [{ value: "", label: "None" }, ...departments.value.map((d) => ({ value: d.id, label: d.name }))]
      },
      {
        key: "location_id",
        label: "Location",
        type: "select",
        options: [{ value: "", label: "None" }, ...locations.value.map((l) => ({ value: l.id, label: `${l.name} (${l.city})` }))]
      },
      { key: "joined_date", label: "Joined date", type: "date" },
      { key: "bio", label: "Bio", type: "textarea" },
      { key: "is_active", label: "Active", type: "checkbox", placeholder: "Currently employed" }
    ]);
    const columns = [
      { key: "full_name", label: "Name" },
      { key: "role", label: "Role" },
      { key: "email", label: "Email" },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(async () => Promise.all([
      load([{ column: "full_name", ascending: true }]),
      (async () => {
        const { data } = await supabase.from("departments").select("id, name").order("name");
        departments.value = data != null ? data : [];
      })(),
      (async () => {
        const { data } = await supabase.from("locations").select("id, name, city").order("name");
        locations.value = data != null ? data : [];
      })()
    ])), await __temp, __restore();
    function openNew() {
      editing.value = { is_active: true };
      editorOpen.value = true;
    }
    function openEdit(row) {
      var _a, _b, _c;
      editing.value = { ...row, department_id: (_a = row.department_id) != null ? _a : "", location_id: (_b = row.location_id) != null ? _b : "", joined_date: (_c = row.joined_date) != null ? _c : "" };
      editorOpen.value = true;
    }
    async function save(payload) {
      var _a, _b, _c, _d;
      saving.value = true;
      try {
        const data = {
          full_name: payload.full_name,
          email: payload.email,
          phone: (_a = payload.phone) != null ? _a : "",
          role: payload.role,
          department_id: payload.department_id || null,
          location_id: payload.location_id || null,
          joined_date: payload.joined_date || null,
          bio: (_b = payload.bio) != null ? _b : "",
          is_active: !!payload.is_active
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
      if (!confirm(`Delete "${row.full_name}"?`)) return;
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
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl" }, _attrs))}>`);
      _push(ssrRenderComponent(_component_AdminList, {
        title: "Staff",
        description: "Manage staff directory entries.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New staff member",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: ((_a = unref(editing)) == null ? void 0 : _a.id) ? "Edit staff member" : "New staff member",
        fields: unref(fields),
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/staff.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=staff-CY2J97hc.mjs.map
