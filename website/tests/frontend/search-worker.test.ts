import { afterEach, expect, it, vi } from 'vitest';
import type { SearchWorkerRequest, SearchWorkerResponse } from '../../src/frontend/search-protocol';

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules(); });

it('coalesces queued queries, reports the real match count and returns bounded excerpts', async () => {
  const scope = { onmessage: null as ((event: MessageEvent<SearchWorkerRequest>) => void) | null, postMessage: vi.fn() };
  vi.stubGlobal('self', scope);
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ schema_version: 1, documents:
    Array.from({ length: 30 }, (_, i) => ({ id: String(i), title: `Note ${i}`, url: `/${i}/`, aliases: [], tags: [], text: `${'prefix '.repeat(100)}needle body <script>` }))
  }))));
  await import('../../src/frontend/search-worker');
  scope.onmessage!(new MessageEvent('message', { data: { type: 'init', url: '/search.json' } }));
  await vi.waitFor(() => expect(scope.postMessage).toHaveBeenCalledWith({ type: 'ready' }));
  vi.useFakeTimers();
  for (let id = 1; id <= 100; id++) scope.onmessage!(new MessageEvent('message', { data: { type: 'query', id, query: 'needle' } }));
  await vi.advanceTimersByTimeAsync(30);
  const messages = scope.postMessage.mock.calls.map(([message]) => message as SearchWorkerResponse).filter(message => message.type === 'results');
  expect(messages).toHaveLength(1);
  expect(messages[0]).toMatchObject({ id: 100, total: 30 });
  expect(messages[0]!.results).toHaveLength(12);
  expect(messages[0]!.results[0]!.excerpt).toContain('needle');
  expect(messages[0]!.results[0]!.excerpt!.length).toBeLessThanOrEqual(182);
});

it('bounds index terms and reports incomplete text coverage instead of growing the index indefinitely', async () => {
  const scope = { onmessage: null as ((event: MessageEvent<SearchWorkerRequest>) => void) | null, postMessage: vi.fn() };
  vi.stubGlobal('self', scope);
  const text = Array.from({ length: 12_000 }, (_, i) => `term${i}`).join(' ');
  vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ schema_version: 1, documents:
    Array.from({ length: 25 }, (_, i) => ({ id: String(i), title: `Note ${i}`, url: `/${i}/`, aliases: [], tags: [], text }))
  }))));
  await import('../../src/frontend/search-worker');
  scope.onmessage!(new MessageEvent('message', { data: { type: 'init', url: '/search.json' } }));
  await vi.waitFor(() => expect(scope.postMessage).toHaveBeenCalledWith({ type: 'ready' }));
  scope.onmessage!(new MessageEvent('message', { data: { type: 'query', id: 1, query: 'term1' } }));
  await vi.waitFor(() => expect(scope.postMessage).toHaveBeenLastCalledWith(expect.objectContaining({ type: 'results', limited: true })));
  const result = scope.postMessage.mock.calls.at(-1)![0] as Extract<SearchWorkerResponse, { type: 'results' }>;
  expect(result.total).toBeLessThan(25);
  expect(result.results.length).toBeLessThanOrEqual(12);
});
