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
      saving.value = true;
      try {
        const data = {
          name: payload.name,
          category: payload.category || "general",
          description: payload.description ?? "",
          used_for: payload.used_for ?? "",
          url: payload.url ?? "",
          display_order: Number(payload.display_order) || 0,
          is_active: payload.is_active === void 0 ? true : !!payload.is_active
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
        title: unref(editing)?.id ? "Edit technology" : "New technology",
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
export {
  _sfc_main as default
};
//# sourceMappingURL=technology-CrKeIsyg.js.map
