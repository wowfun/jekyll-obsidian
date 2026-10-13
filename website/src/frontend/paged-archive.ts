import { archiveState, type ArchiveMatches } from "./archive-query";
import { createArchiveClient } from "./archive-client";
import { initialiseArchiveExport } from "./archive-export";
import { initialiseArchiveReading } from "./archive-reading";
import { renderArchiveLedger } from "./archive-ledger";
import { loadFavoriteArchive, renderFavoriteFilters, selectFavorites } from "./favorite-archive";
import { FAVORITES_CHANGE } from "./favorites-store";
import { favoritesUI } from "./favorite-controls";
import { renderArchivePagination } from "./archive-pagination";

export function initialisePagedArchive(root: HTMLElement): () => void {
  const client = createArchiveClient(root.dataset.archiveUrl!);
  const favorites = root.hasAttribute("data-favorites-page");
  const status = root.querySelector<HTMLElement>("[data-archive-status]")!;
  const retry = root.querySelector<HTMLButtonElement>("[data-archive-retry]")!;
  const empty = root.querySelector<HTMLElement>("[data-archive-empty]")!;
  const emptyContent = [...empty.childNodes].map(node => node.cloneNode(true));
  const pagination = root.querySelector<HTMLElement>("[data-archive-pagination]")!;
  const prev = pagination.querySelector<HTMLButtonElement>("[data-archive-page=prev]")!;
  const next = pagination.querySelector<HTMLButtonElement>("[data-archive-page=next]")!;
  const controller = new AbortController();
  const reading = initialiseArchiveReading(root, client);
  const cleanupExport = favorites ? () => {} : initialiseArchiveExport(client);
  let epoch = 0, alive = true;
  let pendingSearch: string | undefined;
  let current: ArchiveMatches = { ordinals: [], count: 0, page: 1, pages: 1 };
  async function refresh(): Promise<void> {
    const search = window.location.search;
    if (pendingSearch === search) return;
    pendingSearch = search;
    const turn = ++epoch; status.textContent = status.dataset.loading || "Loading…"; retry.hidden = true;
    root.setAttribute("aria-busy", "true"); prev.disabled = true; next.disabled = true;
    try {
      const saved = favorites ? await loadFavoriteArchive(client, controller.signal) : undefined;
      const data = saved?.manifest || await client.manifest(controller.signal);
      if (!alive || turn !== epoch) return;
      const state = archiveState(data, window.location.search);
      const result = saved ? selectFavorites(saved.cards, data, state) : await client.select(state, "page", controller.signal);
      if (!alive || turn !== epoch) return;
      const cards = saved ? result.ordinals.map(ordinal => saved.cards[ordinal]!) : await client.cards(result.ordinals, controller.signal);
      if (!alive || turn !== epoch) return;
      if (saved) { empty.replaceChildren(...emptyContent.map(node => node.cloneNode(true))); renderFavoriteFilters(root, data); }
      renderArchiveLedger(root, cards, data);
      reading.refresh();
      current = result;
      result.page > 1 ? state.parameters.set("page", String(result.page)) : state.parameters.delete("page");
      const search = state.parameters.toString(); history.replaceState(null, "", window.location.pathname + (search ? `?${search}` : ""));
      for (const control of root.querySelectorAll<HTMLElement>("button[data-archive-facet]")) {
        const name = control.dataset.archiveFacet!, id = control.dataset.archiveValue!;
        control.setAttribute("aria-pressed", String(id ? state.parameters.getAll(name).includes(id) : !state.parameters.getAll(name).length));
      }
      for (const name of ["year", "month", "day"]) {
        for (const control of document.querySelectorAll<HTMLElement>(`[data-timeline-nav] [data-${name}-filter-option]`)) {
          if (state.parameters.get(name) === control.getAttribute(`data-filter-${name}`)) control.setAttribute("aria-current", "page");
          else control.removeAttribute("aria-current");
        }
      }
      renderArchivePagination(pagination, result.page, result.pages, result.count);
      empty.hidden = result.count !== 0; status.textContent = saved?.refreshFailed ? favoritesUI().refreshError || "Could not refresh articles. Your saved summaries are shown. Retry to continue." : ""; retry.hidden = !saved?.refreshFailed; root.removeAttribute("aria-busy");
    } catch {
      if (alive && turn === epoch) { status.textContent = status.dataset.unavailable || "Entries could not be loaded."; retry.hidden = false; root.removeAttribute("aria-busy"); reading.refresh(); }
    } finally { if (turn === epoch) pendingSearch = undefined; }
  }
  function click(event: MouseEvent): void {
    if (!(event.target instanceof Element) || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const control = event.target.closest<HTMLElement>("[data-archive-facet], [data-year-filter-option], [data-month-filter-option], [data-day-filter-option], [data-archive-page], [data-archive-clear], [data-archive-retry]");
    if (!control || !root.contains(control) && !control.closest("[data-timeline-nav]")) return;
    event.preventDefault();
    if (control.hasAttribute("data-archive-retry")) { void refresh(); return; }
    const nextUrl = new URL(window.location.href);
    if (control.hasAttribute("data-archive-clear")) nextUrl.search = "";
    else if (control.dataset.archivePage) {
      const target = control.dataset.archivePage;
      const page = target === "next" ? current.page + 1 : target === "prev" ? current.page - 1 : Number(target);
      if (!Number.isSafeInteger(page)) return;
      nextUrl.searchParams.set("page", String(Math.max(1, Math.min(current.pages, page))));
    }
    else {
      nextUrl.searchParams.delete("page");
      if (control.dataset.archiveFacet) {
        const name = control.dataset.archiveFacet, id = control.dataset.archiveValue || "", values = new Set(nextUrl.searchParams.getAll(name));
        id ? (values.has(id) ? values.delete(id) : values.add(id)) : values.clear(); nextUrl.searchParams.delete(name);
        [...values].sort().forEach((value) => nextUrl.searchParams.append(name, value));
      } else {
        const name = control.hasAttribute("data-year-filter-option") ? "year" : control.hasAttribute("data-month-filter-option") ? "month" : "day", value = control.getAttribute(`data-filter-${name}`)!;
        for (const other of ["year", "month", "day"]) if (other !== name) nextUrl.searchParams.delete(other);
        nextUrl.searchParams.get(name) === value ? nextUrl.searchParams.delete(name) : nextUrl.searchParams.set(name, value);
      }
    }
    if (nextUrl.search !== window.location.search) history.pushState(null, "", nextUrl.pathname + nextUrl.search);
    void refresh();
  }
  const jump = pagination.querySelector<HTMLFormElement>("[data-archive-page-jump]")!;
  const jumpInput = jump.querySelector<HTMLInputElement>("input")!;
  const onInput = () => { jumpInput.setCustomValidity(""); };
  const onInvalid = () => { jumpInput.setCustomValidity((pagination.dataset.jumpError || "Enter a whole number from 1 to {pages}.").replace("{pages}", String(current.pages))); };
  function submit(event: SubmitEvent): void {
    event.preventDefault();
    if (root.hasAttribute("aria-busy")) return;
    const page = Number(jumpInput.value);
    if (!Number.isSafeInteger(page) || page < 1 || page > current.pages || !jumpInput.value) {
      onInvalid();
      jumpInput.reportValidity(); return;
    }
    const url = new URL(location.href);
    page === 1 ? url.searchParams.delete("page") : url.searchParams.set("page", String(page));
    if (url.search !== location.search) history.pushState(null, "", url.pathname + url.search);
    void refresh();
  }
  const onFavorites = () => { if (favorites) { pendingSearch = undefined; void refresh(); } };
  const onPop = () => { void refresh(); };
  const onShow = (event: PageTransitionEvent) => { if (event.persisted) void refresh(); };
  window.addEventListener(FAVORITES_CHANGE, onFavorites);
  jump.addEventListener("submit", submit); jumpInput.addEventListener("input", onInput); jumpInput.addEventListener("invalid", onInvalid);
  document.addEventListener("click", click); window.addEventListener("popstate", onPop); window.addEventListener("pageshow", onShow);
  // SSR is immediately useful; hydration verifies the complete page projection.
  void refresh();
  return () => { alive = false; controller.abort(); reading.dispose(); cleanupExport(); client.dispose(); jump.removeEventListener("submit", submit); jumpInput.removeEventListener("input", onInput); jumpInput.removeEventListener("invalid", onInvalid); window.removeEventListener(FAVORITES_CHANGE, onFavorites); document.removeEventListener("click", click); window.removeEventListener("popstate", onPop); window.removeEventListener("pageshow", onShow); };
}
