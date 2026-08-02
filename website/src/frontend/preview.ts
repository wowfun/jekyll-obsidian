import { fetchJson, parseCatalogPayload } from "./data";
import type { CatalogNote } from "./types";
import { requireSiteUrl } from "./urls";

let notesPromise: Promise<Map<string, CatalogNote>> | null = null;

function catalog(): Promise<Map<string, CatalogNote>> {
  notesPromise ??= fetchJson(requireSiteUrl("preview"))
    .then(parseCatalogPayload)
    .then((payload) => new Map(payload.notes.map((note) => [note.id, note])));
  return notesPromise;
}

function makePreview(note: CatalogNote): HTMLElement {
  const preview = document.createElement("aside");
  preview.className = "note-preview";
  preview.dataset.notePreview = "";
  preview.setAttribute("role", "status");

  const eyebrow = document.createElement("p");
  eyebrow.className = "note-preview__eyebrow";
  eyebrow.textContent = note.tags.length > 0 ? note.tags.slice(0, 2).join(" · ") : "Connected note";

  const title = document.createElement("strong");
  title.className = "note-preview__title";
  title.textContent = note.title;

  const excerpt = document.createElement("p");
  excerpt.className = "note-preview__text";
  excerpt.textContent = note.preview;

  preview.append(eyebrow, title, excerpt);
  return preview;
}

function placePreview(preview: HTMLElement, anchor: HTMLElement): void {
  const anchorRect = anchor.getBoundingClientRect();
  const maxLeft = Math.max(12, window.innerWidth - 356);
  const left = Math.min(Math.max(12, anchorRect.left), maxLeft);
  const above = anchorRect.top > window.innerHeight * 0.55;
  preview.style.left = `${left}px`;
  preview.style.top = above ? `${anchorRect.top - 12}px` : `${anchorRect.bottom + 12}px`;
  preview.dataset.placement = above ? "above" : "below";
}

export function initialisePreviews(): void {
  let activeAnchor: HTMLElement | null = null;
  let activePreview: HTMLElement | null = null;
  let hideTimer: number | undefined;

  const hide = () => {
    window.clearTimeout(hideTimer);
    hideTimer = window.setTimeout(() => {
      activePreview?.remove();
      activePreview = null;
      activeAnchor = null;
    }, 90);
  };

  const show = async (anchor: HTMLElement) => {
    const noteId = anchor.dataset.noteId;
    window.clearTimeout(hideTimer);
    if (!noteId || activeAnchor === anchor) return;
    activeAnchor = anchor;
    try {
      const note = (await catalog()).get(noteId);
      if (!note || activeAnchor !== anchor) return;
      activePreview?.remove();
      const preview = makePreview(note);
      document.body.append(preview);
      placePreview(preview, anchor);
      activePreview = preview;
    } catch {
      activeAnchor = null;
    }
  };

  document.addEventListener("pointerover", (event) => {
    if (event.pointerType === "touch") return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest<HTMLElement>(".obsidian-link[data-note-id]");
    if (anchor) void show(anchor);
  });
  document.addEventListener("pointerout", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest(".obsidian-link[data-note-id]");
    const related = event.relatedTarget;
    if (anchor && related instanceof Node && anchor.contains(related)) return;
    if (anchor) hide();
  });
  document.addEventListener("focusin", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest<HTMLElement>(".obsidian-link[data-note-id]");
    if (anchor) void show(anchor);
  });
  document.addEventListener("focusout", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest(".obsidian-link[data-note-id]");
    const related = event.relatedTarget;
    if (anchor && related instanceof Node && anchor.contains(related)) return;
    if (anchor) hide();
  });
}
