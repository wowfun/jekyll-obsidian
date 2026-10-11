export interface ArchiveOption { id: string; name: string; count: number; posting: string }
export interface ArchiveManifest {
  version: number; generation: string; total: number; page_size: number;
  facets: Record<string, ArchiveOption[]>; prefixes: Record<string, string>;
  labels: Record<string, string>; aliases: Record<string, string>;
  years: Record<string, [number, number]>; months: Record<string, [number, number]>; chunks: string[];
}
export interface ArchiveCard {
  id: string; title: string; url: string; source_url?: string | null;
  published_at: string | null; display_date: string | null; year: string; month: string | null;
  facets: Record<string, string[]>; date_basis?: string | null;
}
export interface ArchiveQuery { groups: string[][]; range: [number, number]; page: number }

export function matchArchive(total: number, size: number, query: ArchiveQuery, bitmaps: Record<string, Uint8Array>): { ordinals: number[]; count: number; page: number; pages: number } {
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
  for (let i = start; i < end; i++) if (matches(i)) count++;
  const pages = Math.max(1, Math.ceil(count / size));
  const page = Math.min(pages, Math.max(1, query.page));
  const ordinals: number[] = [];
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
  const month = input.get("month"), year = input.get("year");
  if (month) { parameters.set("month", month); range = Object.hasOwn(manifest.months, month) ? manifest.months[month]! : [0, 0]; }
  else if (year) { parameters.set("year", year); range = Object.hasOwn(manifest.years, year) ? manifest.years[year]! : [0, 0]; }
  const rawPage = input.get("page") || "1";
  const page = /^\d+$/.test(rawPage) && Number.isSafeInteger(Number(rawPage)) ? Math.max(1, Number(rawPage)) : 1;
  if (page > 1) parameters.set("page", String(page));
  return { parameters, query: { groups, range, page }, keys };
}
