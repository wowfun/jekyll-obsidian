import { archiveConcurrent, type ArchiveClient } from "./archive-client";

const ELEMENTS = new Set("A ABBR B BLOCKQUOTE BR CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE H1 H2 H3 H4 H5 H6 HR I IMG KBD LI MARK OL P PRE S SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TFOOT TH THEAD TR UL".split(" "));
const BLOCKED = new Set("SCRIPT STYLE IFRAME OBJECT EMBED FORM INPUT BUTTON SELECT TEXTAREA TEMPLATE NOSCRIPT SVG MATH".split(" "));

// Parse in an inert template and copy only reading content, without executing
// scripts, event handlers, or reusing IDs from another article.
export function articleBody(html: string, url: string, prefix: string): DocumentFragment {
  const base = new URL(url), documentUrl = base.origin + base.pathname + base.search;
  const template = document.createElement("template");
  template.innerHTML = html;
  const source = template.content.querySelector(".note-content");
  if (!source) throw new Error("Article body is missing");
  const ids = new Map(Array.from(source.querySelectorAll("[id]"), (element, index) => [element.id, `${prefix}-${index}`]));
  function copy(node: Node): Node | null {
    if (node.nodeType === Node.TEXT_NODE) return document.createTextNode(node.textContent || "");
    if (!(node instanceof Element) || BLOCKED.has(node.tagName)) return null;
    const children = document.createDocumentFragment();
    for (const child of node.childNodes) { const safe = copy(child); if (safe) children.append(safe); }
    if (!ELEMENTS.has(node.tagName)) return children;
    const target = document.createElement(node.tagName.toLowerCase());
    if (node.id) target.id = ids.get(node.id)!;
    for (const name of ["title", "lang", "dir", "alt", "colspan", "rowspan", "scope", "start"]) {
      const value = node.getAttribute(name); if (value !== null) target.setAttribute(name, value);
    }
    if (node.tagName === "CODE") target.className = [...node.classList].filter(name => /^language-[\w+-]+$/.test(name)).join(" ");
    const attribute = node.tagName === "A" ? "href" : node.tagName === "IMG" ? "src" : null;
    if (attribute) {
      const value = node.getAttribute(attribute);
      if (value) {
        try {
          const resolved = new URL(value, base);
          if (/^https?:$/.test(resolved.protocol) || attribute === "href" && resolved.protocol === "mailto:") {
            let fragment: string | undefined;
            try { fragment = ids.get(decodeURIComponent(resolved.hash.slice(1))); } catch { /* Keep the source link. */ }
            target.setAttribute(attribute, fragment && resolved.origin + resolved.pathname + resolved.search === documentUrl ? `#${fragment}` : resolved.href);
          }
        } catch { /* Invalid URLs remain plain text. */ }
      }
    }
    if (node.tagName === "A") target.setAttribute("rel", "noopener noreferrer");
    if (node.tagName === "IMG") { target.setAttribute("loading", "lazy"); if (!target.hasAttribute("src")) return null; }
    target.append(children);
    return target;
  }
  const result = document.createDocumentFragment();
  for (const child of source.childNodes) { const safe = copy(child); if (safe) result.append(safe); }
  return result;
}

