import { ARCHIVE_POSTING_CACHE_LIMIT, TAB_SOURCES_POSTING_KEY, archiveState, decodeBitmap, type ArchiveCard, type ArchiveManifest, type ArchiveMatches, type ArchiveQueryMode } from "./archive-query";
import { requireSiteUrl } from "./urls";
import { ArchiveBodyBudget } from "./archive-export-budget";
import type { ArchiveWorkerRequest } from "./archive-worker";

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid archive data");
  return value as Record<string, unknown>;
}
export function archiveUrl(value: string, external = false): URL {
  const url = new URL(value, window.location.href);
  if (!/^https?:$/.test(url.protocol) || url.username || url.password || (!external && url.origin !== location.origin)) throw new Error("Invalid archive URL");
  return url;
}
export async function archiveConcurrent<T>(values: readonly T[], operation: (value: T) => Promise<void>, signal: AbortSignal): Promise<void> {
  let index = 0;
  await Promise.all(Array.from({ length: Math.min(4, values.length) }, async () => {
    while (index < values.length) { signal.throwIfAborted(); await operation(values[index++]!); }
  }));
}

interface SharedRequest { controller: AbortController; promise: Promise<unknown>; users: number; settled: boolean }

// One client owns a generation, its worker and a four-request budget shared by
// pagination, reading and export. Subscribers cancel independently; the last cancellation
// aborts a shared request. Only complete, validated data enters the cache.
export function createArchiveClient(source: string) {
  let manifestUrl = archiveUrl(source);
  const lifetime = new AbortController();
  let generationLifetime = new AbortController();
  let worker: Worker | undefined;
  const cache = new Map<string, unknown>();
  const requests = new Map<string, SharedRequest>();
  const postings = new Map<string, Uint8Array>();
  const workerPostings = new Map<string, Uint8Array>();
  let workerGeneration: string | undefined;
  let manifest: ArchiveManifest | undefined, queryId = 0, active = 0;
  let identities: Map<string, number> | undefined;
  const queue: { start: () => void; cancel: () => void }[] = [];
  const pending = new Map<number, { resolve: (result: ArchiveMatches) => void; reject: (error: unknown) => void }>();
  function failWorker(failed: Worker, error: unknown): void {
    if (worker !== failed) return;
    worker = undefined; failed.terminate(); workerPostings.clear(); workerGeneration = undefined;
    for (const job of pending.values()) job.reject(error);
  }
  function queryWorker(): Worker {
    if (!worker) {
      workerPostings.clear(); workerGeneration = undefined;
      const next = new Worker(requireSiteUrl("archive-worker"), { type: "module" });
      next.onmessage = (event: MessageEvent<ArchiveMatches & { id: number }>) => {
        if (worker === next) pending.get(event.data.id)?.resolve(event.data);
      };
      next.onerror = () => failWorker(next, new Error("Archive worker failed"));
      next.onmessageerror = () => failWorker(next, new Error("Invalid archive worker response"));
      worker = next;
    }
    return worker;
  }
  function combined(signal?: AbortSignal): AbortSignal { return AbortSignal.any([lifetime.signal, generationLifetime.signal, ...(signal ? [signal] : [])]); }
  function shared(key: string, signal: AbortSignal, operation: (signal: AbortSignal) => Promise<unknown>): Promise<unknown> {
    signal.throwIfAborted();
    let request = requests.get(key);
    if (!request) {
      const controller = new AbortController();
      const entry: SharedRequest = { controller, users: 0, settled: false,
        promise: operation(combined(controller.signal)).finally(() => {
          entry.settled = true;
          if (requests.get(key) === entry) requests.delete(key);
        })
      };
      requests.set(key, entry); request = entry;
    }
    const entry = request; entry.users++;
    return new Promise((resolve, reject) => {
      let finished = false;
      const leave = () => {
        if (finished) return; finished = true;
        signal.removeEventListener('abort', abort);
        if (--entry.users === 0 && !entry.settled) {
          if (requests.get(key) === entry) requests.delete(key);
          entry.controller.abort();
        }
      };
      const abort = () => { leave(); reject(signal.reason); };
      signal.addEventListener('abort', abort, { once: true });
      entry.promise.then(value => { if (!finished) { leave(); resolve(value); } }, error => { if (!finished) { leave(); reject(error); } });
    });
  }
  async function limited<T>(operation: () => Promise<T>, signal: AbortSignal): Promise<T> {
    signal.throwIfAborted();
    if (active < 4) active++;
    else await new Promise<void>((resolve, reject) => {
      const entry = {
        start() { signal.removeEventListener("abort", entry.cancel); resolve(); },
        cancel() { const index = queue.indexOf(entry); if (index >= 0) queue.splice(index, 1); reject(signal.reason); }
      };
      queue.push(entry); signal.addEventListener("abort", entry.cancel, { once: true });
    });
    try { signal.throwIfAborted(); return await operation(); }
    finally { const next = queue.shift(); if (next) next.start(); else active--; }
  }
  async function resource(filename: string, signal: AbortSignal, revalidate = false): Promise<unknown> {
    signal.throwIfAborted();
    if (cache.has(filename)) { const value = cache.get(filename); cache.delete(filename); cache.set(filename, value); return value; }
    const url = new URL(filename, manifestUrl);
    if (url.origin !== manifestUrl.origin || !url.pathname.startsWith(manifestUrl.pathname.slice(0, manifestUrl.pathname.lastIndexOf("/") + 1))) throw new Error("Invalid archive resource path");
    return shared(url.href, signal, requestSignal => limited(async () => {
      if (cache.has(filename)) return cache.get(filename);
      const response = await fetch(url, { signal: AbortSignal.any([requestSignal, AbortSignal.timeout(15000)]), cache: revalidate ? "no-cache" : "default" });
      if (!response.ok || new URL(response.url || url.href).origin !== manifestUrl.origin) throw new Error("Archive load failed");
      const value: unknown = await response.json();
      requestSignal.throwIfAborted();
      if (filename === "manifest.json") {
        const next = validateManifest(value);
        if (manifest?.generation !== next.generation) { cache.clear(); postings.clear(); identities = undefined; }
        return manifest = next;
      }
      else {
        if (object(value).generation !== manifest?.generation) throw new Error("Archive generation differs");
        cache.set(filename, value);
        while (cache.size > 20) cache.delete(cache.keys().next().value!);
      }
      return value;
    }, requestSignal));
  }
  function validateManifest(value: unknown): ArchiveManifest {
    const data = object(value);
    if (data.version !== 1 || !Number.isSafeInteger(data.total) || Number(data.total) < 0 || !Number.isSafeInteger(data.page_size) || Number(data.page_size) < 1 || Number(data.page_size) > 100 || !Number.isSafeInteger(data.export_max_days) || Number(data.export_max_days) < 1 || typeof data.generation !== "string" || !/^[a-f0-9]{64}$/.test(data.generation) || !Array.isArray(data.chunks)) throw new Error("Invalid archive manifest");
    for (const key of ["facets", "prefixes", "labels", "aliases", "years", "months", "days"]) object(data[key]);
    for (const key of ["hidden_tags", "tab_sources"]) {
      const tags = data[key];
      if (tags !== undefined && (!Array.isArray(tags) || tags.some(tag => typeof tag !== "string" || !tag) || new Set(tags).size !== tags.length)) throw new Error("Invalid archive visibility policy");
    }
    if (data.default_view !== undefined) {
      const view = object(data.default_view);
      const validCount = (value: unknown) => Number.isSafeInteger(value) && Number(value) >= 0 && Number(value) <= Number(data.total);
      if (!validCount(view.total)) throw new Error("Invalid archive view count");
      const mappings = [...Object.values(object(view.facets)), view.years, view.months, view.days];
      for (const mapping of mappings) if (!Object.values(object(mapping)).every(validCount)) throw new Error("Invalid archive view counts");
    }
    if ((data.excluded_posting !== undefined || Array.isArray(data.tab_sources) && data.tab_sources.length)
      && (typeof data.excluded_posting !== "string" || !data.excluded_posting)) throw new Error("Invalid archive exclusion posting");
    const scoped = Array.isArray(data.tab_sources) && data.tab_sources.length > 0;
    if (scoped !== (data.default_view !== undefined) || scoped !== (data.excluded_posting !== undefined)
      || scoped && (typeof object(data.prefixes).source !== "string" || !Array.isArray(object(data.facets).source))) throw new Error("Invalid archive visibility scope");
    if (data.identities !== undefined && typeof data.identities !== "string") throw new Error("Invalid archive identities path");
    if (data.ledger_group_by !== undefined && data.ledger_group_by !== "year" && data.ledger_group_by !== "day") throw new Error("Invalid ledger grouping");
    for (const [name, prefix] of Object.entries(object(data.prefixes))) {
      if (!/^[a-z][a-z0-9_-]*$/.test(name) || typeof prefix !== "string" || !Array.isArray(object(data.facets)[name])) throw new Error("Invalid archive facet");
      for (const entry of object(data.facets)[name] as unknown[]) { const option = object(entry); if (typeof option.id !== "string" || typeof option.name !== "string" || (option.posting !== undefined && typeof option.posting !== "string")) throw new Error("Invalid archive option"); }
    }
    if (data.chunks.length !== Math.ceil(Number(data.total) / Number(data.page_size))) throw new Error("Invalid archive chunk count");
    for (const mapping of [data.years, data.months, data.days]) for (const range of Object.values(object(mapping))) {
      if (!Array.isArray(range) || range.length !== 2 || !range.every(Number.isSafeInteger) || range[0] < 0 || range[1] > Number(data.total) || range[0] > range[1]) throw new Error("Invalid chronology bounds");
    }
    return data as unknown as ArchiveManifest;
  }
  async function getManifest(caller?: AbortSignal): Promise<ArchiveManifest> {
    const signal = combined(caller); signal.throwIfAborted();
    return manifest || await resource("manifest.json", signal) as ArchiveManifest;
  }
  async function revalidate(source: string, caller?: AbortSignal): Promise<ArchiveManifest> {
    const next = archiveUrl(source);
    caller?.throwIfAborted(); lifetime.signal.throwIfAborted();
    if (next.href !== manifestUrl.href) {
      generationLifetime.abort(new Error("Archive generation changed")); generationLifetime = new AbortController();
      manifestUrl = next; manifest = undefined; cache.clear(); postings.clear(); identities = undefined;
    }
    const signal = combined(caller);
    return await resource("manifest.json", signal, true) as ArchiveManifest;
  }
  async function revalidateCurrent(source: string, caller?: AbortSignal): Promise<ArchiveManifest> {
    const signal = combined(caller), url = archiveUrl(source);
    const target = await shared("current:" + url.href, signal, requestSignal => limited(async () => {
      const response = await fetch(url, { signal: AbortSignal.any([requestSignal, AbortSignal.timeout(15000)]), cache: "no-cache", headers: { Accept: "application/json" } });
      if (!response.ok || archiveUrl(response.url || url.href).origin !== url.origin) throw new Error("Current archive could not be loaded");
      const descriptor = object(await response.json()); requestSignal.throwIfAborted();
      if (descriptor.version !== 1 || typeof descriptor.url !== "string") throw new Error("Invalid current archive descriptor");
      const next = archiveUrl(descriptor.url);
      if (!next.pathname.endsWith("/manifest.json")) throw new Error("Invalid current archive manifest path");
      return next.href;
    }, requestSignal));
    // Preserve the caller's lifetime; switching generations aborts the signal
    // used for discovery along with all other requests of the old generation.
    signal.throwIfAborted();
    if (manifest && target === manifestUrl.href) return manifest;
    return revalidate(target as string, caller);
  }
  async function select(state: ReturnType<typeof archiveState>, mode: ArchiveQueryMode, caller?: AbortSignal, limit?: number): Promise<ArchiveMatches> {
    const signal = combined(caller), data = await getManifest(signal);
    const bitmaps: Record<string, Uint8Array> = Object.create(null) as Record<string, Uint8Array>;
    await archiveConcurrent(state.keys, async (key) => {
      const split = key.indexOf("/"), name = key.slice(0, split), id = key.slice(split + 1);
      const option = data.facets[name]?.find(entry => entry.id === id);
      if (!option && key !== TAB_SOURCES_POSTING_KEY) return;
      const filename = key === TAB_SOURCES_POSTING_KEY ? data.excluded_posting : option?.posting;
      if (!filename) throw new Error("Archive does not provide remote filter postings");
      if (!postings.has(key)) {
        const posting = object(await resource(filename, signal));
        if (posting.total !== data.total || typeof posting.bitmap !== "string") throw new Error("Invalid posting");
        if (!postings.has(key)) postings.set(key, decodeBitmap(posting.bitmap, data.total));
      }
      const bitmap = postings.get(key)!; postings.delete(key); postings.set(key, bitmap);
      while (postings.size > ARCHIVE_POSTING_CACHE_LIMIT) postings.delete(postings.keys().next().value!);
      bitmaps[key] = bitmap;
    }, signal);
    signal.throwIfAborted();
    const id = ++queryId, currentWorker = queryWorker();
    return new Promise((resolve, reject) => {
      const finish = () => { clearTimeout(timeout); pending.delete(id); signal.removeEventListener("abort", abort); };
      const abort = () => { finish(); reject(signal.reason); };
      const timeout = setTimeout(() => failWorker(currentWorker, new Error("Archive query timed out")), 15000);
      pending.set(id, { resolve(value) { finish(); resolve(value); }, reject(error) { finish(); reject(error); } });
      signal.addEventListener("abort", abort, { once: true });
      try {
        if (workerGeneration !== data.generation) { workerPostings.clear(); workerGeneration = data.generation; }
        const updates = Object.fromEntries(Object.entries(bitmaps).filter(([key, bitmap]) => workerPostings.get(key) !== bitmap));
        const request: ArchiveWorkerRequest = { id, generation: data.generation, total: data.total, size: data.page_size, query: state.query, bitmaps: updates, mode, limit };
        currentWorker.postMessage(request);
        // Messages to one worker are ordered. Mirror its bounded posting cache
        // only after a successful send; recreation starts with no known entries.
        for (const key of [...state.query.groups.flat(), ...(state.query.excluded || [])]) {
          const bitmap = bitmaps[key];
          if (bitmap) { workerPostings.delete(key); workerPostings.set(key, bitmap); }
        }
        while (workerPostings.size > ARCHIVE_POSTING_CACHE_LIMIT) workerPostings.delete(workerPostings.keys().next().value!);
      }
      catch (error) { failWorker(currentWorker, error); }
    });
  }
  async function cards(ordinals: number[], caller?: AbortSignal): Promise<ArchiveCard[]> {
    const signal = combined(caller), data = await getManifest(signal), chunks = new Map<number, ArchiveCard[]>();
    await archiveConcurrent([...new Set(ordinals.map(ordinal => Math.floor(ordinal / data.page_size)))], async (index) => {
      const file = data.chunks[index]; if (!file) throw new Error("Missing archive chunk");
      const chunk = object(await resource(file, signal));
      if (chunk.start !== index * data.page_size || !Array.isArray(chunk.cards) || chunk.cards.length !== Math.min(data.page_size, data.total - index * data.page_size)) throw new Error("Invalid card chunk");
      for (const raw of chunk.cards) {
        const card = object(raw);
        if (typeof card.id !== "string" || typeof card.title !== "string" || typeof card.url !== "string" || typeof card.markdown_url !== "string" || typeof card.year !== "string") throw new Error("Invalid card");
        object(card.facets);
      }
      chunks.set(index, chunk.cards as ArchiveCard[]);
    }, signal);
    return ordinals.map(ordinal => { const card = chunks.get(Math.floor(ordinal / data.page_size))?.[ordinal % data.page_size]; if (!card) throw new Error("Missing archive card"); return card; });
  }
  async function lookup(ids: string[], caller?: AbortSignal): Promise<Map<string, ArchiveCard>> {
    const signal = combined(caller), data = await getManifest(signal);
    if (!data.identities) throw new Error("Missing archive identities");
    if (!identities) {
      const value = object(await resource(data.identities, signal));
      if (!Array.isArray(value.ids) || value.ids.length !== data.total || !value.ids.every(id => typeof id === "string")) throw new Error("Invalid archive identities");
      const mapping = new Map((value.ids as string[]).map((id, ordinal) => [id, ordinal]));
      if (mapping.size !== data.total) throw new Error("Duplicate archive identity");
      identities = mapping;
    }
    const known = ids.filter(id => identities!.has(id)), ordinals = known.map(id => identities!.get(id)!);
    const selected = await cards(ordinals, signal);
    if (selected.some((card, index) => card.id !== known[index])) throw new Error("Archive identity differs from card");
    return new Map(selected.map(card => [card.id, card]));
  }
  async function markdown(card: ArchiveCard, caller: AbortSignal, budget = new ArchiveBodyBudget()): Promise<string> {
    const signal = combined(caller), url = archiveUrl(card.markdown_url);
    return limited(async () => {
      const response = await fetch(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]), headers: { Accept: "text/markdown, text/plain" } });
      signal.throwIfAborted();
      const contentType = response.headers.get("content-type")?.split(';')[0]?.trim().toLowerCase();
      if (!response.ok || new URL(response.url || url.href).origin !== location.origin || (contentType && !['text/markdown', 'text/plain', 'application/octet-stream'].includes(contentType))) throw new Error("Markdown load failed");
      const reader = response.body?.getReader();
      if (!reader) return '';
      const decoder = new TextDecoder(), parts: string[] = []; let reserved = 0;
      try {
        while (true) {
          const { done, value } = await reader.read(); signal.throwIfAborted();
          if (done) break;
          budget.reserve(value.byteLength); reserved += value.byteLength;
          parts.push(decoder.decode(value, { stream: true }));
        }
        parts.push(decoder.decode());
        const body = parts.join('');
        // Generic static hosts may omit a MIME type. Reject document-shaped
        // fallback pages while preserving normal Markdown with inline HTML.
        const opening = body.replace(/^(?:\s|<!--[\s\S]*?-->)+/, '');
        if (/^(?:<!doctype\s+html\b|<html\b|<head\b|<body\b|<\?xml\b|<Error\b)/i.test(opening)) throw new Error("Markdown load failed");
        return body;
      } catch (error) { budget.release(reserved); throw error; }
      finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
    }, signal);
  }
  async function article(value: string, caller: AbortSignal, revalidate = false): Promise<{ html: string; url: string }> {
    const signal = combined(caller), url = archiveUrl(value);
    return limited(async () => {
      const response = await fetch(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]), headers: { Accept: "text/html" }, cache: revalidate ? "no-cache" : "default" });
      signal.throwIfAborted();
      const finalUrl = archiveUrl(response.url || url.href).href;
      if (!response.ok || !response.headers.get("content-type")?.includes("text/html")) throw new Error("Article load failed");
      const html = await response.text(); signal.throwIfAborted(); return { html, url: finalUrl };
    }, signal);
  }
  return { manifest: getManifest, revalidate, revalidateCurrent, select, cards, lookup, markdown, article, dispose() { lifetime.abort(); worker?.terminate(); worker = undefined; cache.clear(); postings.clear(); workerPostings.clear(); workerGeneration = undefined; identities = undefined; } };
}
export type ArchiveClient = ReturnType<typeof createArchiveClient>;
