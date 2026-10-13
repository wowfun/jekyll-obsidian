export interface ArchiveOption { id: string; name: string; count: number; posting: string }
export interface ArchiveManifest {
  version: number; generation: string; total: number; page_size: number; export_max_days: number;
  facets: Record<string, ArchiveOption[]>; prefixes: Record<string, string>;
  labels: Record<string, string>; aliases: Record<string, string>;
  years: Record<string, [number, number]>; months: Record<string, [number, number]>; days: Record<string, [number, number]>; chunks: string[];
  identities?: string; ledger_group_by?: "year" | "day";
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

export function matchArchive(total: number, size: number, query: ArchiveQuery, bitmaps: Record<string, Uint8Array>, mode: ArchiveQueryMode = "page", limit = Infinity): ArchiveMatches {
  const union = query.groups.map((keys) => {
    if (!keys.length) return null;
    const result = new Uint8Array(Math.ceil(total / 8));
    for (const key of keys) {
      const bitmap = Object.hasOwn(bitmaps, key) ? bitmaps[key] : undefined;
      if (bitmap) for (let i = 0; i < result.length; i++) result[i] = result[i]! | bitmap[i]!;
    }
    return result;
  });
  let count = 0;
  const matches = (ordinal: number) => union.every((bitmap) => !bitmap || Boolean(bitmap[ordinal >> 3]! & (1 << (ordinal & 7))));
  const [start, end] = query.range;
  const ordinals: number[] = [];
  for (let i = start; i < end; i++) if (matches(i)) {
    if (mode === "first") return { ordinals: [i], count: 1, page: 1, pages: 1 };
    count++; if (mode === "all" && ordinals.length < limit) ordinals.push(i);
  }
  if (mode !== "page") return { ordinals, count, page: 1, pages: 1 };
  const pages = Math.max(1, Math.ceil(count / size));
  const page = Math.min(pages, Math.max(1, query.page));
  let seen = 0;
  for (let i = start; i < end && ordinals.length < size; i++) if (matches(i)) {
    if (seen++ >= (page - 1) * size) ordinals.push(i);
  }
  return { ordinals, count, page, pages };
}

export function decodeBitmap(encoded: string, total: number): Uint8Array {
  const bytes = Uint8Array.from(atob(encoded), (char) => char.charCodeAt(0));
  if (bytes.length !== Math.ceil(total / 8)) throw new Error("Invalid archive bitmap length");
  return bytes;
}

export function archiveState(manifest: ArchiveManifest, search: string): { parameters: URLSearchParams; query: ArchiveQuery; keys: string[] } {
  const input = new URLSearchParams(search), parameters = new URLSearchParams();
  const groups: string[][] = [], keys: string[] = [];
  for (const [name, prefix] of Object.entries(manifest.prefixes)) {
    const ids = [...new Set(input.getAll(name).filter(Boolean).map((id) => {
      const tag = manifest.aliases[prefix + id];
      return tag?.startsWith(prefix) ? tag.slice(prefix.length) : id;
    }))].sort();
    groups.push(ids.map((id) => `${name}/${id}`));
    for (const id of ids) { parameters.append(name, id); keys.push(`${name}/${id}`); }
  }
  let range: [number, number] = [0, manifest.total];
  const day = input.get("day"), month = input.get("month"), year = input.get("year");
  if (day) { parameters.set("day", day); range = Object.hasOwn(manifest.days, day) ? manifest.days[day]! : [0, 0]; }
  else if (month) { parameters.set("month", month); range = Object.hasOwn(manifest.months, month) ? manifest.months[month]! : [0, 0]; }
  else if (year) { parameters.set("year", year); range = Object.hasOwn(manifest.years, year) ? manifest.years[year]! : [0, 0]; }
  const rawPage = input.get("page") || "1";
  const page = /^\d+$/.test(rawPage) && Number.isSafeInteger(Number(rawPage)) ? Math.max(1, Number(rawPage)) : 1;
  if (page > 1) parameters.set("page", String(page));
  return { parameters, query: { groups, range, page }, keys };
}
