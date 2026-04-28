import { u as useCrud, _ as _sfc_main$1, a as _sfc_main$2 } from "./useCrud-Ds-PhTqf.js";
import { defineComponent, ref, computed, withAsyncContext, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderComponent } from "vue/server-renderer";
import { u as useSupabase } from "./supabase-DXLNwiqO.js";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "./SidebarIcon-B7VkmqYS.js";
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
        departments.value = data ?? [];
      })(),
      (async () => {
        const { data } = await supabase.from("locations").select("id, name, city").order("name");
        locations.value = data ?? [];
      })()
    ])), await __temp, __restore();
    function openNew() {
      editing.value = { is_active: true };
      editorOpen.value = true;
    }
    function openEdit(row) {
      editing.value = { ...row, department_id: row.department_id ?? "", location_id: row.location_id ?? "", joined_date: row.joined_date ?? "" };
      editorOpen.value = true;
    }
    async function save(payload) {
      saving.value = true;
      try {
        const data = {
          full_name: payload.full_name,
          email: payload.email,
          phone: payload.phone ?? "",
          role: payload.role,
          department_id: payload.department_id || null,
          location_id: payload.location_id || null,
          joined_date: payload.joined_date || null,
          bio: payload.bio ?? "",
          is_active: !!payload.is_active
        };
        if (editing.value?.id) await update(editing.value.id, data);
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert(e.message ?? "Failed to save");
      } finally {
        saving.value = false;
      }
    }
    async function del(row) {
      if (!confirm(`Delete "${row.full_name}"?`)) return;
      try {
        await remove(row.id);
      } catch (e) {
        alert(e.message ?? "Failed to delete");
      }
    }
    return (_ctx, _push, _parent, _attrs) => {
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
        title: unref(editing)?.id ? "Edit staff member" : "New staff member",
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
export {
  _sfc_main as default
};
//# sourceMappingURL=staff-CY2J97hc.js.map
