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
  __name: "company",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("company_info");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "info_key", label: "Key", required: true, placeholder: "e.g. tagline, mission, founded_year", hint: "Identifier used in the app. Use snake_case." },
      { key: "info_value", label: "Value", type: "textarea", required: true },
      {
        key: "category",
        label: "Category",
        type: "select",
        options: [
          { value: "general", label: "General" },
          { value: "about", label: "About" },
          { value: "mission", label: "Mission & vision" },
          { value: "history", label: "History" },
          { value: "leadership", label: "Leadership" }
        ]
      },
      { key: "display_order", label: "Display order", type: "number" }
    ];
    const columns = [
      { key: "info_key", label: "Key" },
      { key: "category", label: "Category" },
      { key: "info_value", label: "Value", render: (r) => (r.info_value || "").slice(0, 80) + ((r.info_value || "").length > 80 ? "..." : "") }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "display_order", ascending: true }])), await __temp, __restore();
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
        const data = { info_key: payload.info_key, info_value: payload.info_value, category: payload.category || "general", display_order: Number(payload.display_order) || 0 };
        if (editing.value?.id) await update(editing.value.id, { ...data, updated_at: (/* @__PURE__ */ new Date()).toISOString() });
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert(e.message ?? "Failed to save");
      } finally {
        saving.value = false;
      }
    }
    async function del(row) {
      if (!confirm(`Delete "${row.info_key}"?`)) return;
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
        title: "Company info",
        description: "Key-value content shown across the hub.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New info",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing) ? "Edit info" : "New info",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/company.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=company-Cw-IvAdR.js.map
