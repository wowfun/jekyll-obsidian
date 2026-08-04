// @vitest-environment happy-dom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

interface NoteFixture {
  id: string;
  title: string;
  url: string;
  description?: string | null;
  preview?: string;
}

function catalog(notes: NoteFixture[]): string {
  return JSON.stringify({
    schema_version: 1,
    notes: notes.map((note) => ({
      id: note.id,
      title: note.title,
      url: note.url,
      aliases: [],
      tags: ["linked"],
      description: note.description ?? null,
      preview: note.preview ?? "Catalog preview",
      updated: null,
      content_type: "page",
      published_at: null
    }))
  });
}

function anchor(id: string): HTMLAnchorElement {
  const element = document.createElement("a");
  element.className = "website-link";
  element.dataset.noteId = id;
  element.href = `/${id}/`;
  element.textContent = id;
  document.body.append(element);
  return element;
}

describe("note previews", () => {
  beforeEach(() => {
    vi.resetModules();
    document.head.replaceChildren();
    document.body.replaceChildren();
    document.head.insertAdjacentHTML("beforeend", '<meta name="website:preview" content="/assets/website/catalog.v1.json">');
  });

  afterEach(() => {
    window.dispatchEvent(new Event("pagehide"));
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("shows catalog metadata first, then a sanitized, read-only note body", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).includes("catalog.v1.json")) {
        return new Response(catalog([{ id: "safe.md", title: "Safe note", url: "/safe/", description: "A useful summary." }]), { status: 200 });
      }
      return new Response(`<!doctype html><main><div class="note-content">
        <h1>Safe note</h1><h2>Repeated heading</h2><p>First paragraph.</p><h2>Details</h2>
        <p><a href="/danger" onclick="alert(1)">Plain link text</a></p>
        <table><tbody><tr><th scope="col">Key</th><td>Value</td></tr></tbody></table>
        <pre><code class="language-js evil">const safe = true;</code></pre>
        <script>alert(1)</script><iframe src="/active"></iframe><form><input value="secret"></form><video src="movie.mp4"></video>
      </div></main>`, { status: 200, headers: { "Content-Type": "text/html" } });
    });
    vi.stubGlobal("fetch", fetchMock);
    const link = anchor("safe.md");
    const { initialisePreviews } = await import("../../src/frontend/preview");
    initialisePreviews();

    link.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    await vi.waitFor(() => expect(document.querySelector("[data-preview-body-ready]")).not.toBeNull());

    const preview = document.querySelector<HTMLElement>("[data-note-preview]")!;
    expect(preview.querySelector(".note-preview__title")?.textContent).toBe("Safe note");
    expect(preview.querySelector(".note-preview__description")?.textContent).toBe("A useful summary.");
    expect(preview.querySelector(".note-preview__body")?.textContent).toContain("First paragraph.");
    expect(preview.querySelector("h1")).toBeNull();
    expect(preview.textContent).not.toContain("Repeated heading");
    expect(preview.querySelector("a, script, iframe, form, input, video")).toBeNull();
    expect(preview.textContent).toContain("Plain link text");
    expect(preview.querySelector("table code")).toBeNull();
    expect(preview.querySelector("table")).not.toBeNull();
    expect(preview.querySelector("pre code")?.className).toBe("language-js");
  });

  it("caches successful page requests and ignores stale page responses", async () => {
    let resolveAlpha: ((response: Response) => void) | undefined;
    const alphaResponse = new Promise<Response>((resolve) => { resolveAlpha = resolve; });
    const fetchMock = vi.fn((input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("catalog.v1.json")) {
        return Promise.resolve(new Response(catalog([
          { id: "a.md", title: "Alpha", url: "/a/" },
          { id: "b.md", title: "Beta", url: "/b/" }
        ]), { status: 200 }));
      }
      if (url.endsWith("/a/")) return alphaResponse;
      return Promise.resolve(new Response('<div class="note-content"><p>Beta body.</p></div>', { status: 200 }));
    });
    vi.stubGlobal("fetch", fetchMock);
    const alpha = anchor("a.md");
    const beta = anchor("b.md");
    const { initialisePreviews } = await import("../../src/frontend/preview");
    initialisePreviews();

    alpha.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/a/", expect.any(Object)));
    beta.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")?.textContent).toContain("Beta body."));
    resolveAlpha?.(new Response('<div class="note-content"><p>Alpha body.</p></div>', { status: 200 }));
    await Promise.resolve();
    await Promise.resolve();
    expect(document.querySelector("[data-note-preview]")?.textContent).toContain("Beta body.");
    expect(document.querySelector("[data-note-preview]")?.textContent).not.toContain("Alpha body.");

    beta.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 120));
    alpha.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")?.textContent).toContain("Alpha body."));
    expect(fetchMock.mock.calls.filter(([url]) => String(url).endsWith("/a/"))).toHaveLength(1);
  });

  it("stays open across the anchor and card, contains wheel events, and leaves touch clicks alone", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => String(input).includes("catalog")
      ? new Response(catalog([{ id: "safe.md", title: "Safe", url: "/safe/" }]), { status: 200 })
      : new Response('<div class="note-content"><p>Body.</p></div>', { status: 200 })));
    const link = anchor("safe.md");
    const { initialisePreviews } = await import("../../src/frontend/preview");
    initialisePreviews();
    link.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "mouse" }));
    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")).not.toBeNull());
    const preview = document.querySelector<HTMLElement>("[data-note-preview]")!;
    link.dispatchEvent(new PointerEvent("pointerout", { bubbles: true, pointerType: "mouse", relatedTarget: preview }));
    await new Promise((resolve) => setTimeout(resolve, 120));
    expect(document.querySelector("[data-note-preview]")).toBe(preview);

    const outerWheel = vi.fn();
    document.addEventListener("wheel", outerWheel, { once: true });
    const body = preview.querySelector<HTMLElement>(".note-preview__body")!;
    Object.defineProperties(body, {
      clientHeight: { configurable: true, value: 200 },
      scrollHeight: { configurable: true, value: 1_000 }
    });
    const wheel = new WheelEvent("wheel", { bubbles: true, cancelable: true, deltaY: 300 });
    body.dispatchEvent(wheel);
    expect(outerWheel).not.toHaveBeenCalled();
    expect(wheel.defaultPrevented).toBe(true);
    expect(body.scrollTop).toBe(300);

    const touchClick = new MouseEvent("click", { bubbles: true, cancelable: true });
    link.dispatchEvent(touchClick);
    expect(touchClick.defaultPrevented).toBe(false);
  });

  it("keeps the preview controller live across a persisted pagehide", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => String(input).includes("catalog")
      ? new Response(catalog([{ id: "safe.md", title: "Safe", url: "/safe/" }]), { status: 200 })
      : new Response('<div class="note-content"><p>Body.</p></div>', { status: 200 })));
    const link = anchor("safe.md");
    const { initialisePreviews } = await import("../../src/frontend/preview");
    initialisePreviews();
    link.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "mouse" }));
    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")).not.toBeNull());
    const preview = document.querySelector<HTMLElement>("[data-note-preview]")!;

    const pagehide = new Event("pagehide");
    Object.defineProperty(pagehide, "persisted", { value: true });
    window.dispatchEvent(pagehide);
    const pageshow = new Event("pageshow");
    Object.defineProperty(pageshow, "persisted", { value: true });
    window.dispatchEvent(pageshow);

    expect(preview.isConnected).toBe(true);
    link.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "mouse" }));
    expect(document.querySelector("[data-note-preview]")).toBe(preview);
  });
});
