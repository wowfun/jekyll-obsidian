import { matchArchive, type ArchiveQuery, type ArchiveQueryMode } from "./archive-query";

interface Request { id: number; total: number; size: number; query: ArchiveQuery; bitmaps: Record<string, Uint8Array>; mode: ArchiveQueryMode; limit?: number }
globalThis.addEventListener("message", (event: MessageEvent<Request>) => {
  const { id, total, size, query, bitmaps, mode, limit } = event.data;
  globalThis.postMessage({ id, ...matchArchive(total, size, query, bitmaps, mode, limit) });
});
