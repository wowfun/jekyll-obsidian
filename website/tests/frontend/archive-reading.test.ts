import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { articleBody, initialiseArchiveReading } from "../../src/frontend/archive-reading";

let dispose = () => {};
beforeEach(() => {
  localStorage.clear();
  document.body.innerHTML = '<button data-archive-reading-toggle hidden></button><main><div data-filter-list></div></main>';
});
afterEach(() => { dispose(); vi.unstubAllGlobals(); });
function rows(count: number, offset = 0): void {
  document.querySelector('[data-filter-list]')!.innerHTML = Array.from({ length: count }, (_, i) => `<li data-filter-item><div class="blog-ledger__content"><a class="blog-ledger__main" href="/items/${i + offset}/">Item</a><span class="blog-ledger__description">Description</span></div></li>`).join('');
}
function response(text = "Full body"): Response { return new Response(`<div class="note-content"><p>${text}</p><p>Second paragraph</p></div>`, { headers: { 'content-type': 'text/html' } }); }

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
  const reading = initialiseArchiveReading(document.querySelector('main')!); dispose = reading.dispose;
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
});

it("bounds concurrent loads, cancels queued work on switch-off, and ignores late responses", async () => {
  rows(8);
  const resolve: ((value: Response) => void)[] = [];
  const fetch = vi.fn(() => new Promise<Response>(done => resolve.push(done))); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!); dispose = reading.dispose;
  const toggle = document.querySelector<HTMLButtonElement>('button')!; toggle.click();
  expect(fetch).toHaveBeenCalledTimes(4);
  toggle.click(); resolve.forEach(done => done(response()));
  await vi.waitFor(() => expect(document.querySelector('main')!.classList.contains('archive-reading')).toBe(false));
  expect(document.querySelector('[data-reading-loaded]')).toBeNull();
  expect(fetch).toHaveBeenCalledTimes(4);
});

it("retries a failed article while keeping successful articles and the description", async () => {
  rows(2);
  const fetch = vi.fn().mockResolvedValueOnce(new Response('', { status: 503 })).mockImplementation(async () => response()); vi.stubGlobal('fetch', fetch);
  const reading = initialiseArchiveReading(document.querySelector('main')!); dispose = reading.dispose;
  document.querySelector<HTMLButtonElement>('button')!.click();
  await vi.waitFor(() => expect(document.querySelector('[data-reading-retry]')).not.toBeNull());
  document.querySelector<HTMLButtonElement>('[data-reading-retry]')!.click();
  await vi.waitFor(() => expect(document.querySelectorAll('[data-reading-loaded]')).toHaveLength(2));
  expect(fetch).toHaveBeenCalledTimes(3);
});
