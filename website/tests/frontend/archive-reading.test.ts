import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { createArchiveClient, type ArchiveClient } from "../../src/frontend/archive-client";
import { articleBody, initialiseArchiveReading } from "../../src/frontend/archive-reading";

let dispose = () => {};
let client: ArchiveClient;
beforeEach(() => {
  localStorage.clear();
  vi.stubGlobal('IntersectionObserver', undefined);
  document.head.innerHTML = '<meta name="website:archive-worker" content="/worker.js">';
  vi.stubGlobal("Worker", class { terminate() {} });
  client = createArchiveClient("/archive/manifest.json");
  document.body.innerHTML = '<button data-archive-reading-toggle hidden></button><main><div data-filter-list></div></main>';
});
afterEach(() => { dispose(); client.dispose(); vi.unstubAllGlobals(); });
function rows(count: number, offset = 0): void {
  document.querySelector('[data-filter-list]')!.innerHTML = Array.from({ length: count }, (_, i) => `<li data-filter-item><div class="blog-ledger__content"><a class="blog-ledger__main" href="/items/${i + offset}/">Item</a><span class="blog-ledger__description">Description</span></div></li>`).join('');
}
function response(text = "Full body"): Response { return new Response(`<div class="note-content"><p>${text}</p><p>Second paragraph</p></div>`, { headers: { 'content-type': 'text/html' } }); }

it('loads newly opened days without reloading existing bodies, including without IntersectionObserver', async () => {
  rows(2);
  const items = [...document.querySelectorAll<HTMLElement>('[data-filter-item]')];
  for (const [index, row] of items.entries()) {
    const group = document.createElement('details'); group.dataset.ledgerDay = `2026-10-${15 - index}`; group.open = index === 0;
    row.before(group); group.append(row);
  }
  const fetch = vi.fn(async () => response()); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(1));
  await vi.waitFor(() => expect(items[0]!.dataset.readingLoaded).toBe('true'));
  const second = items[1]!.parentElement as HTMLDetailsElement; second.open = true; second.dispatchEvent(new Event('toggle'));
  await vi.waitFor(() => expect(items[1]!.dataset.readingLoaded).toBe('true'));
  second.open = false; second.dispatchEvent(new Event('toggle'));
  second.open = true; second.dispatchEvent(new Event('toggle'));
  expect(fetch).toHaveBeenCalledTimes(2);
  expect(items[0]!.dataset.readingLoaded).toBe('true');
});

it('evicts the least recently used body at 100 entries while preserving recently revisited bodies', async () => {
  rows(100);
  const fetch = vi.fn(async () => response()); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(100));
  async function visit(offset: number) {
    rows(1, offset); reading.refresh();
    await vi.waitFor(() => expect(document.querySelector('[data-reading-loaded]')).not.toBeNull());
  }
  await visit(0); expect(fetch).toHaveBeenCalledTimes(100);
  await visit(100); expect(fetch).toHaveBeenCalledTimes(101);
  await visit(0); expect(fetch).toHaveBeenCalledTimes(101);
  await visit(1); expect(fetch).toHaveBeenCalledTimes(102);
});

it('evicts bodies by source weight even below the entry limit and still displays an oversized body', async () => {
  rows(1);
  // Padding outside the retained body tests the documented source-size proxy.
  let padding = 1_200_000;
  const fetch = vi.fn(async () => response('</p><!--' + 'x'.repeat(padding) + '--><p>Visible'));
  vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  async function loaded() { await vi.waitFor(() => expect(document.querySelector('[data-reading-loaded]')).not.toBeNull()); }
  await loaded();
  rows(1, 1); reading.refresh(); await loaded();
  rows(1); reading.refresh(); await loaded();
  expect(fetch).toHaveBeenCalledTimes(3);
  padding = 2_200_000;
  rows(1, 2); reading.refresh(); await loaded();
  expect(document.querySelector('.archive-reading__body')!.textContent).toContain('Visible');
  rows(1, 2); reading.refresh(); await loaded();
  expect(fetch).toHaveBeenCalledTimes(5);
});

it('loads only rows approaching the viewport and disconnects stale observations', async () => {
  rows(50);
  const observers: { notify: (rows: Element[]) => void; disconnect: ReturnType<typeof vi.fn> }[] = [];
  vi.stubGlobal('IntersectionObserver', class {
    disconnect = vi.fn(); observe = vi.fn(); unobserve = vi.fn();
    constructor(callback: IntersectionObserverCallback) {
      observers.push({ notify: rows => callback(rows.map(target => ({ target, isIntersecting: true })) as IntersectionObserverEntry[], this as unknown as IntersectionObserver), disconnect: this.disconnect });
    }
  });
  const fetch = vi.fn(async () => response()); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  const toggle = document.querySelector<HTMLButtonElement>('button')!; toggle.click();
  expect(fetch).not.toHaveBeenCalled();
  observers[0]!.notify([document.querySelector('[data-filter-item]')!]);
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(1));
  expect(fetch).toHaveBeenCalledTimes(1);
  toggle.click(); expect(observers[0]!.disconnect).toHaveBeenCalled();
  observers[0]!.notify([document.querySelectorAll('[data-filter-item]')[49]!]);
  expect(fetch).toHaveBeenCalledTimes(1);
  toggle.click();
  observers[1]!.notify([document.querySelectorAll('[data-filter-item]')[49]!]);
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(2));
  expect(fetch).toHaveBeenCalledTimes(2);
});

