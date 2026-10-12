import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { createArchiveClient } from '../../src/frontend/archive-client';
import { archiveState, type ArchiveCard } from '../../src/frontend/archive-query';
import { ArchiveBodyBudget } from '../../src/frontend/archive-export-budget';

let client: ReturnType<typeof createArchiveClient>;
beforeEach(() => {
  document.head.innerHTML = '<meta name="website:archive-worker" content="/worker.js">';
  vi.stubGlobal('Worker', class { terminate() {} });
  client = createArchiveClient('/archive/manifest.json');
});
afterEach(() => { client.dispose(); vi.useRealTimers(); vi.unstubAllGlobals(); });
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

it('bounds streamed body bytes across entries and releases failed reservations for retry', async () => {
  const budget = new ArchiveBodyBudget(6), cancelled = vi.fn(); let chunk = 0;
  vi.stubGlobal('fetch', vi.fn()
    .mockResolvedValueOnce(new Response('abc', { headers: { 'content-type': 'text/plain' } }))
    .mockResolvedValueOnce(new Response(new ReadableStream({
      pull(controller) { if (chunk === 2) controller.close(); else controller.enqueue(new TextEncoder().encode(['de', 'fg'][chunk++])); },
      cancel: cancelled
    }, { highWaterMark: 0 }), { headers: { 'content-type': 'text/plain' } }))
    .mockResolvedValueOnce(new Response('def', { headers: { 'content-type': 'text/plain' } })));
  const signal = new AbortController().signal;
  expect(await client.markdown(card(0), signal, budget)).toBe('abc');
  await expect(client.markdown(card(1), signal, budget)).rejects.toThrow('size limit');
  expect(cancelled).toHaveBeenCalled();
  expect(await client.markdown(card(1), signal, budget)).toBe('def');
});

it('rejects an empty response that arrives after cancellation', async () => {
  let finish!: (response: Response) => void;
  vi.stubGlobal('fetch', vi.fn(() => new Promise<Response>(resolve => { finish = resolve; })));
  const controller = new AbortController(), result = client.markdown(card(0), controller.signal);
  controller.abort();
  finish(new Response(null, { status: 204, headers: { 'content-type': 'text/plain' } }));
  await expect(result).rejects.toThrow();
});

it('rejects all worker queries immediately and recreates the worker on retry without leaking timers', async () => {
  vi.useFakeTimers();
  const workers: Worker[] = [];
  vi.stubGlobal('Worker', class {
    postMessage = vi.fn(); terminate = vi.fn();
    constructor() { workers.push(this as unknown as Worker); }
  });
  vi.stubGlobal('fetch', vi.fn(async () => Response.json(manifest)));
  const state = archiveState(await client.manifest(), '');
  const failed = Promise.allSettled([client.select(state, 'all'), client.select(state, 'page')]);
  await vi.waitFor(() => expect(workers[0]?.postMessage).toHaveBeenCalledTimes(2));
  workers[0]!.onerror!(new Event('error') as ErrorEvent);
  expect((await failed).map(result => result.status)).toEqual(['rejected', 'rejected']);
  expect(workers[0]!.terminate).toHaveBeenCalledTimes(1);
  expect(vi.getTimerCount()).toBe(0);
  const retry = client.select(state, 'all', undefined, 5000);
  await vi.waitFor(() => expect(workers).toHaveLength(2));
  const request = vi.mocked(workers[1]!.postMessage).mock.calls[0]![0];
  expect(request.limit).toBe(5000);
  workers[1]!.onmessage!(new MessageEvent('message', { data: { id: request.id, count: 0, ordinals: [], page: 1, pages: 1 } }));
  expect((await retry).count).toBe(0);
  expect(vi.getTimerCount()).toBe(0);
});

it.each(['application/octet-stream', null])('accepts generic Markdown hosting (%s) while rejecting disguised HTML/XML', async contentType => {
  const fetch = vi.fn(async () => {
    const response = new Response('# 正文\n\n<details>Valid Markdown HTML</details>');
    if (contentType) response.headers.set('content-type', contentType); else response.headers.delete('content-type');
    return response;
  });
  vi.stubGlobal('fetch', fetch);
  expect(await client.markdown(card(0), new AbortController().signal)).toContain('<details>');
  for (const body of [' \uFEFF<!doctype html><html>Error</html>', '<!-- fallback -->\n<html>Error</html>', '<?xml version="1.0"?><Error>Missing</Error>']) {
    fetch.mockImplementationOnce(async () => new Response(body, { headers: { 'content-type': contentType || 'text/plain' } }));
    await expect(client.markdown(card(0), new AbortController().signal)).rejects.toThrow('Markdown load failed');
  }
});

it.each(['timeout', 'postMessage'])('discards a broken worker after %s and permits retry', async failure => {
  vi.useFakeTimers();
  const workers: Worker[] = [];
  vi.stubGlobal('Worker', class {
    terminate = vi.fn();
    postMessage = vi.fn(() => { if (workers.length === 1 && failure === 'postMessage') throw new Error('Send failed'); });
    constructor() { workers.push(this as unknown as Worker); }
  });
  vi.stubGlobal('fetch', vi.fn(async () => Response.json(manifest)));
  const state = archiveState(await client.manifest(), '');
  const result = client.select(state, 'all');
  const rejected = expect(result).rejects.toThrow(failure === 'timeout' ? 'Archive query timed out' : 'Send failed');
  await vi.waitFor(() => expect(workers).toHaveLength(1));
  if (failure === 'timeout') await vi.advanceTimersByTimeAsync(15000);
  await rejected;
  expect(workers[0]!.terminate).toHaveBeenCalledTimes(1);
  expect(vi.getTimerCount()).toBe(0);
  const cancelled = new AbortController();
  const retry = client.select(state, 'page', cancelled.signal);
  const aborted = expect(retry).rejects.toThrow();
  await vi.waitFor(() => expect(workers).toHaveLength(2));
  cancelled.abort(); await aborted;
  expect(vi.getTimerCount()).toBe(0);
});

it('checks article cancellation before validating or reading a late response', async () => {
  let finish!: (response: Response) => void;
  vi.stubGlobal('fetch', vi.fn(() => new Promise<Response>(resolve => { finish = resolve; })));
  const controller = new AbortController(), reason = new Error('Cancelled by reader');
  const result = client.article('/article/', controller.signal);
  controller.abort(reason);
  const response = new Response('Late error', { status: 503 });
  const read = vi.spyOn(response, 'text'); finish(response);
  await expect(result).rejects.toBe(reason);
  expect(read).not.toHaveBeenCalled();
});
