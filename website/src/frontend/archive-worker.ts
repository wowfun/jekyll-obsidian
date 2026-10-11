import { matchArchive, type ArchiveQuery } from "./archive-query";

interface Request { id: number; total: number; size: number; query: ArchiveQuery; bitmaps: Record<string, Uint8Array> }
globalThis.addEventListener("message", (event: MessageEvent<Request>) => {
  const { id, total, size, query, bitmaps } = event.data;
  globalThis.postMessage({ id, ...matchArchive(total, size, query, bitmaps) });
});
