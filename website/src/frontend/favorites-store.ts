import type { ArchiveCard, ArchiveCollection } from "./archive-query";
import { archiveUrl } from "./archive-client";
import { favoriteLabels } from "./archive-facets";

export const FAVORITES_CHANGE = "website:favorites-change";
export const FAVORITES_RECOVERY_CHANGE = "website:favorites-recovery-change";
export interface Favorite { id: string; saved_at: string; snapshots: Record<string, ArchiveCard> }
export interface FavoriteCollection { entries: ReadonlyMap<string, Favorite>; revision: string | null }
let cached: { key: string; raw: string | null; entries: ReadonlyMap<string, Favorite>; damaged: boolean } | undefined;
export class FavoritesStorageError extends Error {
  constructor(public code: "damaged" | "unreadable" | "unsupported" | "recovery_required") { super(code); }
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
export function readFavoriteCollection(): FavoriteCollection {
  const key = favoritesKey(), raw = localStorage.getItem(key);
  if (cached?.key !== key || cached.raw !== raw) {
    const decoded = decodeFavorites(raw);
    cached = { key, raw, entries: immutableFavorites(decoded.entries), damaged: decoded.damaged };
  }
  return { entries: cached.entries, revision: raw };
}
export function readFavorites(): Map<string, Favorite> { return new Map(readFavoriteCollection().entries); }
function immutableFavorites(entries: Map<string, Favorite>): ReadonlyMap<string, Favorite> {
  for (const entry of entries.values()) {
    if (Object.isFrozen(entry)) continue;
    for (const card of Object.values(entry.snapshots)) {
      for (const ids of Object.values(card.facets)) Object.freeze(ids);
      Object.freeze(card.facets); Object.freeze(card.favorite_labels); Object.freeze(card);
    }
    Object.freeze(entry.snapshots); Object.freeze(entry);
  }
  // Freezing a Map does not disable set/delete/clear. Expose only its read API,
  // including the map supplied to forEach, while preserving snapshot identities.
  const view: ReadonlyMap<string, Favorite> = {
    get size() { return entries.size; },
    get: entries.get.bind(entries), has: entries.has.bind(entries),
    keys: entries.keys.bind(entries), values: entries.values.bind(entries),
    entries: entries.entries.bind(entries), [Symbol.iterator]: entries[Symbol.iterator].bind(entries),
    forEach(callback, thisArg) { entries.forEach((entry, key) => callback.call(thisArg, entry, key, view)); }
  };
  return Object.freeze(view);
}
function decodeFavorites(raw: string | null): { entries: Map<string, Favorite>; damaged: boolean } {
  const result = new Map<string, Favorite>();
  if (!raw) return { entries: result, damaged: false };
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
  return { entries: result, damaged };
}
export function favoritesDamaged(): boolean { return cached?.key === favoritesKey() ? cached.damaged : false; }
function persist(entries: Map<string, Favorite>): void {
  const key = favoritesKey(), raw = JSON.stringify({ version: 1, entries: [...entries.values()] });
  // Keep the exact damaged payload before replacing it. If either write fails,
  // the original collection remains intact and no success event is emitted.
  if (cached?.key === key && cached.damaged && cached.raw) {
    const copies = favoriteRecoveryCopies();
    // A distinct damaged payload needs a separate copy. Keep the earlier
    // original until the reader explicitly clears it instead of evicting data.
    if (copies.some(copy => copy.raw !== cached!.raw)) throw new FavoritesStorageError("recovery_required");
    if (!copies.length) {
      localStorage.setItem(`${key}:recovery:current`, cached.raw);
      window.dispatchEvent(new Event(FAVORITES_RECOVERY_CHANGE));
    }
  }
  localStorage.setItem(key, raw);
  cached = { key, raw, entries: immutableFavorites(entries), damaged: false };
}
export function favoriteRecoveryCopies(): { key: string; raw: string }[] {
  return favoriteRecoveryKeys().sort().flatMap(key => {
    const raw = localStorage.getItem(key); return raw === null ? [] : [{ key, raw }];
  });
}
function favoriteRecoveryKeys(): string[] {
  const prefix = favoritesKey() + ":recovery:", keys: string[] = [];
  for (let index = 0; index < localStorage.length; index++) {
    const key = localStorage.key(index);
    if (key?.startsWith(prefix)) keys.push(key);
  }
  return keys;
}
export function hasFavoriteRecovery(): boolean { return favoriteRecoveryKeys().length > 0; }
export async function clearFavoriteRecovery(): Promise<void> {
  if (!navigator.locks) throw new FavoritesStorageError("unsupported");
  await navigator.locks.request(favoritesKey(), () => {
    for (const key of favoriteRecoveryKeys()) localStorage.removeItem(key);
  });
  window.dispatchEvent(new Event(FAVORITES_RECOVERY_CHANGE));
}
export async function restoreFavoriteRecovery(): Promise<void> {
  await writeFavorites(entries => {
    let changed = false;
    for (const copy of favoriteRecoveryCopies()) {
      let recovered: Map<string, Favorite>;
      try { recovered = decodeFavorites(copy.raw).entries; } catch { continue; }
      for (const [id, saved] of recovered) {
        const current = entries.get(id);
        if (!current) { entries.set(id, saved); changed = true; }
        else {
          const missing = Object.fromEntries(Object.entries(saved.snapshots).filter(([locale]) => !Object.hasOwn(current.snapshots, locale)));
          if (Object.keys(missing).length) { entries.set(id, { ...current, snapshots: { ...missing, ...current.snapshots } }); changed = true; }
        }
      }
    }
    return changed;
  });
  window.dispatchEvent(new Event(FAVORITES_CHANGE));
}
async function writeFavorites(operation: (entries: Map<string, Favorite>) => boolean): Promise<FavoriteCollection> {
  if (!navigator.locks) throw new FavoritesStorageError("unsupported");
  return navigator.locks.request(favoritesKey(), () => {
    const collection = readFavoriteCollection();
    const entries = new Map(collection.entries);
    if (!operation(entries)) return collection;
    persist(entries);
    // Return the state actually read/written under this lock, rather than a
    // later revision that may belong to another tab's yet-unrendered changes.
    return { entries: cached!.entries, revision: cached!.raw };
  });
}
export function snapshotCard(card: ArchiveCard, manifest?: Pick<ArchiveCollection, "labels" | "prefixes">): ArchiveCard {
  const snapshot = favoriteCard(card);
  snapshot.favorite_labels = favoriteLabels(card, manifest);
  return snapshot;
}
export async function toggleFavorite(card: ArchiveCard, locale = document.documentElement.lang || "en", selected?: boolean): Promise<void> {
  const snapshot = favoriteCard(card);
  await writeFavorites(entries => {
    if (!(selected ?? !entries.has(card.id))) return entries.delete(card.id);
    else {
      const entry = entries.get(card.id);
      if (sameFavoriteCard(entry?.snapshots[locale], snapshot)) return false;
      entries.set(card.id, { id: card.id, saved_at: entry?.saved_at || new Date().toISOString(), snapshots: { ...entry?.snapshots, [locale]: snapshot } });
    }
    return true;
  });
  window.dispatchEvent(new Event(FAVORITES_CHANGE));
}
export function sameFavoriteCard(a: ArchiveCard | undefined, b: ArchiveCard | undefined): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  const fields = ["id", "title", "url", "markdown_url", "published_at", "display_date", "year", "month", "summary", "source_url", "date_basis"] as const;
  if (fields.some(key => a[key] !== b[key])) return false;
  const names = Object.keys(a.facets);
  if (names.length !== Object.keys(b.facets).length || names.some(name => !Object.hasOwn(b.facets, name) || a.facets[name]!.length !== b.facets[name]!.length || a.facets[name]!.some((id, i) => id !== b.facets[name]![i]))) return false;
  const left = a.favorite_labels || {}, right = b.favorite_labels || {};
  return Object.keys(left).length === Object.keys(right).length && Object.keys(left).every(key => Object.hasOwn(right, key) && left[key] === right[key]);
}
export async function updateFavoriteSnapshots(cards: ArchiveCard[], locale = document.documentElement.lang || "en", expected?: ReadonlyMap<string, Favorite>): Promise<FavoriteCollection> {
  if (!cards.length) return readFavoriteCollection();
  return writeFavorites(entries => {
    let changed = false;
    for (const card of cards) {
      const entry = entries.get(card.id); if (!entry) continue;
      // Do not overwrite a newer snapshot saved while this lookup was pending.
      if (expected && !sameFavoriteCard(entry.snapshots[locale], expected.get(card.id)?.snapshots[locale])) continue;
      const snapshot = favoriteCard(card);
      if (!sameFavoriteCard(entry.snapshots[locale], snapshot)) { entries.set(card.id, { ...entry, snapshots: { ...entry.snapshots, [locale]: snapshot } }); changed = true; }
    }
    return changed;
  });
}
