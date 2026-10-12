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

it('shares four request slots, aborts queued work and rejects late responses', async () => {
  const responses: ((value: Response) => void)[] = [], signals: AbortSignal[] = [];
  const fetch = vi.fn((_url, options) => { signals.push(options.signal); return new Promise<Response>(resolve => responses.push(resolve)); });
  vi.stubGlobal('fetch', fetch);
  const controller = new AbortController();
  const settled = Promise.allSettled(Array.from({ length: 8 }, (_, i) => client.markdown(card(i), controller.signal)));
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
