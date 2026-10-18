export interface ArchiveFacetOption { id: string; name: string; count: number }
export interface ArchiveCollection {
  total: number; page_size: number;
  facets: Record<string, ArchiveFacetOption[]>; prefixes: Record<string, string>;
  labels: Record<string, string>; aliases: Record<string, string>;
  years: Record<string, [number, number]>; months: Record<string, [number, number]>; days: Record<string, [number, number]>;
  ledger_group_by?: "year" | "day";
}
export interface ArchiveOption extends ArchiveFacetOption { posting?: string }
export interface ArchiveManifest extends ArchiveCollection {
  version: number; generation: string; export_max_days: number;
  facets: Record<string, ArchiveOption[]>; chunks: string[]; identities?: string;
}
export interface ArchiveCard {
  id: string; title: string; url: string; markdown_url: string; summary?: string | null; source_url?: string | null;
  published_at: string | null; display_date: string | null; year: string; month: string | null;
  facets: Record<string, string[]>; date_basis?: string | null;
  favorite_labels?: Record<string, string>; unavailable?: boolean; snapshot_locale?: string;
}
export interface ArchiveQuery { groups: string[][]; range: [number, number]; page: number }
export type ArchiveQueryMode = "page" | "all" | "first";
export interface ArchiveMatches { ordinals: number[]; count: number; page: number; pages: number }
export const ARCHIVE_POSTING_CACHE_LIMIT = 20;

export function archivePageNumber(value: string): number | undefined {
  const page = /^\d+$/.test(value) ? Number(value) : NaN;
  return Number.isSafeInteger(page) && page > 0 ? page : undefined;
}
export function canonicalFacetId(id: string, prefix: string, aliases: Record<string, string>): string {
  const key = prefix + id, alias = Object.hasOwn(aliases, key) ? aliases[key] : undefined;
  return alias?.startsWith(prefix) ? alias.slice(prefix.length) : id;
}

export function matchArchive(total: number, size: number, query: ArchiveQuery, bitmaps: Record<string, Uint8Array>, mode: ArchiveQueryMode = "page", limit = Infinity): ArchiveMatches {
  const union = query.groups.map((keys) => {
    if (!keys.length) return null;
    let result: Uint8Array | undefined, shared = true;
    for (const key of keys) {
      const bitmap = Object.hasOwn(bitmaps, key) ? bitmaps[key] : undefined;
      if (!bitmap) continue;
      if (!result) result = bitmap;
      else {
        if (shared) { result = result.slice(); shared = false; }
        for (let i = 0; i < result.length; i++) result[i] = result[i]! | bitmap[i]!;
      }
    }
    return result || new Uint8Array(0);
  });
  let count = 0;
  const matches = (ordinal: number) => union.every((bitmap) => !bitmap || Boolean(bitmap[ordinal >> 3]! & (1 << (ordinal & 7))));
  const [start, end] = query.range;
  const ordinals: number[] = [];
  const requestedPage = Math.max(1, query.page), offset = (requestedPage - 1) * size;
  const lastPage = mode === "page" && requestedPage > 1 ? new Array<number>(size) : undefined;
  for (let i = start; i < end; i++) if (matches(i)) {
    if (mode === "first") return { ordinals: [i], count: 1, page: 1, pages: 1 };
    if ((mode === "all" && ordinals.length < limit) || (mode === "page" && count >= offset && ordinals.length < size)) ordinals.push(i);
    if (lastPage) lastPage[count % size] = i;
    count++;
  }
  if (mode !== "page") return { ordinals, count, page: 1, pages: 1 };
  const pages = Math.max(1, Math.ceil(count / size));
  const page = Math.min(pages, requestedPage);
  // Exact counts and the requested window come from the same scan. A bounded
  // ring keeps the final page available when an excessive page must be clamped.
  return { ordinals: requestedPage > pages ? lastPage!.slice(0, count - (pages - 1) * size) : ordinals, count, page, pages };
}

export function decodeBitmap(encoded: string, total: number): Uint8Array {
  const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
  if (bytes.length !== Math.ceil(total / 8)) throw new Error("Invalid archive bitmap length");
  return bytes;
}

export function archiveState(manifest: ArchiveCollection, search: string): { parameters: URLSearchParams; query: ArchiveQuery; keys: string[] } {
  const input = new URLSearchParams(search), parameters = new URLSearchParams();
  const groups: string[][] = [], keys: string[] = [];
  for (const [name, prefix] of Object.entries(manifest.prefixes)) {
    const ids = [...new Set(input.getAll(name).filter(Boolean).map(id => canonicalFacetId(id, prefix, manifest.aliases)))].sort();
    groups.push(ids.map((id) => `${name}/${id}`));
    for (const id of ids) { parameters.append(name, id); keys.push(`${name}/${id}`); }
  }
  let range: [number, number] = [0, manifest.total];
  const day = input.get("day"), month = input.get("month"), year = input.get("year");
  if (day) { parameters.set("day", day); range = Object.hasOwn(manifest.days, day) ? manifest.days[day]! : [0, 0]; }
  else if (month) { parameters.set("month", month); range = Object.hasOwn(manifest.months, month) ? manifest.months[month]! : [0, 0]; }
  else if (year) { parameters.set("year", year); range = Object.hasOwn(manifest.years, year) ? manifest.years[year]! : [0, 0]; }
  const page = archivePageNumber(input.get("page") || "1") || 1;
  if (page > 1) parameters.set("page", String(page));
  return { parameters, query: { groups, range, page }, keys };
}
