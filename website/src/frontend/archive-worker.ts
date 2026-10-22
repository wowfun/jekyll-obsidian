import { ARCHIVE_POSTING_CACHE_LIMIT, matchArchive, type ArchiveQuery, type ArchiveQueryMode } from "./archive-query";

export interface ArchiveWorkerRequest { id: number; generation: string; total: number; size: number; query: ArchiveQuery; bitmaps: Record<string, Uint8Array>; mode: ArchiveQueryMode; limit?: number | undefined }
const postings = new Map<string, Uint8Array>();
let generation: string | undefined;
globalThis.addEventListener("message", (event: MessageEvent<ArchiveWorkerRequest>) => {
  const { id, generation: current, total, size, query, bitmaps: updates, mode, limit } = event.data;
  if (generation !== current) { postings.clear(); generation = current; }
  for (const [key, bitmap] of Object.entries(updates)) postings.set(key, bitmap);
  const bitmaps: Record<string, Uint8Array> = Object.create(null);
  for (const key of [...query.groups.flat(), ...(query.excluded || [])]) {
    const bitmap = postings.get(key);
    if (bitmap) { bitmaps[key] = bitmap; postings.delete(key); postings.set(key, bitmap); }
  }
  // Current queries can select more than the retained cache budget. Keep their
  // local references until matching finishes, then retain at most 20 postings.
  while (postings.size > ARCHIVE_POSTING_CACHE_LIMIT) postings.delete(postings.keys().next().value!);
  globalThis.postMessage({ id, ...matchArchive(total, size, query, bitmaps, mode, limit) });
});
