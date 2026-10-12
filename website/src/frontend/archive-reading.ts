const ELEMENTS = new Set("A ABBR B BLOCKQUOTE BR CODE DD DEL DETAILS DIV DL DT EM FIGCAPTION FIGURE H1 H2 H3 H4 H5 H6 HR I IMG KBD LI MARK OL P PRE S SECTION SMALL SPAN STRONG SUB SUMMARY SUP TABLE TBODY TD TFOOT TH THEAD TR UL".split(" "));
const BLOCKED = new Set("SCRIPT STYLE IFRAME OBJECT EMBED FORM INPUT BUTTON SELECT TEXTAREA TEMPLATE NOSCRIPT SVG MATH".split(" "));

// Parse in an inert template and copy only reading content, without executing
// scripts, event handlers, or reusing IDs from another article.
export function articleBody(html: string, url: string, prefix: string): DocumentFragment {
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
          const resolved = new URL(value, url);
          if (/^https?:$/.test(resolved.protocol) || attribute === "href" && resolved.protocol === "mailto:") {
            let fragment: string | undefined;
            try { fragment = ids.get(decodeURIComponent(resolved.hash.slice(1))); } catch { /* Keep the source link. */ }
            target.setAttribute(attribute, fragment && resolved.origin + resolved.pathname + resolved.search === new URL(url).origin + new URL(url).pathname + new URL(url).search ? `#${fragment}` : resolved.href);
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

export function initialiseArchiveReading(root: HTMLElement): { refresh: () => void; dispose: () => void } {
  const toggle = document.querySelector<HTMLButtonElement>("[data-archive-reading-toggle]");
  if (!toggle) return { refresh() {}, dispose() {} };
  let enabled = false, disposed = false, controller = new AbortController(), sequence = 0;
  try { enabled = localStorage.getItem("website-archive-reading") === "true"; } catch { /* Storage is optional. */ }
  toggle.hidden = false;
  function refresh(): void {
    controller.abort(); controller = new AbortController();
    root.classList.toggle("archive-reading", enabled);
    toggle!.setAttribute("aria-checked", String(enabled));
    if (!enabled || disposed) return;
    const signal = controller.signal;
    const rows = Array.from(root.querySelectorAll<HTMLElement>("[data-filter-item]"));
    let index = 0;
    async function load(row: HTMLElement): Promise<void> {
      const link = row.querySelector<HTMLAnchorElement>(".blog-ledger__main");
      const content = row.querySelector<HTMLElement>(".blog-ledger__content");
      if (!link || !content || row.dataset.readingLoaded) return;
      let body = content.querySelector<HTMLElement>(".archive-reading__body");
      if (!body) { body = document.createElement("div"); body.className = "archive-reading__body note-content"; content.append(body); }
      body.textContent = toggle!.dataset.loading || "Loading article…";
      body.setAttribute("aria-busy", "true");
      try {
        const url = new URL(link.href);
        if (url.origin !== location.origin) throw new Error("Invalid article origin");
        const response = await fetch(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]), headers: { Accept: "text/html" } });
        if (!response.ok || new URL(response.url || url.href).origin !== location.origin || !response.headers.get("content-type")?.includes("text/html")) throw new Error("Article load failed");
        const html = await response.text();
        if (signal.aborted) return;
        body.replaceChildren(articleBody(html, url.href, `archive-article-${++sequence}`));
        row.dataset.readingLoaded = "true";
      } catch {
        if (signal.aborted) return;
        const message = document.createElement("p"); message.textContent = toggle!.dataset.unavailable || "Article could not be loaded.";
        const retry = document.createElement("button"); retry.type = "button"; retry.dataset.readingRetry = ""; retry.textContent = toggle!.dataset.retry || "Retry";
        body.replaceChildren(message, retry);
      } finally { if (!signal.aborted) body.removeAttribute("aria-busy"); }
    }
    // Each successful body belongs to its current-page row. Replacing the page
    // releases it; switching off cancels the remaining requests immediately.
    void Promise.all(Array.from({ length: Math.min(4, rows.length) }, async () => {
      while (!signal.aborted && index < rows.length) await load(rows[index++]!);
    }));
  }
  function switchReading(): void {
    enabled = !enabled;
    try { localStorage.setItem("website-archive-reading", String(enabled)); } catch { /* Storage is optional. */ }
    refresh();
  }
  function retry(event: MouseEvent): void {
    if (event.target instanceof Element && event.target.closest("[data-reading-retry]")) refresh();
  }
  toggle.addEventListener("click", switchReading);
  root.addEventListener("click", retry);
  refresh();
  return { refresh, dispose() { disposed = true; controller.abort(); toggle.removeEventListener("click", switchReading); root.removeEventListener("click", retry); } };
}
