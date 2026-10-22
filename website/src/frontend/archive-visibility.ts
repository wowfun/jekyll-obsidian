import { archiveState, canonicalFacetId, type ArchiveCollection, type ArchiveView } from "./archive-query";

export type VisibilityKey = "include_tabs" | "show_hidden";

function availableInView(data: ArchiveCollection, parameters: URLSearchParams, name: string, id: string): boolean {
  if (parameters.getAll(name).includes(id)) return true;
  if (!data.default_view || parameters.get("include_tabs") === "1") return true;
  return !!data.default_view.facets[name]?.[id];
}

export function archiveView(data: ArchiveCollection, parameters: URLSearchParams): ArchiveView {
  if (data.default_view && parameters.get("include_tabs") !== "1") return data.default_view;
  const counts = (ranges: Record<string, [number, number]>) => Object.fromEntries(Object.entries(ranges).map(([key, [start, end]]) => [key, end - start]));
  return { total: data.total, facets: Object.fromEntries(Object.entries(data.facets).map(([name, options]) =>
    [name, Object.fromEntries(options.map(option => [option.id, option.count]))])),
  years: counts(data.years), months: counts(data.months), days: counts(data.days) };
}

export function visibleArchiveOption(data: ArchiveCollection, parameters: URLSearchParams, name: string, id: string): boolean {
  // Keep the empty-query rules aligned with _includes/website/archive-facets.html.
  if (!id || parameters.getAll(name).includes(id)) return true;
  if (!availableInView(data, parameters, name, id)) return false;
  if (name === "source" && data.tab_sources?.includes(id) && parameters.get("include_tabs") !== "1") return false;
  return parameters.getAll("show_hidden").includes(name) || !data.hidden_tags?.includes(data.prefixes[name]! + id);
}

export function toggleArchiveVisibility(parameters: URLSearchParams, key: VisibilityKey, data: ArchiveCollection, name: string): void {
  if (key === "show_hidden") {
    const expanded = new Set(parameters.getAll(key));
    expanded.has(name) ? expanded.delete(name) : expanded.add(name);
    parameters.delete(key);
    [...expanded].sort().forEach(facet => parameters.append(key, facet));
    return;
  }
  const expanded = archiveState(data, parameters.toString()).parameters.get(key) === "1";
  expanded ? parameters.delete(key) : parameters.set(key, "1");
  if (key === "include_tabs") {
    parameters.delete("page");
    if (expanded) {
      const sources = [...new Set(parameters.getAll("source").map(id => canonicalFacetId(id, data.prefixes.source || "source/", data.aliases)))].filter(id => !data.tab_sources?.includes(id));
      parameters.delete("source"); sources.forEach(id => parameters.append("source", id));
    }
  }
}

export function readArchiveVisibilityUI(): DOMStringMap {
  return document.querySelector<HTMLElement>("[data-archive-visibility-ui]")?.dataset || {};
}

export function visibilityButtons(data: ArchiveCollection, parameters: URLSearchParams, name: string, ui: DOMStringMap = {}, controlsId?: string): HTMLButtonElement[] {
  const hidden = data.facets[name]?.some(option =>
    data.hidden_tags?.includes(data.prefixes[name]! + option.id) && availableInView(data, parameters, name, option.id));
  const tabs = name === "source" && data.facets[name]?.some(option => data.tab_sources?.includes(option.id));
  const keys: VisibilityKey[] = [...(tabs ? ["include_tabs" as const] : []), ...(hidden ? ["show_hidden" as const] : [])];
  return keys.map(key => {
    const expanded = key === "show_hidden" ? parameters.getAll(key).includes(name) : parameters.get(key) === "1";
    const button = document.createElement("button"); button.type = "button"; button.className = "archive-visibility";
    button.dataset.archiveVisibility = key; button.dataset.archiveVisibilityFacet = name;
    button.setAttribute("aria-expanded", String(expanded));
    if (controlsId) button.setAttribute("aria-controls", controlsId);
    button.textContent = key === "include_tabs" ? expanded ? ui.hideTabs || "Hide tab sources" : ui.includeTabs || "Include tab sources"
      : name === "topic" ? expanded ? ui.hideTopics || "Hide hidden topics" : ui.showTopics || "Show hidden topics"
      : expanded ? ui.hideTags || "Hide hidden tags" : ui.showTags || "Show hidden tags";
    return button;
  });
}

