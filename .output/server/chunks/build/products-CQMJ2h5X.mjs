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
  __name: "products",
  __ssrInlineRender: true,
  async setup(__props) {
    let __temp, __restore;
    const { items, loading, load, create, update, remove } = useCrud("products");
    const editorOpen = ref(false);
    const editing = ref(null);
    const saving = ref(false);
    const fields = [
      { key: "name", label: "Product name", required: true },
      { key: "tagline", label: "Tagline", placeholder: "One sentence summary" },
      { key: "description", label: "Description", type: "textarea" },
      {
        key: "category",
        label: "Category",
        type: "select",
        required: true,
        options: [
          { value: "payments", label: "Payments" },
          { value: "lending", label: "Lending" },
          { value: "savings", label: "Savings & investments" },
          { value: "banking", label: "Banking" },
          { value: "cards", label: "Cards" },
          { value: "business", label: "Business / B2B" },
          { value: "consumer", label: "Consumer / B2C" },
          { value: "infrastructure", label: "Infrastructure / API" },
          { value: "general", label: "General" }
        ]
      },
      {
        key: "status",
        label: "Status",
        type: "select",
        required: true,
        options: [
          { value: "live", label: "Live" },
          { value: "beta", label: "Beta" },
          { value: "internal", label: "Internal" },
          { value: "retired", label: "Retired" }
        ]
      },
      { key: "target_market", label: "Target market", placeholder: "e.g. SMEs in Nigeria" },
      { key: "url", label: "Product URL", placeholder: "https://..." },
      { key: "display_order", label: "Display order", type: "number" },
      { key: "is_active", label: "Active", type: "checkbox" }
    ];
    const columns = [
      { key: "name", label: "Name" },
      { key: "category", label: "Category" },
      { key: "status", label: "Status" },
      { key: "is_active", label: "Active", render: (r) => r.is_active ? "Yes" : "No" }
    ];
    [__temp, __restore] = withAsyncContext(() => load([{ column: "display_order", ascending: true }, { column: "name", ascending: true }])), await __temp, __restore();
    function openNew() {
      editing.value = { is_active: true, status: "live", category: "general", display_order: 0 };
      editorOpen.value = true;
    }
    function openEdit(row) {
      editing.value = { ...row };
      editorOpen.value = true;
    }
    async function save(payload) {
      var _a, _b, _c, _d, _e, _f;
      saving.value = true;
      try {
        const data = {
          name: payload.name,
          tagline: (_a = payload.tagline) != null ? _a : "",
          description: (_b = payload.description) != null ? _b : "",
          category: payload.category || "general",
          status: payload.status || "live",
          target_market: (_c = payload.target_market) != null ? _c : "",
          url: (_d = payload.url) != null ? _d : "",
          display_order: Number(payload.display_order) || 0,
          is_active: payload.is_active === void 0 ? true : !!payload.is_active
        };
        if ((_e = editing.value) == null ? void 0 : _e.id) await update(editing.value.id, data);
        else await create(data);
        editorOpen.value = false;
      } catch (e) {
        alert((_f = e.message) != null ? _f : "Failed to save");
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
        title: "Products",
        description: "Sycamore's fintech offerings.",
        columns,
        rows: unref(items),
        loading: unref(loading),
        "new-label": "New product",
        onNew: openNew,
        onEdit: openEdit,
        onDelete: del
      }, null, _parent));
      _push(ssrRenderComponent(_component_AdminEditor, {
        open: unref(editorOpen),
        title: ((_a = unref(editing)) == null ? void 0 : _a.id) ? "Edit product" : "New product",
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
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/admin/products.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=products-CQMJ2h5X.mjs.map
