import { defineComponent, ref, computed, mergeProps, unref, useSSRContext } from 'vue';
import { ssrRenderAttrs, ssrInterpolate, ssrRenderList, ssrRenderClass } from 'vue/server-renderer';
import { u as useCompanyData } from './useCompanyData-CSkVUIju.mjs';
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
  __name: "calendar",
  __ssrInlineRender: true,
  setup(__props) {
    useCompanyData();
    const events = ref([]);
    const loading = ref(true);
    const today = /* @__PURE__ */ new Date();
    const todayKey = ymd(today);
    const cursor = ref({ year: today.getFullYear(), month: today.getMonth() });
    function ymd(d) {
      const y = d.getFullYear();
      const m = String(d.getMonth() + 1).padStart(2, "0");
      const day = String(d.getDate()).padStart(2, "0");
      return `${y}-${m}-${day}`;
    }
    function parseLocalDate(s) {
      if (!s) return null;
      const parts = s.slice(0, 10).split("-").map(Number);
      if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) return null;
      return new Date(parts[0], parts[1] - 1, parts[2]);
    }
    function expandRecurring(e, year) {
      const base = parseLocalDate(e.event_date);
      if (!base) return [];
      if (!e.is_recurring) return [{ date: e.event_date.slice(0, 10), e }];
      const out = [];
      for (let y = year - 1; y <= year + 1; y++) {
        const d = new Date(y, base.getMonth(), base.getDate());
        out.push({ date: ymd(d), e });
      }
      return out;
    }
    const eventsByDate = computed(() => {
      const map = {};
      for (const e of events.value) {
        for (const inst of expandRecurring(e, cursor.value.year)) {
          if (!map[inst.date]) map[inst.date] = [];
          map[inst.date].push(inst.e);
        }
      }
      return map;
    });
    const monthLabel = computed(
      () => new Date(cursor.value.year, cursor.value.month, 1).toLocaleDateString("en-GB", { month: "long", year: "numeric" })
    );
    const weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const grid = computed(() => {
      const { year, month } = cursor.value;
      const first = new Date(year, month, 1);
      const startOffset = (first.getDay() + 6) % 7;
      const start = new Date(year, month, 1 - startOffset);
      const cells = [];
      for (let i = 0; i < 42; i++) {
        const d = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
        const key = ymd(d);
        cells.push({
          date: d,
          key,
          inMonth: d.getMonth() === month,
          isToday: key === todayKey,
          events: eventsByDate.value[key] || []
        });
      }
      return cells;
    });
    const selectedKey = ref(null);
    const selectedEvents = computed(() => selectedKey.value ? eventsByDate.value[selectedKey.value] || [] : []);
    const upcomingAcrossYear = computed(() => {
      const out = [];
      for (const e of events.value) {
        for (const inst of expandRecurring(e, cursor.value.year)) {
          if (inst.date >= todayKey) out.push(inst);
        }
      }
      return out.sort((a, b) => a.date.localeCompare(b.date)).slice(0, 6);
    });
    function badgeClass(t) {
      if (t === "holiday") return "bg-rose-100 text-rose-700";
      if (t === "company") return "bg-emerald-100 text-emerald-700";
      if (t === "training") return "bg-sky-100 text-sky-700";
      return "bg-slate-100 text-slate-700";
    }
    function dotClass(t) {
      if (t === "holiday") return "bg-rose-500";
      if (t === "company") return "bg-emerald-500";
      if (t === "training") return "bg-sky-500";
      return "bg-slate-400";
    }
    function formatFull(d) {
      const parsed = parseLocalDate(d);
      return (parsed || new Date(d)).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
    }
    return (_ctx, _push, _parent, _attrs) => {
      _push(`<div${ssrRenderAttrs(mergeProps({ class: "max-w-6xl mx-auto space-y-8" }, _attrs))}><div><h1 class="section-title">Calendar &amp; Events</h1><p class="section-subtitle">Browse company events, holidays, and important dates across any month.</p></div>`);
      if (unref(loading)) {
        _push(`<div class="text-slate-400">Loading events...</div>`);
      } else {
        _push(`<div class="grid lg:grid-cols-[1fr_320px] gap-6 items-start"><section class="card p-4 sm:p-6"><div class="flex items-center justify-between mb-4 gap-3"><div class="flex items-center gap-1"><button class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Previous year">\xAB</button><button class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Previous month">\u2039</button></div><div class="flex-1 text-center"><h2 class="text-lg font-bold text-slate-900">${ssrInterpolate(unref(monthLabel))}</h2></div><div class="flex items-center gap-1"><button class="px-3 py-1.5 rounded-lg text-xs font-semibold text-sycamore-700 hover:bg-sycamore-50">Today</button><button class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Next month">\u203A</button><button class="px-2.5 py-1.5 rounded-lg text-slate-500 hover:bg-slate-100 text-xs font-semibold" title="Next year">\xBB</button></div></div><div class="grid grid-cols-7 gap-px bg-slate-100 rounded-lg overflow-hidden border border-slate-100"><!--[-->`);
        ssrRenderList(weekdayLabels, (d) => {
          _push(`<div class="bg-slate-50 text-[11px] font-semibold uppercase tracking-wide text-slate-500 text-center py-2">${ssrInterpolate(d)}</div>`);
        });
        _push(`<!--]--><!--[-->`);
        ssrRenderList(unref(grid), (cell) => {
          _push(`<button type="button" class="${ssrRenderClass([[
            cell.inMonth ? "text-slate-800" : "text-slate-300 bg-slate-50/50",
            unref(selectedKey) === cell.key ? "ring-2 ring-sycamore-500 ring-inset" : "hover:bg-slate-50"
          ], "bg-white text-left p-2 min-h-[88px] flex flex-col gap-1 transition-colors"])}"><span class="${ssrRenderClass([cell.isToday ? "bg-sycamore-600 text-white" : "", "inline-flex items-center justify-center w-6 h-6 rounded-full text-xs font-semibold"])}">${ssrInterpolate(cell.date.getDate())}</span><div class="flex-1 flex flex-col gap-0.5 overflow-hidden"><!--[-->`);
          ssrRenderList(cell.events.slice(0, 3), (ev) => {
            _push(`<div class="flex items-center gap-1 truncate text-[11px] leading-tight"><span class="${ssrRenderClass([dotClass(ev.event_type), "w-1.5 h-1.5 rounded-full flex-shrink-0"])}"></span><span class="truncate">${ssrInterpolate(ev.title)}</span></div>`);
          });
          _push(`<!--]-->`);
          if (cell.events.length > 3) {
            _push(`<div class="text-[10px] text-slate-400">+${ssrInterpolate(cell.events.length - 3)} more</div>`);
          } else {
            _push(`<!---->`);
          }
          _push(`</div></button>`);
        });
        _push(`<!--]--></div><div class="flex flex-wrap gap-3 mt-4 text-xs text-slate-500"><span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-emerald-500"></span> Company</span><span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-rose-500"></span> Holiday</span><span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-sky-500"></span> Training</span><span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-slate-400"></span> Other</span></div></section><aside class="space-y-6"><div class="card p-5"><h3 class="font-bold text-slate-900 mb-1">${ssrInterpolate(unref(selectedKey) ? formatFull(unref(selectedKey)) : "Select a date")}</h3>`);
        if (!unref(selectedKey)) {
          _push(`<p class="text-sm text-slate-500">Click any day in the calendar to see what&#39;s scheduled.</p>`);
        } else if (!unref(selectedEvents).length) {
          _push(`<div class="text-sm text-slate-400">No events on this day.</div>`);
        } else {
          _push(`<ul class="space-y-3 mt-2"><!--[-->`);
          ssrRenderList(unref(selectedEvents), (e) => {
            _push(`<li class="flex gap-3"><span class="${ssrRenderClass([dotClass(e.event_type), "w-2 h-2 rounded-full mt-1.5 flex-shrink-0"])}"></span><div class="min-w-0 flex-1"><div class="font-semibold text-sm text-slate-900">${ssrInterpolate(e.title)}</div>`);
            if (e.description) {
              _push(`<p class="text-xs text-slate-600 mt-0.5">${ssrInterpolate(e.description)}</p>`);
            } else {
              _push(`<!---->`);
            }
            _push(`<div class="flex items-center gap-2 mt-1 text-[11px]">`);
            if (e.event_type) {
              _push(`<span class="${ssrRenderClass([badgeClass(e.event_type), "px-2 py-0.5 rounded-full capitalize"])}">${ssrInterpolate(e.event_type)}</span>`);
            } else {
              _push(`<!---->`);
            }
            if (e.is_recurring) {
              _push(`<span class="text-slate-400">Recurring annually</span>`);
            } else {
              _push(`<!---->`);
            }
            _push(`</div></div></li>`);
          });
          _push(`<!--]--></ul>`);
        }
        _push(`</div><div class="card p-5"><h3 class="font-bold text-slate-900 mb-3">Up next</h3>`);
        if (unref(upcomingAcrossYear).length) {
          _push(`<ul class="space-y-3"><!--[-->`);
          ssrRenderList(unref(upcomingAcrossYear), (item, idx) => {
            _push(`<li class="flex gap-3"><div class="flex-shrink-0 w-12 text-center py-1.5 rounded-lg bg-sycamore-50 text-sycamore-700 border border-sycamore-100"><div class="text-[10px] font-semibold uppercase">${ssrInterpolate((parseLocalDate(item.date) || /* @__PURE__ */ new Date()).toLocaleString("en-GB", { month: "short" }))}</div><div class="text-base font-bold leading-none">${ssrInterpolate((parseLocalDate(item.date) || /* @__PURE__ */ new Date()).getDate())}</div></div><div class="min-w-0 flex-1"><div class="text-sm font-semibold text-slate-900 truncate">${ssrInterpolate(item.e.title)}</div><div class="text-[11px] text-slate-500 truncate capitalize">${ssrInterpolate(item.e.event_type)}</div></div></li>`);
          });
          _push(`<!--]--></ul>`);
        } else {
          _push(`<div class="text-sm text-slate-400">No upcoming events.</div>`);
        }
        _push(`</div></aside></div>`);
      }
      _push(`</div>`);
    };
  }
});
const _sfc_setup = _sfc_main.setup;
_sfc_main.setup = (props, ctx) => {
  const ssrContext = useSSRContext();
  (ssrContext.modules || (ssrContext.modules = /* @__PURE__ */ new Set())).add("pages/calendar.vue");
  return _sfc_setup ? _sfc_setup(props, ctx) : void 0;
};

export { _sfc_main as default };
//# sourceMappingURL=calendar-C-B36Y-R.mjs.map
