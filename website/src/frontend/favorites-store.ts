import type { ArchiveCard, ArchiveManifest } from "./archive-query";
import { archiveUrl } from "./archive-client";

export const FAVORITES_CHANGE = "website:favorites-change";
export interface Favorite { id: string; saved_at: string; snapshots: Record<string, ArchiveCard> }
let cached: { key: string; raw: string | null; entries: Map<string, Favorite>; damaged: boolean } | undefined;
export class FavoritesStorageError extends Error {
  constructor(public code: "damaged" | "unreadable" | "unsupported") { super(code); }
}
export function favoritesKey(): string {
  const scope = document.querySelector<HTMLMetaElement>('meta[name="website:favorites-scope"]')?.content;
  if (scope === undefined) throw new Error("Missing favorites scope");
  return `website:favorites:v1:${scope || "/"}`;
}
export function favoriteCard(value: unknown): ArchiveCard {
  if (!value || typeof value !== "object") throw new Error("Invalid favorite");
  const card = value as ArchiveCard;
  if (typeof card.id !== "string" || !card.id || typeof card.title !== "string" || typeof card.url !== "string" || typeof card.markdown_url !== "string" || !card.facets || typeof card.facets !== "object" || Array.isArray(card.facets)) throw new Error("Invalid favorite");
  archiveUrl(card.url); archiveUrl(card.markdown_url);
  if (card.source_url) archiveUrl(card.source_url, true);
  for (const ids of Object.values(card.facets)) if (!Array.isArray(ids) || !ids.every(id => typeof id === "string")) throw new Error("Invalid favorite facets");
  if (card.display_date !== null && (typeof card.display_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(card.display_date))) throw new Error("Invalid favorite date");
  if (card.display_date !== null) {
    const day = new Date(card.display_date + "T00:00:00Z");
    if (!Number.isFinite(day.getTime()) || day.toISOString().slice(0, 10) !== card.display_date) throw new Error("Invalid favorite date");
  }
  if (card.published_at !== null && (typeof card.published_at !== "string" || !Number.isFinite(Date.parse(card.published_at)))) throw new Error("Invalid favorite date");
  if (card.summary != null && typeof card.summary !== "string") throw new Error("Invalid favorite summary");
  if (card.favorite_labels && (!Object.values(card.favorite_labels).every(label => typeof label === "string"))) throw new Error("Invalid favorite labels");
  return { id: card.id, title: card.title, url: card.url, markdown_url: card.markdown_url,
    published_at: card.published_at, display_date: card.display_date, year: card.display_date?.slice(0, 4) || "Undated",
    month: card.display_date?.slice(0, 7) || null, facets: structuredClone(card.facets), summary: card.summary ?? null,
    source_url: card.source_url ?? null, date_basis: card.date_basis ?? null, favorite_labels: { ...card.favorite_labels } };
}
export function readFavorites(): Map<string, Favorite> {
  const key = favoritesKey(), raw = localStorage.getItem(key);
  if (cached?.key === key && cached.raw === raw) return new Map(cached.entries);
  const result = new Map<string, Favorite>();
  if (!raw) { cached = { key, raw, entries: result, damaged: false }; return result; }
  let data: { version: number; entries: unknown[] };
  try { data = JSON.parse(raw); if (data?.version !== 1 || !Array.isArray(data.entries)) throw new Error(); }
  catch { throw new FavoritesStorageError("unreadable"); }
  let damaged = false;
  for (const value of data.entries) {
    try {
      const entry = value as Favorite;
      if (!entry || typeof entry.id !== "string" || typeof entry.saved_at !== "string" || !Number.isFinite(Date.parse(entry.saved_at)) || !entry.snapshots || typeof entry.snapshots !== "object") throw new Error("Invalid favorite entry");
      const snapshots: Record<string, ArchiveCard> = Object.create(null);
      for (const [locale, card] of Object.entries(entry.snapshots)) {
        try {
          const snapshot = favoriteCard(card);
          if (!/^[a-z0-9-]+$/i.test(locale) || snapshot.id !== entry.id) throw new Error("Invalid favorite snapshot");
          snapshots[locale] = snapshot;
        } catch { damaged = true; }
      }
      if (!Object.keys(snapshots).length || result.has(entry.id)) throw new Error("Invalid favorite identity");
      result.set(entry.id, { id: entry.id, saved_at: entry.saved_at, snapshots });
    } catch { damaged = true; }
  }
  cached = { key, raw, entries: result, damaged };
  return result;
}
export function favoritesRevision(): string | null { return localStorage.getItem(favoritesKey()); }
export function favoritesDamaged(): boolean { return cached?.key === favoritesKey() && cached.damaged || false; }
function persist(entries: Map<string, Favorite>): void {
  const key = favoritesKey(), raw = JSON.stringify({ version: 1, entries: [...entries.values()] });
  // Keep the exact damaged payload before replacing it. If either write fails,
  // the original collection remains intact and no success event is emitted.
  if (cached?.key === key && cached.damaged && cached.raw) localStorage.setItem(`${key}:recovery:${crypto.randomUUID()}`, cached.raw);
  localStorage.setItem(key, raw);
  cached = { key, raw, entries, damaged: false };
}
async function writeFavorites(operation: (entries: Map<string, Favorite>) => boolean): Promise<void> {
  if (!navigator.locks) throw new FavoritesStorageError("unsupported");
  await navigator.locks.request(favoritesKey(), () => {
    const entries = readFavorites();
    if (operation(entries)) persist(entries);
  });
}
export function snapshotCard(card: ArchiveCard, manifest?: ArchiveManifest): ArchiveCard {
  const snapshot = favoriteCard(card);
  if (manifest) snapshot.favorite_labels = Object.fromEntries(Object.entries(card.facets).flatMap(([name, ids]) => ids.map(id => [name + "/" + id, manifest.labels[(Object.hasOwn(manifest.prefixes, name) ? manifest.prefixes[name]! : name + "/") + id] || id])));
  return snapshot;
}
export async function toggleFavorite(card: ArchiveCard, locale = document.documentElement.lang || "en", selected = !readFavorites().has(card.id)): Promise<void> {
  const snapshot = favoriteCard(card);
  await writeFavorites(entries => {
    if (!selected) entries.delete(card.id);
    else {
      const entry = entries.get(card.id);
      entries.set(card.id, { id: card.id, saved_at: entry?.saved_at || new Date().toISOString(), snapshots: { ...entry?.snapshots, [locale]: snapshot } });
    }
    return true;
  });
  window.dispatchEvent(new Event(FAVORITES_CHANGE));
}
export async function updateFavoriteSnapshots(cards: ArchiveCard[], locale = document.documentElement.lang || "en"): Promise<void> {
  if (!cards.length) return;
  await writeFavorites(entries => {
    let changed = false;
    for (const card of cards) {
      const entry = entries.get(card.id); if (!entry) continue;
      const snapshot = favoriteCard(card);
      if (JSON.stringify(entry.snapshots[locale]) !== JSON.stringify(snapshot)) { entries.set(card.id, { ...entry, snapshots: { ...entry.snapshots, [locale]: snapshot } }); changed = true; }
    }
    return changed;
  });
}
