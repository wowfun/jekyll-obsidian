import type { ArchiveCard, ArchiveManifest } from "./archive-query";
import { archiveUrl } from "./archive-client";

export const FAVORITES_CHANGE = "website:favorites-change";
export interface Favorite { id: string; saved_at: string; snapshots: Record<string, ArchiveCard> }
export function favoritesKey(): string {
  const scope = document.querySelector<HTMLMetaElement>('meta[name="website:favorites-scope"]')?.content;
  if (scope === undefined) throw new Error("Missing favorites scope");
  return `website:favorites:v1:${scope || "/"}`;
}
export function favoriteCard(value: unknown): ArchiveCard {
  if (!value || typeof value !== "object") throw new Error("Invalid favorite");
  const card = value as ArchiveCard;
  if (typeof card.id !== "string" || !card.id || typeof card.title !== "string" || typeof card.url !== "string" || typeof card.markdown_url !== "string" || !card.facets || typeof card.facets !== "object") throw new Error("Invalid favorite");
  archiveUrl(card.url); archiveUrl(card.markdown_url);
  if (card.source_url) archiveUrl(card.source_url, true);
  for (const ids of Object.values(card.facets)) if (!Array.isArray(ids) || !ids.every(id => typeof id === "string")) throw new Error("Invalid favorite facets");
  if (card.display_date !== null && (typeof card.display_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(card.display_date))) throw new Error("Invalid favorite date");
  if (card.published_at !== null && (typeof card.published_at !== "string" || !Number.isFinite(Date.parse(card.published_at)))) throw new Error("Invalid favorite date");
  if (card.summary != null && typeof card.summary !== "string") throw new Error("Invalid favorite summary");
  if (card.favorite_labels && (!Object.values(card.favorite_labels).every(label => typeof label === "string"))) throw new Error("Invalid favorite labels");
  return { id: card.id, title: card.title, url: card.url, markdown_url: card.markdown_url,
    published_at: card.published_at, display_date: card.display_date, year: card.display_date?.slice(0, 4) || "Undated",
    month: card.display_date?.slice(0, 7) || null, facets: structuredClone(card.facets), summary: card.summary ?? null,
    source_url: card.source_url ?? null, date_basis: card.date_basis ?? null, favorite_labels: { ...card.favorite_labels } };
}
export function readFavorites(): Map<string, Favorite> {
  const raw = localStorage.getItem(favoritesKey());
  if (!raw) return new Map();
  const data = JSON.parse(raw) as { version: number; entries: unknown[] };
  if (data.version !== 1 || !Array.isArray(data.entries)) throw new Error("Invalid favorites storage");
  const result = new Map<string, Favorite>();
  for (const value of data.entries) {
    const entry = value as Favorite;
    if (!entry || typeof entry.id !== "string" || typeof entry.saved_at !== "string" || !Number.isFinite(Date.parse(entry.saved_at)) || !entry.snapshots || typeof entry.snapshots !== "object") throw new Error("Invalid favorite entry");
    const snapshots: Record<string, ArchiveCard> = Object.create(null);
    for (const [locale, card] of Object.entries(entry.snapshots)) {
      if (!/^[a-z0-9-]+$/i.test(locale) || card.id !== entry.id) throw new Error("Invalid favorite snapshot");
      snapshots[locale] = favoriteCard(card);
    }
    if (!Object.keys(snapshots).length || result.has(entry.id)) throw new Error("Invalid favorite identity");
    result.set(entry.id, { id: entry.id, saved_at: entry.saved_at, snapshots });
  }
  return result;
}
function persist(entries: Map<string, Favorite>): void {
  localStorage.setItem(favoritesKey(), JSON.stringify({ version: 1, entries: [...entries.values()] }));
}
export function snapshotCard(card: ArchiveCard, manifest?: ArchiveManifest): ArchiveCard {
  const snapshot = favoriteCard(card);
  if (manifest) snapshot.favorite_labels = Object.fromEntries(Object.entries(card.facets).flatMap(([name, ids]) => ids.map(id => [name + "/" + id, manifest.labels[manifest.prefixes[name]! + id] || id])));
  return snapshot;
}
export function toggleFavorite(card: ArchiveCard, locale = document.documentElement.lang || "en"): void {
  const entries = readFavorites();
  if (entries.has(card.id)) entries.delete(card.id);
  else entries.set(card.id, { id: card.id, saved_at: new Date().toISOString(), snapshots: { [locale]: favoriteCard(card) } });
  persist(entries);
  window.dispatchEvent(new Event(FAVORITES_CHANGE));
}
export function updateFavoriteSnapshots(cards: ArchiveCard[], locale = document.documentElement.lang || "en"): void {
  const entries = readFavorites(); let changed = false;
  for (const card of cards) {
    const entry = entries.get(card.id); if (!entry) continue;
    const snapshot = favoriteCard(card);
    if (JSON.stringify(entry.snapshots[locale]) !== JSON.stringify(snapshot)) { entry.snapshots[locale] = snapshot; changed = true; }
  }
  if (changed) persist(entries);
}
