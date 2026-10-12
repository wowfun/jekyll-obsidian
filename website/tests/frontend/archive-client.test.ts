import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createArchiveClient } from '../../src/frontend/archive-client';
import type { ArchiveCard } from '../../src/frontend/archive-query';

let client: ReturnType<typeof createArchiveClient>;
beforeEach(() => {
  document.head.innerHTML = '<meta name="website:archive-worker" content="/worker.js">';
  vi.stubGlobal('Worker', class { terminate() {} });
  client = createArchiveClient('/archive/manifest.json');
});
afterEach(() => { client.dispose(); vi.unstubAllGlobals(); });
const card = (i: number) => ({ markdown_url: `/article-${i}.md` }) as ArchiveCard;
const manifest = { version: 1, generation: 'a'.repeat(64), total: 0, page_size: 50, export_max_days: 7, facets: {}, prefixes: {}, labels: {}, aliases: {}, years: {}, months: {}, days: {}, chunks: [] };

it('coalesces manifest subscribers without letting one cancellation abort another', async () => {
  let resolve!: (value: Response) => void, networkSignal!: AbortSignal;
  const fetch = vi.fn((_url, options) => { networkSignal = options.signal; return new Promise<Response>(done => { resolve = done; }); });
  vi.stubGlobal('fetch', fetch);
  const first = new AbortController(), second = new AbortController();
  const results = Promise.allSettled([client.manifest(first.signal), client.manifest(second.signal)]);
  expect(fetch).toHaveBeenCalledTimes(1);
  first.abort(); expect(networkSignal.aborted).toBe(false);
  resolve(Response.json(manifest));
  expect((await results).map(result => result.status)).toEqual(['rejected', 'fulfilled']);
  expect(await client.manifest()).toEqual(manifest);
  expect(fetch).toHaveBeenCalledTimes(1);
});

it('aborts an unneeded shared load and allows an immediate fresh subscription', async () => {
  const signals: AbortSignal[] = [], responses: ((value: Response) => void)[] = [];
  const fetch = vi.fn((_url, options) => { signals.push(options.signal); return new Promise<Response>(done => responses.push(done)); });
  vi.stubGlobal('fetch', fetch);
  const first = new AbortController(), second = new AbortController();
  const cancelled = Promise.allSettled([client.manifest(first.signal), client.manifest(second.signal)]);
  first.abort(); second.abort();
  expect(signals.every(signal => signal.aborted)).toBe(true);
  const fresh = client.manifest();
  expect(fetch).toHaveBeenCalledTimes(2);
  responses[0]!(Response.json({ ...manifest, generation: 'b'.repeat(64) }));
  responses[1]!(Response.json(manifest));
  expect((await cancelled).every(result => result.status === 'rejected')).toBe(true);
  expect((await fresh).generation).toBe(manifest.generation);
  expect((await client.manifest()).generation).toBe(manifest.generation);
});

it('coalesces overlapping card loads after the manifest has loaded', async () => {
  let resolve!: (value: Response) => void;
  const fetch = vi.fn().mockResolvedValueOnce(Response.json({ ...manifest, total: 1, chunks: ['cards-0.json'] }))
    .mockImplementation(() => new Promise<Response>(done => { resolve = done; }));
  vi.stubGlobal('fetch', fetch);
  await client.manifest();
  const results = Promise.all([client.cards([0]), client.cards([0])]);
  await vi.waitFor(() => expect(fetch).toHaveBeenCalledTimes(2));
  const entry = { ...card(0), id: 'a', title: 'A', url: '/a/', year: '2026', facets: {} };
  resolve(Response.json({ generation: manifest.generation, start: 0, cards: [entry] }));
  expect(await results).toEqual([[entry], [entry]]);
  expect(fetch).toHaveBeenCalledTimes(2);
});

it('shares four request slots, aborts queued work and rejects late responses', async () => {
  const responses: ((value: Response) => void)[] = [], signals: AbortSignal[] = [];
  const fetch = vi.fn((_url, options) => { signals.push(options.signal); return new Promise<Response>(resolve => responses.push(resolve)); });
  vi.stubGlobal('fetch', fetch);
  const controller = new AbortController();
  const settled = Promise.allSettled(Array.from({ length: 8 }, (_, i) => i % 2 ? client.article(`/article-${i}/`, controller.signal) : client.markdown(card(i), controller.signal)));
  expect(fetch).toHaveBeenCalledTimes(4);
  controller.abort(); expect(signals.every(signal => signal.aborted)).toBe(true);
  responses.forEach(resolve => resolve(new Response('# Late', { headers: { 'content-type': 'text/markdown' } })));
  expect((await settled).every(result => result.status === 'rejected')).toBe(true);
  expect(fetch).toHaveBeenCalledTimes(4);
  vi.stubGlobal('fetch', vi.fn(async () => new Response('# Good', { headers: { 'content-type': 'text/plain; charset=utf-8' } })));
  expect(await client.markdown(card(9), new AbortController().signal)).toBe('# Good');
});

it('rejects HTML fallback pages and cross-origin Markdown resources', async () => {
  const fetch = vi.fn(async () => new Response('<html>Not found</html>', { headers: { 'content-type': 'text/html' } })); vi.stubGlobal('fetch', fetch);
  await expect(client.markdown(card(0), new AbortController().signal)).rejects.toThrow('Markdown load failed');
  await expect(client.markdown({ markdown_url: 'https://remote.invalid/a.md' } as ArchiveCard, new AbortController().signal)).rejects.toThrow('Invalid archive URL');
  expect(fetch).toHaveBeenCalledTimes(1);
});
