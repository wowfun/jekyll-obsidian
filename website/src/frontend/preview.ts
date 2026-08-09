import { fetchJson, parseCatalogPayload } from "./data";
import type { CatalogNote } from "./types";
import { requireSiteUrl } from "./urls";

const ALLOWED_ELEMENTS = new Set([
  "ABBR", "B", "BLOCKQUOTE", "BR", "CODE", "DD", "DEL", "DL", "DT", "EM",
  "H1", "H2", "H3", "H4", "H5", "H6", "HR", "I", "KBD", "LI", "MARK",
  "OL", "P", "PRE", "S", "SMALL", "STRONG", "SUB", "SUP", "TABLE", "TBODY",
  "TD", "TFOOT", "TH", "THEAD", "TR", "UL"
]);
const BLOCKED_ELEMENTS = new Set([
  "AUDIO", "BUTTON", "CANVAS", "EMBED", "FORM", "IFRAME", "IMG", "INPUT", "MATH",
  "NOSCRIPT", "OBJECT", "OPTION", "PICTURE", "SCRIPT", "SELECT", "SOURCE", "STYLE",
  "SVG", "TEMPLATE", "TEXTAREA", "TRACK", "VIDEO"
]);
const previewController = Symbol.for("jekyll-obsidian.preview-controller");
const HOVER_DELAY_MS = 300;
const FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled]):not([type='hidden'])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])"
].join(",");

let notesPromise: Promise<Map<string, CatalogNote>> | null = null;
const noteBodies = new Map<string, Promise<DocumentFragment>>();

function catalog(): Promise<Map<string, CatalogNote>> {
  notesPromise ??= fetchJson(requireSiteUrl("preview"))
    .then(parseCatalogPayload)
    .then((payload) => new Map(payload.notes.map((note) => [note.id, note])))
    .catch((error: unknown) => {
      notesPromise = null;
      throw error;
    });
  return notesPromise;
}

function sanitizedNode(source: Node): Node | null {
  if (source.nodeType === Node.TEXT_NODE) return document.createTextNode(source.textContent || "");
  if (!(source instanceof Element) || BLOCKED_ELEMENTS.has(source.tagName)) return null;

  const children = () => {
    const fragment = document.createDocumentFragment();
    for (const child of [...source.childNodes]) {
      const safe = sanitizedNode(child);
      if (safe) fragment.append(safe);
    }
    return fragment;
  };

  if (source.tagName === "A" || !ALLOWED_ELEMENTS.has(source.tagName)) return children();

  const target = document.createElement(source.tagName.toLocaleLowerCase("en-US"));
  if (source.tagName === "CODE") {
    const languages = [...source.classList].filter((name) => /^language-[a-z0-9_+-]+$/i.test(name));
    if (languages.length > 0) target.className = languages.join(" ");
  }
  if (source.tagName === "TH") {
    const scope = source.getAttribute("scope");
    if (scope === "row" || scope === "col" || scope === "rowgroup" || scope === "colgroup") {
      target.setAttribute("scope", scope);
    }
  }
  if (source.tagName === "TH" || source.tagName === "TD") {
    for (const attribute of ["colspan", "rowspan"] as const) {
      const value = Number(source.getAttribute(attribute));
      if (Number.isSafeInteger(value) && value > 0 && value <= 100) target.setAttribute(attribute, String(value));
    }
  }
  target.append(children());
  return target;
}

function sanitizedBody(html: string): DocumentFragment {
  const inert = document.createElement("template");
  inert.innerHTML = html;
  const source = inert.content.querySelector<HTMLElement>(".note-content");
  if (!source) throw new TypeError("Fetched note has no .note-content element");
  const firstElement = source.firstElementChild;
  if (firstElement?.tagName === "H1") firstElement.remove();
  const firstParagraph = source.querySelector("p");
  if (firstParagraph) {
    let firstBranch: Element = firstParagraph;
    while (firstBranch.parentElement && firstBranch.parentElement !== source) {
      while (firstBranch.previousSibling) firstBranch.previousSibling.remove();
      firstBranch = firstBranch.parentElement;
    }
    while (firstBranch.previousSibling) firstBranch.previousSibling.remove();
  }

  const result = document.createDocumentFragment();
  for (const child of [...source.childNodes]) {
    const safe = sanitizedNode(child);
    if (safe) result.append(safe);
  }
  return result;
}

function loadNoteBody(url: string): Promise<DocumentFragment> {
  let request = noteBodies.get(url);
  if (request) return request;
  request = fetch(url, {
    credentials: "same-origin",
    headers: { Accept: "text/html" }
  }).then((response) => {
    if (!response.ok) throw new Error(`Unable to load ${url}: ${response.status}`);
    return response.text();
  }).then(sanitizedBody).catch((error: unknown) => {
    noteBodies.delete(url);
    throw error;
  });
  noteBodies.set(url, request);
  return request;
}

