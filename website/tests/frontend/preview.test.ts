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

function expand(link: HTMLAnchorElement) {
  link.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, altKey: true, key: "ArrowDown" }));
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

    expand(link);
    await vi.waitFor(() => expect(document.querySelector("[data-preview-body-ready]")).not.toBeNull());

    const preview = document.querySelector<HTMLElement>("[data-note-preview]")!;
    expect(preview.querySelector(".note-preview__title")?.textContent).toBe("Safe note");
    expect(preview.querySelector(".note-preview__title-link")?.getAttribute("href")).toBe("/safe/");
    expect(preview.querySelector(".note-preview__description")?.textContent).toBe("A useful summary.");
    expect(preview.querySelector(".note-preview__body")?.textContent).toContain("First paragraph.");
    expect(preview.querySelector("h1")).toBeNull();
    expect(preview.textContent).not.toContain("Repeated heading");
    expect(preview.querySelector(".note-preview__body a, script, iframe, form, input, video")).toBeNull();
    expect(preview.textContent).toContain("Plain link text");
    expect(preview.querySelector("table code")).toBeNull();
    expect(preview.querySelector("table")).not.toBeNull();
    expect(preview.querySelector("pre code")?.className).toBe("language-js");

    link.focus();
    expand(link);
    await vi.waitFor(() => expect(document.activeElement).toBe(preview.querySelector('a')));
    const titleLink = preview.querySelector<HTMLAnchorElement>(".note-preview__title-link")!;
    expect(document.activeElement).toBe(titleLink);
    titleLink.dispatchEvent(new KeyboardEvent("keydown", { bubbles: true, cancelable: true, key: "Tab" }));
    expect(document.activeElement).toBe(preview.querySelector(".note-preview__body"));
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

    expand(alpha);
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/a/", expect.any(Object)));
    const alphaSignal = (fetchMock.mock.calls.find(([url]) => url === '/a/') as unknown as [string, RequestInit])[1].signal!;
    expand(beta);
    expect(alphaSignal.aborted).toBe(true);
    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")?.textContent).toContain("Beta body."));
    resolveAlpha?.(new Response('<div class="note-content"><p>Alpha body.</p></div>', { status: 200 }));
    await Promise.resolve();
    await Promise.resolve();
    expect(document.querySelector("[data-note-preview]")?.textContent).toContain("Beta body.");
    expect(document.querySelector("[data-note-preview]")?.textContent).not.toContain("Alpha body.");

    beta.dispatchEvent(new FocusEvent("focusout", { bubbles: true }));
    await new Promise((resolve) => setTimeout(resolve, 120));
    expand(alpha);
    await vi.waitFor(() => expect(document.querySelector("[data-note-preview]")?.textContent).toContain("Alpha body."));
    expect(fetchMock.mock.calls.filter(([url]) => String(url).endsWith("/a/"))).toHaveLength(2);
  });

  it("stays open across the anchor and card, contains wheel events, and leaves touch clicks alone", async () => {
    vi.stubGlobal("fetch", vi.fn(async (input: RequestInfo | URL) => String(input).includes("catalog")
      ? new Response(catalog([{ id: "safe.md", title: "Safe", url: "/safe/" }]), { status: 200 })
      : new Response('<div class="note-content"><p>Body.</p></div>', { status: 200 })));
    const link = anchor("safe.md");
    const { initialisePreviews } = await import("../../src/frontend/preview");
    initialisePreviews();
    link.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "mouse" }));
    await new Promise((resolve) => setTimeout(resolve, 150));
    link.dispatchEvent(new PointerEvent("pointerout", { bubbles: true, pointerType: "mouse", relatedTarget: document.body }));
    await new Promise((resolve) => setTimeout(resolve, 180));
    expect(document.querySelector("[data-note-preview]")).toBeNull();
    link.dispatchEvent(new PointerEvent("pointerover", { bubbles: true, pointerType: "mouse" }));
    await new Promise((resolve) => setTimeout(resolve, 250));
    expect(document.querySelector("[data-note-preview]")).toBeNull();
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

    body.scrollTop = 800;
    const boundary = new WheelEvent("wheel", { bubbles: true, cancelable: true, deltaY: 100 });
    body.dispatchEvent(boundary);
    expect(boundary.defaultPrevented).toBe(false);
    expect(outerWheel).toHaveBeenCalledOnce();

    const touchClick = new MouseEvent("click", { bubbles: true, cancelable: true });
    link.dispatchEvent(touchClick);
    expect(touchClick.defaultPrevented).toBe(false);
  });

  it("keeps ordinary keyboard focus on the page and only fetches bodies after explicit expansion", async () => {
    const fetchMock = vi.fn(async () => new Response(catalog([{ id: 'a.md', title: 'A', url: '/a/' }])));
    vi.stubGlobal('fetch', fetchMock);
    const link = anchor('a.md');
    const { initialisePreviews } = await import('../../src/frontend/preview');
    initialisePreviews(); link.focus();
    await vi.waitFor(() => expect(document.querySelector('[data-note-preview]')).not.toBeNull());
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const tab = new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true });
    link.dispatchEvent(tab);
    expect(tab.defaultPrevented).toBe(false);
    expect(document.querySelector('[data-note-preview]')).toBeNull();
  });

  it("keeps the catalog and body cache usable after tabbing out of an expanded preview", async () => {
    let catalogSignal: AbortSignal | undefined;
    const fetchMock = vi.fn(async (input: RequestInfo | URL, options?: RequestInit) => {
      if (String(input).includes('catalog')) {
        catalogSignal = options?.signal as AbortSignal;
        return new Response(catalog([{ id: 'a.md', title: 'A', url: '/a/' }]));
      }
      return new Response('<div class="note-content"><p>Body</p></div>');
    });
    vi.stubGlobal('fetch', fetchMock);
    const link = anchor('a.md');
    const { initialisePreviews } = await import('../../src/frontend/preview');
    initialisePreviews(); expand(link);
    await vi.waitFor(() => expect(document.querySelector('[data-preview-body-ready]')).not.toBeNull());
    document.querySelector('.note-preview__body')!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true, cancelable: true }));
    expect(document.querySelector('[data-note-preview]')).toBeNull();
    expect(catalogSignal?.aborted).toBe(false);
    expand(link);
    await vi.waitFor(() => expect(document.querySelector('[data-preview-body-ready]')).not.toBeNull());
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("aborts a pending catalog download when the page controller is disposed", async () => {
    let signal: AbortSignal | undefined;
    vi.stubGlobal('fetch', vi.fn((_input: RequestInfo | URL, options?: RequestInit) => {
      signal = options?.signal as AbortSignal;
      return new Promise<Response>((_resolve, reject) => signal!.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true }));
    }));
    const link = anchor('a.md');
    const { initialisePreviews } = await import('../../src/frontend/preview');
    initialisePreviews(); link.focus();
    await vi.waitFor(() => expect(signal).toBeDefined());
    window.dispatchEvent(new Event('pagehide'));
    expect(signal!.aborted).toBe(true);
    await Promise.resolve();
    expect(document.querySelector('[data-note-preview]')).toBeNull();
  });

  it.each([['entry count', 25, 20], ['byte weight', 4, 750_000]] as const)("evicts by %s and clears cached bodies on navigation", async (_name, count, bytes) => {
    const notes = Array.from({ length: count }, (_, id) => ({ id: `${id}.md`, title: String(id), url: `/${id}/` }));
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => new Response(String(input).includes('catalog')
      ? catalog(notes) : `<div class="note-content"><p>${'a'.repeat(bytes)}</p></div>`));
    vi.stubGlobal('fetch', fetchMock);
    const links = notes.map(note => anchor(note.id));
    const { initialisePreviews } = await import('../../src/frontend/preview');
    initialisePreviews();
    for (const link of links) {
      expand(link);
      await vi.waitFor(() => expect(document.querySelector('.note-preview__title')?.textContent).toBe(link.dataset.noteId!.replace('.md', '')));
      await vi.waitFor(() => expect(document.querySelector('[data-preview-body-ready]')).not.toBeNull());
    }
    expand(links[0]!);
    await vi.waitFor(() => expect(fetchMock.mock.calls.filter(([url]) => url === '/0/')).toHaveLength(2));
    await vi.waitFor(() => expect(document.querySelector('[data-preview-body-ready]')).not.toBeNull());
    initialisePreviews(); expand(links[0]!);
    await vi.waitFor(() => expect(fetchMock.mock.calls.filter(([url]) => url === '/0/')).toHaveLength(3));
  });

  it("retries a failed body request", async () => {
    let attempts = 0;
    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL) => {
      if (String(input).includes('catalog')) return new Response(catalog([{ id: 'a.md', title: 'A', url: '/a/' }]));
      return ++attempts === 1 ? new Response('', { status: 503 }) : new Response('<div class="note-content"><p>Recovered</p></div>');
    }));
    const link = anchor('a.md');
    const { initialisePreviews } = await import('../../src/frontend/preview');
    initialisePreviews(); expand(link);
    await vi.waitFor(() => expect(document.querySelector('[data-preview-body-error]')).not.toBeNull());
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expand(link);
    await vi.waitFor(() => expect(document.querySelector('[data-preview-body-ready]')?.textContent).toBe('Recovered'));
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
