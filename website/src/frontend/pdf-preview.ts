// Only validated PDF bytes enter the viewer. A .pdf URL may return HTML;
// never navigate an unsandboxed frame to that server response.
const MAX_BYTES = 20 * 1024 * 1024;
export async function pdfBlob(response: Response): Promise<Blob> {
  if (!response.ok || response.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/pdf" || !response.body) throw new Error("Invalid PDF response");
  const length = Number(response.headers.get("content-length"));
  if (length > MAX_BYTES) throw new Error("PDF too large");
  const reader = response.body.getReader(), parts: Uint8Array<ArrayBuffer>[] = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength; if (size > MAX_BYTES) throw new Error("PDF too large");
      parts.push(new Uint8Array(value));
    }
  } catch (error) { await reader.cancel(); throw error; }
  finally { reader.releaseLock(); }
  const blob = new Blob(parts, { type: "application/pdf" });
  if (await blob.slice(0, 5).text() !== "%PDF-") throw new Error("Invalid PDF signature");
  return blob;
}
export function initialisePdfPreviews(): () => void {
  const cards = [...document.querySelectorAll<HTMLElement>("[data-website-pdf-source]")];
  let active: { card: HTMLElement; controller: AbortController; url: string | undefined } | undefined;
  const close = () => {
    if (!active) return;
    active.controller.abort(); if (active.url) URL.revokeObjectURL(active.url);
    active.card.querySelector("iframe")?.remove();
    const button = active.card.querySelector<HTMLButtonElement>("[data-pdf-preview]")!;
    button.textContent = active.card.dataset.pdfPreview || "Preview PDF"; button.setAttribute("aria-expanded", "false");
    active.card.querySelector<HTMLElement>("[data-pdf-status]")!.textContent = "";
    active = undefined;
  };
  const click = async (event: MouseEvent) => {
    const button = event.target instanceof Element ? event.target.closest<HTMLButtonElement>("[data-pdf-preview]") : null;
    const card = button?.closest<HTMLElement>("[data-website-pdf-source]"); if (!button || !card) return;
    const wasActive = active?.card === card; close(); if (wasActive) return;
    const controller = new AbortController(), current = { card, controller, url: undefined as string | undefined };
    active = current;
    button.textContent = card.dataset.pdfClose || "Close preview"; button.setAttribute("aria-expanded", "true");
    const status = card.querySelector<HTMLElement>("[data-pdf-status]")!; status.textContent = card.dataset.pdfLoading || "Loading PDF…";
    const timeout = setTimeout(() => controller.abort(), 30000);
    try {
      const source = new URL(card.dataset.websitePdfSource!, location.href);
      const response = await fetch(source, { credentials: "omit", signal: controller.signal });
      const blob = await pdfBlob(response); controller.signal.throwIfAborted();
      current.url = URL.createObjectURL(blob);
      const frame = document.createElement("iframe"); frame.className = "website-external-pdf__viewport";
      frame.src = current.url + source.hash; frame.title = card.querySelector("a")!.textContent || "PDF";
      frame.height = card.dataset.pdfHeight || "640"; card.append(frame); status.textContent = "";
    } catch {
      if (active !== current) return;
      close(); status.textContent = card.dataset.pdfError || "Preview unavailable. Open the PDF using its link.";
    } finally { clearTimeout(timeout); }
  };
  for (const card of cards) card.querySelector<HTMLButtonElement>("[data-pdf-preview]")!.hidden = !navigator.pdfViewerEnabled;
  document.addEventListener("click", click); window.addEventListener("pagehide", close);
  return () => { close(); document.removeEventListener("click", click); window.removeEventListener("pagehide", close); };
}