function makePreview(note: CatalogNote): { preview: HTMLElement; body: HTMLElement } {
  const preview = document.createElement("aside");
  preview.className = "note-preview";
  preview.dataset.notePreview = "";
  preview.setAttribute("role", "dialog");
  preview.setAttribute("aria-label", note.title);

  const header = document.createElement("header");
  header.className = "note-preview__header";
  const eyebrow = document.createElement("p");
  eyebrow.className = "note-preview__eyebrow";
  eyebrow.textContent = note.tags.length > 0 ? note.tags.slice(0, 2).join(" · ") : "Connected note";
  const title = document.createElement("h2");
  title.className = "note-preview__title";
  const titleLink = document.createElement("a");
  titleLink.className = "note-preview__title-link";
  titleLink.href = note.url;
  titleLink.textContent = note.title;
  title.append(titleLink);
  header.append(eyebrow, title);
  if (note.description) {
    const description = document.createElement("p");
    description.className = "note-preview__description";
    description.textContent = note.description;
    header.append(description);
  }

  const body = document.createElement("div");
  body.className = "note-preview__body";
  body.tabIndex = 0;
  body.setAttribute("aria-label", `${note.title} preview`);
  const fallback = document.createElement("p");
  fallback.className = "note-preview__fallback";
  fallback.textContent = note.preview;
  body.append(fallback);
  body.addEventListener("wheel", (event) => {
    event.stopPropagation();
    if (event.deltaY === 0) return;
    event.preventDefault();
    const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? body.clientHeight : 1;
    const maximum = Math.max(0, body.scrollHeight - body.clientHeight);
    body.scrollTop = Math.min(maximum, Math.max(0, body.scrollTop + event.deltaY * unit));
  }, { passive: false });
  preview.append(header, body);
  return { preview, body };
}

function placePreview(preview: HTMLElement, anchor: HTMLElement): void {
  const safe = 12;
  const gap = 10;
  const anchorRect = anchor.getBoundingClientRect();
  const previewRect = preview.getBoundingClientRect();
  const width = previewRect.width || Math.min(420, window.innerWidth - safe * 2);
  const height = previewRect.height || Math.min(560, window.innerHeight - safe * 2);
  const left = Math.min(Math.max(safe, anchorRect.left), Math.max(safe, window.innerWidth - width - safe));
  const roomBelow = window.innerHeight - anchorRect.bottom - gap - safe;
  const roomAbove = anchorRect.top - gap - safe;
  const above = roomBelow < height && roomAbove > roomBelow;
  const desiredTop = above ? anchorRect.top - gap - height : anchorRect.bottom + gap;
  const top = Math.min(
    Math.max(safe, desiredTop),
    Math.max(safe, window.innerHeight - height - safe)
  );
  preview.style.left = `${left}px`;
  preview.style.top = `${top}px`;
  preview.dataset.placement = above ? "above" : "below";
}

