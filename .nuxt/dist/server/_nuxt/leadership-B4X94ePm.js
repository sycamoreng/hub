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
  __name: "leadership",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("leadership");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "full_name", label: "Full name", required: true },
      { key: "title", label: "Title / role", required: true },
      {
        key: "tier",
        label: "Tier",
        type: "select",
        required: true,
        options: [
          { value: "board", label: "Board of Directors" },
          { value: "executive", label: "Executives" },
          { value: "senior", label: "Senior Management" }
        ]
      },
      { key: "bio", label: "Bio", type: "textarea" },
      { key: "email", label: "Email", type: "email" },
      { key: "phone", label: "Phone", type: "tel" },
      { key: "photo_url", label: "Photo URL", placeholder: "https://..." },
      { key: "linkedin_url", label: "LinkedIn URL", placeholder: "https://..." },
      { key: "display_order", label: "Display order", type: "number" },
      { key: "is_active", label: "Active", type: "checkbox" }
    ];
    const tierLabels = {
      board: "Board",
      executive: "Executive",
      senior: "Senior Mgmt"
    };
    const columns = [
      { key: "full_name", label: "Name" },
      { key: "title", label: "Title" },
      { key: "tier", label: "Tier", render: (r) => tierLabels[r.tier] ?? r.tier },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "tier", ascending: true }, { column: "display_order", ascending: true }, { column: "full_name", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = { is_active: true, tier: "executive", display_order: 0 };
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
          full_name: payload.full_name,
          title: payload.title,
          tier: payload.tier,
          bio: payload.bio ?? "",
          email: payload.email ?? "",
          phone: payload.phone ?? "",
          photo_url: payload.photo_url ?? "",
          linkedin_url: payload.linkedin_url ?? "",
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
        title: "Leadership",
        description: "Board of directors, executives, and senior management.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New leader",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: unref(editing)?.id ? "Edit leader" : "New leader",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/leadership.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};
export {
  _sfc_main as default
};
//# sourceMappingURL=leadership-B4X94ePm.js.map