it("keeps prose and links, resolves relative URLs and scopes fragments without executing source markup", () => {
  const host = document.createElement('div');
  host.append(articleBody('<div class="note-content"><h2 id="same">Heading</h2><a href="#same">Jump</a><a href="../other/">Other</a><p onclick="bad()">Text</p><img src="image.png" onerror="bad()"><script>bad()</script><iframe src="https://example.com"></iframe><a href="javascript:bad()">Bad</a></div>', 'https://example.com/items/a/', 'article-1'));
  expect(host.querySelector('h2')!.id).toBe('article-1-0');
  expect(host.querySelector('a')!.getAttribute('href')).toBe('#article-1-0');
  expect(host.querySelectorAll('a')[1]!.getAttribute('href')).toBe('https://example.com/items/other/');
  expect(host.querySelector('img')!.getAttribute('src')).toBe('https://example.com/items/a/image.png');
  expect(host.querySelector('script, iframe, [onclick], [onerror], [href^="javascript:"]')).toBeNull();
  expect(host.textContent).toContain('Text');
});

it("loads only the current page on demand and retains successful bodies across toggles", async () => {
  rows(2);
  const fetch = vi.fn(async (_url: URL) => response()); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  expect(fetch).not.toHaveBeenCalled();
  const toggle = document.querySelector<HTMLButtonElement>('button')!; toggle.click();
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(2));
  expect(fetch).toHaveBeenCalledTimes(2);
  expect(toggle.getAttribute('aria-checked')).toBe('true');
  expect(document.querySelectorAll('.archive-reading__body p')).toHaveLength(4);
  toggle.click(); toggle.click();
  expect(fetch).toHaveBeenCalledTimes(2);
  rows(1, 2); reading.refresh();
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(1));
  expect(fetch).toHaveBeenCalledTimes(3);
  expect(String(fetch.mock.calls[2]![0])).toContain('/items/2/');
  rows(2); reading.refresh();
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(2));
  expect(fetch).toHaveBeenCalledTimes(3);
});

it('resolves article media and local fragments against the final redirect URL', async () => {
  rows(1);
  const redirected = response('<h2 id="heading">Heading</h2><a href="/canonical/note/#heading">Jump</a><img src="image.png">');
  Object.defineProperty(redirected, 'url', { value: new URL('/canonical/note/', location.href).href });
  vi.stubGlobal('fetch', vi.fn(async () => redirected));
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  await vi.waitFor(() => expect(document.querySelector('[data-reading-loaded]')).not.toBeNull());
  const body = document.querySelector('.archive-reading__body')!;
  expect(body.querySelector('img')!.getAttribute('src')).toBe(new URL('/canonical/note/image.png', location.href).href);
  expect(body.querySelector('a')!.getAttribute('href')).toBe('#' + body.querySelector('h2')!.id);
});

it("bounds concurrent loads, cancels queued work on switch-off, and ignores late responses", async () => {
  rows(8);
  const resolve: ((value: Response) => void)[] = [];
  const fetch = vi.fn(() => new Promise<Response>(done => resolve.push(done))); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  const toggle = document.querySelector<HTMLButtonElement>('button')!; toggle.click();
  expect(fetch).toHaveBeenCalledTimes(4);
  toggle.click(); resolve.forEach(done => done(response()));
  await vi.waitFor(() => expect(document.querySelector('main')!.classList.contains('archive-reading')).toBe(false));
  expect(document.querySelector('[data-reading-loaded]')).toBeNull();
  expect(fetch).toHaveBeenCalledTimes(4);
});

it("preserves the client-wide request limit when another date opens without IntersectionObserver", async () => {
  rows(8);
  const root = document.querySelector<HTMLElement>("main")!;
  const entries = [...root.querySelectorAll<HTMLElement>("[data-filter-item]")];
  const first = document.createElement("details"), second = document.createElement("details");
  first.dataset.ledgerDay = "2026-10-15"; first.open = true; second.dataset.ledgerDay = "2026-10-14";
  first.append(...entries.slice(0, 4)); second.append(...entries.slice(4)); root.append(first, second);
  const finish: ((response: Response) => void)[] = [];
  const fetch = vi.fn(() => new Promise<Response>(resolve => finish.push(resolve))); vi.stubGlobal("fetch", fetch);
  const reading = initialiseArchiveReading(root, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>("button")!.click();
  expect(fetch).toHaveBeenCalledTimes(4);
  second.open = true; second.dispatchEvent(new Event("toggle"));
  expect(fetch).toHaveBeenCalledTimes(4);
  finish.slice(0, 4).forEach(resolve => resolve(response()));
  await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(8));
  finish.slice(4).forEach(resolve => resolve(response()));
  await vi.waitFor(() => expect(root.querySelectorAll("[data-reading-loaded]")).toHaveLength(8));
});

it("retries a failed article while keeping successful articles and the description", async () => {
  rows(2);
  const fetch = vi.fn().mockResolvedValueOnce(new Response('', { status: 503 })).mockImplementation(async () => response()); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  await vi.waitFor(() => expect(document.querySelector('[data-reading-retry]')).not.toBeNull());
  document.querySelector<HTMLButtonElement>('[data-reading-retry]')!.click();
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(2));
  expect(fetch).toHaveBeenCalledTimes(3);
});

it('retries only the failed row without aborting another article still loading', async () => {
  rows(2);
  let finish!: (value: Response) => void, pendingSignal!: AbortSignal;
  const fetch = vi.fn().mockResolvedValueOnce(new Response('', { status: 503 }))
    .mockImplementationOnce((_url, options) => { pendingSignal = options.signal; return new Promise<Response>(resolve => { finish = resolve; }); })
    .mockImplementation(async () => response());
  vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!, client); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  await vi.waitFor(() => expect(document.querySelector('[data-reading-retry]')).not.toBeNull());
  document.querySelector<HTMLButtonElement>('[data-reading-retry]')!.click();
  expect(pendingSignal.aborted).toBe(false);
  finish(response());
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(2));
  expect(fetch).toHaveBeenCalledTimes(3);
});
