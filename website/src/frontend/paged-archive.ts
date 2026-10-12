import { archiveState, type ArchiveCard, type ArchiveManifest, type ArchiveMatches } from "./archive-query";
import { createArchiveClient, archiveUrl } from "./archive-client";
import { initialiseArchiveExport } from "./archive-export";
import { initialiseArchiveReading } from "./archive-reading";

function textElement<K extends keyof HTMLElementTagNameMap>(tag: K, value: string, className?: string): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag); element.textContent = value;
  if (className) element.className = className;
  return element;
}
export function initialisePagedArchive(root: HTMLElement): () => void {
  const client = createArchiveClient(root.dataset.archiveUrl!);
  const list = root.querySelector<HTMLElement>("[data-filter-list]")!;
  const status = root.querySelector<HTMLElement>("[data-archive-status]")!;
  const retry = root.querySelector<HTMLButtonElement>("[data-archive-retry]")!;
  const empty = root.querySelector<HTMLElement>("[data-archive-empty]")!;
  const pagination = root.querySelector<HTMLElement>("[data-archive-pagination]")!;
  const prev = pagination.querySelector<HTMLButtonElement>("[data-archive-page=prev]")!;
  const next = pagination.querySelector<HTMLButtonElement>("[data-archive-page=next]")!;
  const controller = new AbortController();
  const reading = initialiseArchiveReading(root);
  const cleanupExport = initialiseArchiveExport(client);
  let epoch = 0, alive = true;
  let current: ArchiveMatches = { ordinals: [], count: 0, page: 1, pages: 1 };
  function render(cards: ArchiveCard[], data: ArchiveManifest): void {
    const fragment = document.createDocumentFragment();
    let year: string | undefined, ol: HTMLOListElement | undefined;
    for (const card of cards) {
      if (card.year !== year) {
        year = card.year; const section = document.createElement("section"); section.dataset.filterGroup = "";
        section.append(textElement("h2", year)); const ledger = textElement("section", "", "blog-ledger"); ol = document.createElement("ol"); ledger.append(ol); section.append(ledger); fragment.append(section);
      }
      const row = document.createElement("li"); row.dataset.filterItem = ""; row.dataset.itemId = card.id;
      const meta = textElement("div", "", "blog-ledger__meta"), time = textElement("time", card.display_date || ""); time.dateTime = card.published_at || ""; meta.append(time);
      const content = textElement("div", "", "blog-ledger__content"), title = textElement("a", "", "blog-ledger__main"); title.href = archiveUrl(card.url).href; title.append(textElement("strong", card.title)); content.append(title);
      if (card.summary) title.append(textElement("span", card.summary, "blog-ledger__description"));
      const footer = textElement("footer", "", "archive-card-footer"), tags = textElement("ul", "", "blog-ledger__topics");
      for (const [name, ids] of Object.entries(card.facets)) for (const id of ids) {
        const label = data.labels[data.prefixes[name]! + id] || id;
        const link = textElement("a", label); link.dataset.archiveFacet = name; link.dataset.archiveValue = id;
        link.href = `${window.location.pathname}?${new URLSearchParams([[name, id]])}`;
        const li = document.createElement("li"); li.append(link); tags.append(li);
      }
      footer.append(tags);
      if (card.source_url) { const original = textElement("a", card.source_url, "archive-source-url"); original.href = archiveUrl(card.source_url, true).href; original.rel = "noopener noreferrer"; footer.append(original); }
      if (card.date_basis === "observed") footer.append(textElement("small", root.dataset.observedLabel || "First observed"));
      content.append(footer); row.append(meta, content); ol!.append(row);
    }
    list.replaceChildren(fragment);
    reading.refresh();
  }
  async function refresh(): Promise<void> {
    const turn = ++epoch; status.textContent = status.dataset.loading || "Loading…"; retry.hidden = true;
    root.setAttribute("aria-busy", "true"); prev.disabled = true; next.disabled = true;
    try {
      const data = await client.manifest(controller.signal);
      if (!alive || turn !== epoch) return;
      const state = archiveState(data, window.location.search);
      const result = await client.select(state, "page", controller.signal);
      if (!alive || turn !== epoch) return;
      const cards = await client.cards(result.ordinals, controller.signal);
      if (!alive || turn !== epoch) return;
      render(cards, data);
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
      const pageText = pagination.dataset.pageLabel || "Page {page} of {pages}", resultText = pagination.dataset.resultLabel || "{count} entries";
      pagination.querySelector<HTMLElement>("[data-archive-page-status]")!.textContent = `${resultText.replace("{count}", String(result.count))} · ${pageText.replace("{page}", String(result.page)).replace("{pages}", String(result.pages))}`;
      prev.disabled = result.page <= 1; next.disabled = result.page >= result.pages;
      empty.hidden = result.count !== 0; status.textContent = ""; root.removeAttribute("aria-busy");
    } catch {
      if (alive && turn === epoch) { status.textContent = status.dataset.unavailable || "Entries could not be loaded."; retry.hidden = false; root.removeAttribute("aria-busy"); }
    }
  }
  function click(event: MouseEvent): void {
    if (!(event.target instanceof Element) || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const control = event.target.closest<HTMLElement>("[data-archive-facet], [data-year-filter-option], [data-month-filter-option], [data-day-filter-option], [data-archive-page], [data-archive-clear], [data-archive-retry]");
    if (!control || !root.contains(control) && !control.closest("[data-timeline-nav]")) return;
    event.preventDefault();
    if (control.hasAttribute("data-archive-retry")) { void refresh(); return; }
    const nextUrl = new URL(window.location.href);
    if (control.hasAttribute("data-archive-clear")) nextUrl.search = "";
    else if (control.dataset.archivePage) nextUrl.searchParams.set("page", String(Math.max(1, current.page + (control.dataset.archivePage === "next" ? 1 : -1))));
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
  const onPop = () => { void refresh(); };
  document.addEventListener("click", click); window.addEventListener("popstate", onPop); window.addEventListener("pageshow", onPop);
  // SSR is immediately useful; hydration verifies the complete page projection.
  void refresh();
  return () => { alive = false; controller.abort(); reading.dispose(); cleanupExport(); client.dispose(); document.removeEventListener("click", click); window.removeEventListener("popstate", onPop); window.removeEventListener("pageshow", onPop); };
}