export function initialisePreviews(): void {
  const controlledDocument = document as Document & { [previewController]?: () => void };
  controlledDocument[previewController]?.();

  let activeAnchor: HTMLElement | null = null;
  let activePreview: HTMLElement | null = null;
  let activeBody: HTMLElement | null = null;
  let pendingAnchor: HTMLElement | null = null;
  let showTimer: number | undefined;
  let hideTimer: number | undefined;
  let requestVersion = 0;

  const cancelHide = () => window.clearTimeout(hideTimer);
  const cancelShow = () => {
    window.clearTimeout(showTimer);
    showTimer = undefined;
    pendingAnchor = null;
  };
  const close = () => {
    cancelShow();
    cancelHide();
    requestVersion += 1;
    activePreview?.remove();
    activePreview = null;
    activeBody = null;
    activeAnchor = null;
  };
  const staysOpenFor = (target: EventTarget | null) => target instanceof Node && Boolean(
    activeAnchor?.contains(target) || activePreview?.contains(target)
  );
  const hide = (relatedTarget?: EventTarget | null) => {
    if (staysOpenFor(relatedTarget ?? null)) return;
    cancelHide();
    hideTimer = window.setTimeout(close, 100);
  };

  const show = async (anchor: HTMLElement) => {
    cancelShow();
    const noteId = anchor.dataset.noteId;
    cancelHide();
    if (!noteId || (activeAnchor === anchor && activePreview)) return;
    const version = ++requestVersion;
    activeAnchor = anchor;
    try {
      const note = (await catalog()).get(noteId);
      if (!note || activeAnchor !== anchor || requestVersion !== version) return;
      activePreview?.remove();
      const { preview, body } = makePreview(note);
      preview.addEventListener("pointerenter", cancelHide);
      preview.addEventListener("pointerleave", (event) => hide(event.relatedTarget));
      preview.addEventListener("focusin", cancelHide);
      preview.addEventListener("focusout", (event) => hide(event.relatedTarget));
      document.body.append(preview);
      placePreview(preview, anchor);
      activePreview = preview;
      activeBody = body;

      try {
        const content = await loadNoteBody(note.url);
        if (activeAnchor !== anchor || activePreview !== preview || requestVersion !== version) return;
        body.replaceChildren(content.cloneNode(true));
        body.dataset.previewBodyReady = "true";
        placePreview(preview, anchor);
      } catch {
        body.dataset.previewBodyError = "true";
      }
    } catch {
      if (requestVersion === version) activeAnchor = null;
    }
  };
  const scheduleShow = (anchor: HTMLElement) => {
    if ((activeAnchor === anchor && activePreview) || pendingAnchor === anchor) return;
    cancelShow();
    pendingAnchor = anchor;
    showTimer = window.setTimeout(() => {
      pendingAnchor = null;
      showTimer = undefined;
      void show(anchor);
    }, HOVER_DELAY_MS);
  };

  const handlePointerOver = (event: PointerEvent) => {
    if (event.pointerType === "touch") return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest<HTMLElement>(".website-link[data-note-id]");
    if (anchor) scheduleShow(anchor);
  };
  const handlePointerOut = (event: PointerEvent) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest<HTMLElement>(".website-link[data-note-id]");
    if (!anchor) return;
    if (event.relatedTarget instanceof Node && anchor.contains(event.relatedTarget)) return;
    if (pendingAnchor === anchor) cancelShow();
    hide(event.relatedTarget);
  };
  const handleFocusIn = (event: FocusEvent) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest<HTMLElement>(".website-link[data-note-id]");
    if (anchor) void show(anchor);
  };
  const handleFocusOut = (event: FocusEvent) => {
    const target = event.target;
    if (!(target instanceof Element) || !target.closest(".website-link[data-note-id]")) return;
    hide(event.relatedTarget);
  };
  const handleKeydown = (event: KeyboardEvent) => {
    if (!activePreview || !activeAnchor) return;
    if (event.key === "Escape") {
      if (activePreview.contains(document.activeElement)) activeAnchor.focus();
      close();
      return;
    }
    if (event.key !== "Tab" || event.altKey || event.ctrlKey || event.metaKey) return;
    if (!event.shiftKey && event.target === activeAnchor && activeBody) {
      event.preventDefault();
      cancelHide();
      const firstPreviewControl = activePreview.querySelector<HTMLElement>(FOCUSABLE_SELECTOR);
      (firstPreviewControl || activeBody).focus();
      return;
    }
    if (!(event.target instanceof Node) || !activePreview.contains(event.target)) return;
    event.preventDefault();
    const previewControls = [...activePreview.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)];
    const controlIndex = event.target instanceof HTMLElement ? previewControls.indexOf(event.target) : -1;
    const adjacentControl = previewControls[controlIndex + (event.shiftKey ? -1 : 1)];
    if (adjacentControl) {
      adjacentControl.focus();
      return;
    }
    if (event.shiftKey) {
      activeAnchor.focus();
      return;
    }
    const focusable = [...document.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)]
      .filter((element) => !activePreview?.contains(element) && !element.closest("[hidden], [inert], dialog:not([open])"));
    const next = focusable[focusable.indexOf(activeAnchor) + 1];
    close();
    next?.focus();
  };
  const reposition = () => {
    if (activePreview && activeAnchor) placePreview(activePreview, activeAnchor);
  };

  document.addEventListener("pointerover", handlePointerOver);
  document.addEventListener("pointerout", handlePointerOut);
  document.addEventListener("focusin", handleFocusIn);
  document.addEventListener("focusout", handleFocusOut);
  document.addEventListener("keydown", handleKeydown);
  window.addEventListener("resize", reposition);
  window.addEventListener("scroll", reposition, true);

  function cleanup() {
    document.removeEventListener("pointerover", handlePointerOver);
    document.removeEventListener("pointerout", handlePointerOut);
    document.removeEventListener("focusin", handleFocusIn);
    document.removeEventListener("focusout", handleFocusOut);
    document.removeEventListener("keydown", handleKeydown);
    window.removeEventListener("resize", reposition);
    window.removeEventListener("scroll", reposition, true);
    window.removeEventListener("pagehide", handlePageHide);
    close();
    if (controlledDocument[previewController] === cleanup) delete controlledDocument[previewController];
  }
  function handlePageHide(event: PageTransitionEvent) {
    if (!event.persisted) cleanup();
  }
  controlledDocument[previewController] = cleanup;
  window.addEventListener("pagehide", handlePageHide);
}