export function initialiseArchiveReading(root: HTMLElement, client: Pick<ArchiveClient, "article">): { refresh: () => void; dispose: () => void } {
  const toggle = document.querySelector<HTMLButtonElement>("[data-archive-reading-toggle]");
  if (!toggle) return { refresh() {}, dispose() {} };
  let enabled = false, disposed = false, controller = new AbortController(), sequence = 0;
  let observer: IntersectionObserver | undefined;
  const loading = new WeakMap<HTMLElement, AbortSignal>();
  const cache = new Map<string, { body: DocumentFragment; weight: number }>();
  let cacheWeight = 0;
  try { enabled = localStorage.getItem("website-archive-reading") === "true"; } catch { /* Storage is optional. */ }
  toggle.hidden = false;
  function cloneBody(body: DocumentFragment): DocumentFragment {
    const clone = body.cloneNode(true) as DocumentFragment, ids = new Map<string, string>();
    const prefix = `archive-article-${++sequence}`;
    for (const [index, element] of [...clone.querySelectorAll('[id]')].entries()) {
      const id = `${prefix}-${index}`; ids.set(element.id, id); element.id = id;
    }
    for (const link of clone.querySelectorAll('a[href^="#"]')) {
      const id = ids.get(link.getAttribute('href')!.slice(1)); if (id) link.setAttribute('href', '#' + id);
    }
    return clone;
  }
  async function load(row: HTMLElement, signal: AbortSignal): Promise<void> {
    const link = row.querySelector<HTMLAnchorElement>(".blog-ledger__main");
    const content = row.querySelector<HTMLElement>(".blog-ledger__content");
    if (!link || !content || row.dataset.readingLoaded || loading.get(row) === signal) return;
    loading.set(row, signal);
    let body = content.querySelector<HTMLElement>(".archive-reading__body");
    if (!body) { body = document.createElement("div"); body.className = "archive-reading__body note-content"; content.append(body); }
    body.textContent = toggle!.dataset.loading || "Loading article…";
    body.setAttribute("aria-busy", "true");
    try {
      let cached = cache.get(link.href);
      if (cached) { cache.delete(link.href); cache.set(link.href, cached); }
      else {
        const article = await client.article(link.href, signal); signal.throwIfAborted();
        cached = { body: articleBody(article.html, article.url, 'archive-template'), weight: article.html.length * 2 };
        cache.set(link.href, cached); cacheWeight += cached.weight;
        // Bound both item count and source size; retain only sanitized bodies.
        while (cache.size > 100 || cacheWeight > 4 * 1024 * 1024) {
          const key = cache.keys().next().value!; cacheWeight -= cache.get(key)!.weight; cache.delete(key);
        }
      }
      signal.throwIfAborted(); body.replaceChildren(cloneBody(cached.body)); row.dataset.readingLoaded = "true";
    } catch {
      if (signal.aborted) return;
      const message = document.createElement("p"); message.textContent = toggle!.dataset.unavailable || "Article could not be loaded.";
      const retry = document.createElement("button"); retry.type = "button"; retry.dataset.readingRetry = ""; retry.textContent = toggle!.dataset.retry || "Retry";
      body.replaceChildren(message, retry);
    } finally {
      if (loading.get(row) === signal) loading.delete(row);
      if (!signal.aborted) body.removeAttribute("aria-busy");
    }
  }
  function refresh(): void {
    observer?.disconnect(); observer = undefined;
    controller.abort(); controller = new AbortController();
    root.classList.toggle("archive-reading", enabled);
    toggle!.setAttribute("aria-checked", String(enabled));
    if (!enabled || disposed) return;
    const signal = controller.signal;
    const rows = Array.from(root.querySelectorAll<HTMLElement>("[data-filter-item]"));
    if (typeof IntersectionObserver === 'function') {
      observer = new IntersectionObserver((entries, current) => {
        if (signal.aborted) return;
        for (const entry of entries) if (entry.isIntersecting) {
          current.unobserve(entry.target);
          void load(entry.target as HTMLElement, signal);
        }
      }, { rootMargin: '400px 0px' });
      for (const row of rows) if (!row.dataset.readingLoaded) observer.observe(row);
    } else {
      void archiveConcurrent(rows, row => load(row, signal), signal).catch(() => { /* Rows handle errors; cancellation stops the pool. */ });
    }
  }
  function switchReading(): void {
    enabled = !enabled;
    try { localStorage.setItem("website-archive-reading", String(enabled)); } catch { /* Storage is optional. */ }
    refresh();
  }
  function retry(event: MouseEvent): void {
    if (!enabled || disposed || !(event.target instanceof Element) || !event.target.closest("[data-reading-retry]")) return;
    const row = event.target.closest<HTMLElement>('[data-filter-item]');
    if (row) void load(row, controller.signal);
  }
  toggle.addEventListener("click", switchReading);
  root.addEventListener("click", retry);
  // Pagination chooses the initial rows before starting saved reading mode.
  toggle.setAttribute('aria-checked', String(enabled));
  return { refresh, dispose() { disposed = true; observer?.disconnect(); controller.abort(); cache.clear(); cacheWeight = 0; toggle.removeEventListener("click", switchReading); root.removeEventListener("click", retry); } };
}
