import { archiveState, decodeBitmap, type ArchiveCard, type ArchiveManifest, type ArchiveMatches, type ArchiveQueryMode } from "./archive-query";
import { requireSiteUrl } from "./urls";

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

// One client owns a generation, its worker and a four-request budget shared by
// pagination and export. Callers own cancellation; only completed data is cached.
export function createArchiveClient(source: string) {
  const manifestUrl = archiveUrl(source), lifetime = new AbortController();
  const worker = new Worker(requireSiteUrl("archive-worker"), { type: "module" });
  const cache = new Map<string, unknown>();
  let manifest: ArchiveManifest | undefined, queryId = 0, active = 0;
  const queue: { start: () => void; cancel: () => void }[] = [];
  const pending = new Map<number, { resolve: (result: ArchiveMatches) => void; reject: (error: unknown) => void }>();
  worker.onmessage = (event: MessageEvent<ArchiveMatches & { id: number }>) => pending.get(event.data.id)?.resolve(event.data);
  worker.onerror = () => { for (const job of pending.values()) job.reject(new Error("Archive worker failed")); };
  function combined(signal?: AbortSignal): AbortSignal { return signal ? AbortSignal.any([lifetime.signal, signal]) : lifetime.signal; }
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
  async function resource(filename: string, signal: AbortSignal): Promise<unknown> {
    signal.throwIfAborted();
    if (cache.has(filename)) { const value = cache.get(filename); cache.delete(filename); cache.set(filename, value); return value; }
    const url = new URL(filename, manifestUrl);
    if (url.origin !== manifestUrl.origin || !url.pathname.startsWith(manifestUrl.pathname.slice(0, manifestUrl.pathname.lastIndexOf("/") + 1))) throw new Error("Invalid archive resource path");
    return limited(async () => {
      if (cache.has(filename)) return cache.get(filename);
      const response = await fetch(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]) });
      if (!response.ok || new URL(response.url || url.href).origin !== manifestUrl.origin) throw new Error("Archive load failed");
      const value: unknown = await response.json();
      signal.throwIfAborted();
      if (filename !== "manifest.json") {
        if (object(value).generation !== manifest?.generation) throw new Error("Archive generation differs");
        cache.set(filename, value);
        while (cache.size > 20) cache.delete(cache.keys().next().value!);
      }
      return value;
    }, signal);
  }
  async function getManifest(caller?: AbortSignal): Promise<ArchiveManifest> {
    const signal = combined(caller); signal.throwIfAborted();
    if (manifest) return manifest;
    const data = object(await resource("manifest.json", signal));
    if (data.version !== 1 || !Number.isSafeInteger(data.total) || Number(data.total) < 0 || !Number.isSafeInteger(data.page_size) || Number(data.page_size) < 1 || Number(data.page_size) > 100 || !Number.isSafeInteger(data.export_max_days) || Number(data.export_max_days) < 1 || typeof data.generation !== "string" || !/^[a-f0-9]{64}$/.test(data.generation) || !Array.isArray(data.chunks)) throw new Error("Invalid archive manifest");
    for (const key of ["facets", "prefixes", "labels", "aliases", "years", "months", "days"]) object(data[key]);
    for (const [name, prefix] of Object.entries(object(data.prefixes))) {
      if (!/^[a-z][a-z0-9_-]*$/.test(name) || typeof prefix !== "string" || !Array.isArray(object(data.facets)[name])) throw new Error("Invalid archive facet");
      for (const entry of object(data.facets)[name] as unknown[]) { const option = object(entry); if (typeof option.id !== "string" || typeof option.name !== "string" || typeof option.posting !== "string") throw new Error("Invalid archive option"); }
    }
    if (data.chunks.length !== Math.ceil(Number(data.total) / Number(data.page_size))) throw new Error("Invalid archive chunk count");
    for (const mapping of [data.years, data.months, data.days]) for (const range of Object.values(object(mapping))) {
      if (!Array.isArray(range) || range.length !== 2 || !range.every(Number.isSafeInteger) || range[0] < 0 || range[1] > Number(data.total) || range[0] > range[1]) throw new Error("Invalid chronology bounds");
    }
    manifest = data as unknown as ArchiveManifest; return manifest;
  }
  async function select(state: ReturnType<typeof archiveState>, mode: ArchiveQueryMode, caller?: AbortSignal): Promise<ArchiveMatches> {
    const signal = combined(caller), data = await getManifest(signal);
    const bitmaps: Record<string, Uint8Array> = Object.create(null) as Record<string, Uint8Array>;
    await archiveConcurrent(state.keys, async (key) => {
      const split = key.indexOf("/"), name = key.slice(0, split), id = key.slice(split + 1);
      const option = data.facets[name]?.find(entry => entry.id === id);
      if (!option) return;
      const posting = object(await resource(option.posting, signal));
      if (posting.total !== data.total || typeof posting.bitmap !== "string") throw new Error("Invalid posting");
      bitmaps[key] = decodeBitmap(posting.bitmap, data.total);
    }, signal);
    signal.throwIfAborted();
    const id = ++queryId;
    return new Promise((resolve, reject) => {
      const finish = () => { clearTimeout(timeout); pending.delete(id); signal.removeEventListener("abort", abort); };
      const abort = () => { finish(); reject(signal.reason); };
      const timeout = setTimeout(() => { finish(); reject(new Error("Archive query timed out")); }, 15000);
      pending.set(id, { resolve(value) { finish(); resolve(value); }, reject(error) { finish(); reject(error); } });
      signal.addEventListener("abort", abort, { once: true });
      worker.postMessage({ id, total: data.total, size: data.page_size, query: state.query, bitmaps, mode });
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
  async function markdown(card: ArchiveCard, caller: AbortSignal): Promise<string> {
    const signal = combined(caller), url = archiveUrl(card.markdown_url);
    return limited(async () => {
      const response = await fetch(url, { signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]), headers: { Accept: "text/markdown, text/plain" } });
      if (!response.ok || new URL(response.url || url.href).origin !== location.origin || !/^text\/(markdown|plain)(?:;|$)/i.test(response.headers.get("content-type") || "")) throw new Error("Markdown load failed");
      const body = await response.text(); signal.throwIfAborted(); return body;
    }, signal);
  }
  return { manifest: getManifest, select, cards, markdown, dispose() { lifetime.abort(); worker.terminate(); cache.clear(); } };
}
export type ArchiveClient = ReturnType<typeof createArchiveClient>;
