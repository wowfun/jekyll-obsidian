import { archiveState, decodeBitmap, type ArchiveCard, type ArchiveManifest, type ArchiveQuery } from "./archive-query";
import { requireSiteUrl } from "./urls";

type Matches = { ordinals: number[]; count: number; page: number; pages: number };
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid archive data");
  return value as Record<string, unknown>;
}
function textElement<K extends keyof HTMLElementTagNameMap>(tag: K, value: string, className?: string): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag); element.textContent = value;
  if (className) element.className = className;
  return element;
}
function publicUrl(value: string, external = false): string {
  const url = new URL(value, window.location.href);
  if (!/^https?:$/.test(url.protocol) || url.username || url.password || (!external && url.origin !== window.location.origin)) throw new Error("Invalid archive URL");
  return url.href;
}

export function initialisePagedArchive(root: HTMLElement): () => void {
  const manifestUrl = new URL(root.dataset.archiveUrl!, window.location.href);
  const list = root.querySelector<HTMLElement>("[data-filter-list]")!;
  const status = root.querySelector<HTMLElement>("[data-archive-status]")!;
  const retry = root.querySelector<HTMLButtonElement>("[data-archive-retry]")!;
  const empty = root.querySelector<HTMLElement>("[data-archive-empty]")!;
  const pagination = root.querySelector<HTMLElement>("[data-archive-pagination]")!;
  const prev = pagination.querySelector<HTMLButtonElement>("[data-archive-page=prev]")!;
  const next = pagination.querySelector<HTMLButtonElement>("[data-archive-page=next]")!;
  const controller = new AbortController();
  const worker = new Worker(requireSiteUrl("archive-worker"), { type: "module" });
  const pending = new Map<number, { resolve: (result: Matches) => void; reject: (error: Error) => void }>();
  const cache = new Map<string, unknown>();
  const requests = new Map<string, Promise<unknown>>();
  let manifest: ArchiveManifest | undefined, manifestPromise: Promise<ArchiveManifest> | undefined;
  let epoch = 0, queryId = 0, alive = true, activeLoads = 0;
  const loadQueue: (() => void)[] = [];
  async function fetchResource(url: URL): Promise<unknown> {
    if (activeLoads >= 4) await new Promise<void>((resolve) => loadQueue.push(resolve));
    activeLoads++;
    try {
      const response = await fetch(url, { signal: AbortSignal.any([controller.signal, AbortSignal.timeout(15000)]) });
      if (!response.ok) throw new Error("Archive load failed");
      return await response.json() as unknown;
    } finally { activeLoads--; loadQueue.shift()?.(); }
  }
  let current: Matches = { ordinals: [], count: 0, page: 1, pages: 1 };
  worker.onmessage = (event: MessageEvent<Matches & { id: number }>) => {
    pending.get(event.data.id)?.resolve(event.data); pending.delete(event.data.id);
  };
  worker.onerror = () => { for (const job of pending.values()) job.reject(new Error("Archive worker failed")); pending.clear(); };
  async function load(filename: string): Promise<unknown> {
    if (cache.has(filename)) { const value = cache.get(filename); cache.delete(filename); cache.set(filename, value); return value; }
    let promise = requests.get(filename);
    if (!promise) {
      const url = new URL(filename, manifestUrl);
      if (url.origin !== manifestUrl.origin || !url.pathname.startsWith(manifestUrl.pathname.slice(0, manifestUrl.pathname.lastIndexOf("/") + 1))) throw new Error("Invalid archive resource path");
      promise = fetchResource(url).then((value) => {
        if (filename !== "manifest.json") {
          if (object(value).generation !== manifest?.generation) throw new Error("Archive generation differs");
          cache.set(filename, value);
          while (cache.size > 20) cache.delete(cache.keys().next().value!);
        }
        return value;
      }).finally(() => { requests.delete(filename); });
      requests.set(filename, promise);
    }
    return promise;
  }
  async function getManifest(): Promise<ArchiveManifest> {
    manifestPromise ??= load("manifest.json").then((value) => {
      const data = object(value);
      if (data.version !== 1 || !Number.isSafeInteger(data.total) || Number(data.total) < 0 || !Number.isSafeInteger(data.page_size) || Number(data.page_size) < 1 || Number(data.page_size) > 100 || typeof data.generation !== "string" || !/^[a-f0-9]{64}$/.test(data.generation) || !Array.isArray(data.chunks)) throw new Error("Invalid archive manifest");
      for (const key of ["facets", "prefixes", "labels", "aliases", "years", "months"]) object(data[key]);
      for (const [name, prefix] of Object.entries(object(data.prefixes))) {
        if (!/^[a-z][a-z0-9_-]*$/.test(name) || typeof prefix !== "string" || !Array.isArray(object(data.facets)[name])) throw new Error("Invalid archive facet");
        for (const entry of object(data.facets)[name] as unknown[]) { const option = object(entry); if (typeof option.id !== "string" || typeof option.name !== "string" || typeof option.posting !== "string") throw new Error("Invalid archive option"); }
      }
      if (data.chunks.length !== Math.ceil(Number(data.total) / Number(data.page_size))) throw new Error("Invalid archive chunk count");
      for (const mapping of [data.years, data.months]) for (const range of Object.values(object(mapping))) {
        if (!Array.isArray(range) || range.length !== 2 || !range.every(Number.isSafeInteger) || range[0] < 0 || range[1] > Number(data.total) || range[0] > range[1]) throw new Error("Invalid chronology bounds");
      }
      manifest = data as unknown as ArchiveManifest; return manifest;
    }).catch((error: unknown) => { manifestPromise = undefined; throw error; });
    return manifestPromise;
  }
  async function concurrent<T>(values: T[], operation: (value: T) => Promise<void>): Promise<void> {
    let index = 0;
    await Promise.all(Array.from({ length: Math.min(4, values.length) }, async () => { while (index < values.length) await operation(values[index++]!); }));
  }
  function query(total: number, size: number, state: ArchiveQuery, bitmaps: Record<string, Uint8Array>): Promise<Matches> {
    const id = ++queryId;
    return new Promise((resolve, reject) => { const timeout = setTimeout(() => { pending.delete(id); reject(new Error("Archive query timed out")); }, 15000);
      pending.set(id, { resolve: (value) => { clearTimeout(timeout); resolve(value); }, reject: (error) => { clearTimeout(timeout); reject(error); } }); worker.postMessage({ id, total, size, query: state, bitmaps }); });
  }
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
      const content = textElement("div", "", "blog-ledger__content"), title = textElement("a", "", "blog-ledger__main"); title.href = publicUrl(card.url); title.append(textElement("strong", card.title)); content.append(title);
      const footer = textElement("footer", "", "archive-card-footer"), tags = textElement("ul", "", "blog-ledger__topics");
      for (const [name, ids] of Object.entries(card.facets)) for (const id of ids) {
        const label = data.labels[data.prefixes[name]! + id] || id;
        const link = textElement("a", label); link.dataset.archiveFacet = name; link.dataset.archiveValue = id;
        link.href = `${window.location.pathname}?${new URLSearchParams([[name, id]])}`;
        const li = document.createElement("li"); li.append(link); tags.append(li);
      }
      footer.append(tags);
      if (card.source_url) { const original = textElement("a", card.source_url, "archive-source-url"); original.href = publicUrl(card.source_url, true); original.rel = "noopener noreferrer"; footer.append(original); }
      if (card.date_basis === "observed") footer.append(textElement("small", root.dataset.observedLabel || "First observed"));
      content.append(footer); row.append(meta, content); ol!.append(row);
    }
    list.replaceChildren(fragment);
  }
  async function refresh(): Promise<void> {
    const turn = ++epoch; status.textContent = status.dataset.loading || "Loading…"; retry.hidden = true;
    root.setAttribute("aria-busy", "true"); prev.disabled = true; next.disabled = true;
    try {
      const data = await getManifest();
      if (!alive || turn !== epoch) return;
      const state = archiveState(data, window.location.search), bitmaps: Record<string, Uint8Array> = Object.create(null) as Record<string, Uint8Array>;
      await concurrent(state.keys, async (key) => {
        const split = key.indexOf("/"), name = key.slice(0, split), id = key.slice(split + 1);
        const option = data.facets[name]?.find((entry) => entry.id === id);
        if (!option) return;
        const posting = object(await load(option.posting));
        if (posting.total !== data.total || typeof posting.bitmap !== "string") throw new Error("Invalid posting");
        bitmaps[key] = decodeBitmap(posting.bitmap, data.total);
      });
      if (!alive || turn !== epoch) return;
      const result = await query(data.total, data.page_size, state.query, bitmaps);
      if (!alive || turn !== epoch) return;
      const chunks = new Map<number, ArchiveCard[]>();
      await concurrent([...new Set(result.ordinals.map((ordinal) => Math.floor(ordinal / data.page_size)))], async (index) => {
        const file = data.chunks[index]; if (!file) throw new Error("Missing archive chunk");
        const chunk = object(await load(file));
        if (chunk.start !== index * data.page_size || !Array.isArray(chunk.cards) || chunk.cards.length > data.page_size) throw new Error("Invalid card chunk");
        const cards = chunk.cards as ArchiveCard[];
        for (const raw of cards) { const card = object(raw); if (typeof card.id !== "string" || typeof card.title !== "string" || typeof card.url !== "string" || typeof card.year !== "string") throw new Error("Invalid card"); object(card.facets); }
        chunks.set(index, cards);
      });
      if (!alive || turn !== epoch) return;
      render(result.ordinals.map((ordinal) => { const card = chunks.get(Math.floor(ordinal / data.page_size))?.[ordinal % data.page_size]; if (!card) throw new Error("Missing archive card"); return card; }), data);
      current = result;
      result.page > 1 ? state.parameters.set("page", String(result.page)) : state.parameters.delete("page");
      const search = state.parameters.toString(); history.replaceState(null, "", window.location.pathname + (search ? `?${search}` : ""));
      for (const control of root.querySelectorAll<HTMLElement>("button[data-archive-facet]")) {
        const name = control.dataset.archiveFacet!, id = control.dataset.archiveValue!;
        control.setAttribute("aria-pressed", String(id ? state.parameters.getAll(name).includes(id) : !state.parameters.getAll(name).length));
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
    const control = event.target.closest<HTMLElement>("[data-archive-facet], [data-year-filter-option], [data-month-filter-option], [data-archive-page], [data-archive-clear], [data-archive-retry]");
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
        const name = control.hasAttribute("data-year-filter-option") ? "year" : "month", value = name === "year" ? control.dataset.filterYear! : control.dataset.filterMonth!;
        nextUrl.searchParams.delete(name === "year" ? "month" : "year");
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
  return () => { alive = false; controller.abort(); worker.terminate(); for (const job of pending.values()) job.reject(new Error("Archive disposed")); pending.clear(); document.removeEventListener("click", click); window.removeEventListener("popstate", onPop); window.removeEventListener("pageshow", onPop); };
}
