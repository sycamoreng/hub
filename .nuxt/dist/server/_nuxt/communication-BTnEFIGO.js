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
  __name: "communication",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("communication_tools");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "name", label: "Tool name", required: true },
      { key: "description", label: "Description", type: "textarea" },
      { key: "url", label: "URL", placeholder: "https://..." },
      {
        key: "category",
        label: "Category",
        type: "select",
        required: true,
        options: [
          { value: "messaging", label: "Messaging" },
          { value: "email", label: "Email" },
          { value: "video", label: "Video" },
          { value: "collaboration", label: "Collaboration" },
          { value: "project-management", label: "Project Management" },
          { value: "documentation", label: "Documentation" },
          { value: "general", label: "General" }
        ]
      },
      { key: "is_primary", label: "Primary tool", type: "checkbox", placeholder: "Highlight as recommended" }
    ];
    const columns = [
      { key: "name", label: "Name" },
      { key: "category", label: "Category" },
      { key: "is_primary", label: "Primary", render: (r) => r.is_primary ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "is_primary", ascending: false }, { column: "name", ascending: true }])), await __temp, __restore();
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
        const data = { name: payload.name, description: payload.description ?? "", url: payload.url ?? "", category: payload.category, is_primary: !!payload.is_primary };
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
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-5xl" }, _attrs))}>`);
      _push(ssrRenderComponent(_component_AdminList, {
        title: "Communication tools",
        description: "Platforms staff use to stay connected.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New tool",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit tool" : "New tool",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/communication.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=communication-BTnEFIGO.js.map
