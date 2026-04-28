import { u as useCrud, _ as _sfc_main$1, a as _sfc_main$2 } from "./useCrud-Ds-PhTqf.js";
import { defineComponent, ref, withAsyncContext, mergeProps, unref, useSSRContext } from "vue";
import { ssrRenderAttrs, ssrRenderComponent } from "vue/server-renderer";
import "/Users/macbookpro/Documents/work/intranet/node_modules/hookable/dist/index.mjs";
import "./SidebarIcon-B7VkmqYS.js";
import "./supabase-DXLNwiqO.js";
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
  __name: "locations",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("locations");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "name", label: "Office name", required: true },
      { key: "address", label: "Address" },
      { key: "city", label: "City", required: true },
      { key: "state", label: "State / Region" },
      { key: "country", label: "Country", required: true },
      {
        key: "location_type",
        label: "Type",
        type: "select",
        required: true,
        options: [
          { value: "headquarters", label: "Headquarters" },
          { value: "branch", label: "Branch" },
          { value: "satellite", label: "Satellite" },
          { value: "remote", label: "Remote hub" }
        ]
      },
      { key: "phone", label: "Phone", type: "tel" },
      { key: "email", label: "Email", type: "email" },
      { key: "timezone", label: "Timezone", placeholder: "e.g. Africa/Lagos" },
      { key: "is_headquarters", label: "Headquarters", type: "checkbox" }
    ];
    const columns = [
      { key: "name", label: "Name" },
      { key: "city", label: "City" },
      { key: "country", label: "Country" },
      { key: "is_headquarters", label: "HQ", render: (r) => r.is_headquarters ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "name", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = null;
      editorOpen.value = true;
    }
    function openEdit(row) {
      editing.value = { ...row };
      editorOpen.value = true;
    }
    async function save(payload) {
      saving.value = true;
      try {
        const data = {
          name: payload.name,
          address: payload.address ?? "",
          city: payload.city,
          state: payload.state ?? "",
          country: payload.country,
          location_type: payload.location_type,
          phone: payload.phone ?? "",
          email: payload.email ?? "",
          timezone: payload.timezone || "Africa/Lagos",
          is_headquarters: !!payload.is_headquarters
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
      if (!confirm(`Delete "${row.name}"?`)) return;
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
        title: "Locations",
        description: "Sycamore offices around the world.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New location",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit location" : "New location",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/locations.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=locations-wjb8tT6W.js.map