const synchronized = new WeakMap<HTMLElement, { data: ArchiveCollection; selection: string; scope: boolean; governed: boolean }>();
function setText(node: Element | null, text: string): void { if (node && node.textContent !== text) node.textContent = text; }
function setHidden(node: HTMLElement, hidden: boolean): void { if (node.hidden !== hidden) node.hidden = hidden; }

// Package-owned archive-facets.html and renderFavoriteFilters supply each facet's
// .archive-facet-heading and ul > li controls. Keep both renderers aligned when
// changing this DOM contract. Replace data when its counts or policy change;
// the synchronization cache treats each manifest generation as immutable.
export function syncArchiveVisibility(root: HTMLElement, data: ArchiveCollection, parameters: URLSearchParams): void {
  const previous = synchronized.get(root), governed = Boolean(data.hidden_tags?.length || data.tab_sources?.length);
  if (!governed && !previous?.governed) return;
  const scope = parameters.get("include_tabs") === "1";
  // Dates and pagination do not affect disclosure or the scope's facet counts.
  const selection = JSON.stringify([parameters.getAll("show_hidden"), Object.keys(data.facets).map(name => parameters.getAll(name))]);
  if (previous?.data === data && previous.scope === scope && previous.selection === selection) return;
  const countsChanged = previous?.data !== data || previous.scope !== scope;
  const view = countsChanged ? archiveView(data, parameters) : undefined, ui = readArchiveVisibilityUI();
  for (const nav of root.querySelectorAll<HTMLElement>(".archive-facet")) {
    const host = nav.querySelector<HTMLElement>(".archive-facet-heading")!;
    const name = nav.querySelector<HTMLElement>("[data-archive-facet]")?.dataset.archiveFacet;
    if (!name) continue;
    const list = nav.querySelector<HTMLElement>("ul")!;
    if (!list.id) list.id = `archive-options-${name}`;
    const existing = new Map([...host.querySelectorAll<HTMLButtonElement>("[data-archive-visibility]")].map(button => [button.dataset.archiveVisibility, button]));
    for (const button of visibilityButtons(data, parameters, name, ui, list.id)) {
      const current = existing.get(button.dataset.archiveVisibility);
      // Only reuse controls with the same action, preserving their focus.
      if (current) {
        setText(current, button.textContent!);
        for (const attribute of ["aria-expanded", "aria-controls"]) if (current.getAttribute(attribute) !== button.getAttribute(attribute)) current.setAttribute(attribute, button.getAttribute(attribute)!);
        existing.delete(button.dataset.archiveVisibility);
      } else host.append(button);
    }
    existing.forEach(button => button.remove());
    for (const control of nav.querySelectorAll<HTMLElement>("[data-archive-facet]")) {
      const id = control.dataset.archiveValue!, count = control.querySelector("span");
      setHidden(control.closest("li")!, !visibleArchiveOption(data, parameters, name, id));
      if (view) setText(count, String(id ? view.facets[name]?.[id] || 0 : view.total));
    }
  }
  if (view) for (const name of ["year", "month", "day"] as const) {
    const counts = view[`${name}s`];
    for (const control of document.querySelectorAll<HTMLElement>(`[data-timeline-nav] [data-${name}-filter-option]`)) {
      const count = counts[control.getAttribute(`data-filter-${name}`)!] || 0;
      const label = control.querySelector(".archive-timeline__count");
      setText(label, String(count));
      const container = control.closest<HTMLElement>(name === "year" ? "section" : "li");
      if (container) setHidden(container, count === 0);
    }
  }
  synchronized.set(root, { data, selection, scope, governed });
}
