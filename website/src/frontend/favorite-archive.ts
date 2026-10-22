import { archiveState, canonicalFacetId, matchArchive, type ArchiveCard, type ArchiveCollection, type ArchiveMatches } from "./archive-query";
import type { ArchiveClient } from "./archive-client";
import { readFavoriteCollection, sameFavoriteCard, snapshotCard, updateFavoriteSnapshots, type Favorite, type FavoriteCollection } from "./favorites-store";
import { favoritesUI, showFavoriteError } from "./favorite-controls";
import { textElement } from "./archive-ledger";
import { facetLabel, facetPrefix } from "./archive-facets";
import { readArchiveVisibilityUI } from "./archive-visibility";

function offlineHiddenTags(): string[] {
  // This fallback controls filter display while saved entries remain available.
  try {
    const tags: unknown = JSON.parse(readArchiveVisibilityUI().hiddenTags || "[]");
    return Array.isArray(tags) && tags.every(tag => typeof tag === "string" && tag.length > 0) ? tags : [];
  } catch { return []; }
}

export function favoriteManifest(cards: ArchiveCard[], base?: ArchiveCollection): ArchiveCollection {
  const facets: ArchiveCollection["facets"] = Object.create(null);
  const prefixes: Record<string, string> = Object.assign(Object.create(null), base?.prefixes || { source: "source/", topic: "topics/" }), labels = { ...base?.labels };
  const years: ArchiveCollection["years"] = {}, months: ArchiveCollection["months"] = {}, days: ArchiveCollection["days"] = {};
  const optionsByName = new Map<string, Map<string, ArchiveCollection["facets"][string][number]>>();
  for (const name of Object.keys(base?.prefixes || { source: "source/", topic: "topics/" })) facets[name] = [];
  cards.forEach((card, ordinal) => {
    for (const [name, ids] of Object.entries(card.facets)) {
      if (!Object.hasOwn(prefixes, name)) prefixes[name] = facetPrefix(prefixes, name);
      facets[name] ||= [];
      for (const id of ids) {
        const key = prefixes[name]! + id; labels[key] ||= facetLabel(card, name, id, base);
        let options = optionsByName.get(name);
        if (!options) { options = new Map(); optionsByName.set(name, options); }
        let option = options.get(id);
        if (!option) { option = { id, name: labels[key]!, count: 0 }; options.set(id, option); facets[name]!.push(option); }
        option.count++;
      }
    }
    for (const [mapping, key] of [[years, card.year], [months, card.month], [days, card.display_date]] as const) if (key) { mapping[key] ||= [ordinal, ordinal]; mapping[key]![1] = ordinal + 1; }
  });
  for (const options of Object.values(facets)) options.sort((a, b) => b.count - a.count || a.id.localeCompare(b.id));
  return { total: cards.length, page_size: 50,
    hidden_tags: base?.hidden_tags || offlineHiddenTags(),
    facets, prefixes, labels, aliases: base?.aliases || {}, years, months, days, ledger_group_by: "day" };
}
export interface FavoriteArchive { cards: ArchiveCard[]; manifest: ArchiveCollection; refreshFailed: boolean; sourceManifest: ArchiveCollection | undefined; snapshots: Map<string, ArchiveCard>; revision: string | null }
type FavoriteClient = Pick<ArchiveClient, "lookup"> & { manifest(signal?: AbortSignal): Promise<ArchiveCollection> };
function snapshotLocale(entry: Favorite, locale: string): string {
  return Object.hasOwn(entry.snapshots, locale) ? locale : Object.keys(entry.snapshots)[0]!;
}
function selectedSnapshot(entry: Favorite, locale: string): ArchiveCard {
  const language = snapshotLocale(entry, locale);
  return { ...entry.snapshots[language]!, snapshot_locale: language };
}
function normalizeCards(cards: ArchiveCard[], base?: ArchiveCollection): ArchiveCard[] {
  if (base && Object.keys(base.aliases).length) cards = cards.map(card => ({ ...card, facets: Object.fromEntries(Object.entries(card.facets).map(([name, ids]) => [name, [...new Set(ids.map(id => {
    return canonicalFacetId(id, facetPrefix(base.prefixes, name), base.aliases);
  }))]])) }));
  return cards.sort((a, b) => (a.display_date || "") > (b.display_date || "") ? -1 : (a.display_date || "") < (b.display_date || "") ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}
function snapshotReferences(entries: ReadonlyMap<string, Favorite>, locale: string): Map<string, ArchiveCard> {
  return new Map([...entries].map(([id, entry]) => [id, entry.snapshots[snapshotLocale(entry, locale)]!]));
}
function finishArchive(prepared: ArchiveCard[], initial: FavoriteCollection, collection: FavoriteCollection, base: ArchiveCollection | undefined, refreshFailed: boolean, locale: string): FavoriteArchive {
  const known = new Map(prepared.map(card => [card.id, card])), original = snapshotReferences(initial.entries, locale);
  // The locked write may have observed additions, removals, or newer snapshots.
  // Project that exact collection, keeping fresh read-only cards if saving failed.
  const cards = normalizeCards([...collection.entries.values()].map(entry => {
    const prior = known.get(entry.id), snapshot = entry.snapshots[snapshotLocale(entry, locale)]!;
    if (prior && sameFavoriteCard(snapshot, original.get(entry.id))) return prior;
    return { ...selectedSnapshot(entry, locale), unavailable: Boolean(prior?.unavailable) };
  }), base);
  return { cards, manifest: favoriteManifest(cards, base), refreshFailed: refreshFailed && cards.length > 0,
    sourceManifest: base, snapshots: snapshotReferences(collection.entries, locale), revision: collection.revision };
}
async function saveSnapshots(cards: ArchiveCard[], initial: FavoriteCollection, locale: string): Promise<FavoriteCollection> {
  try { return cards.length ? await updateFavoriteSnapshots(cards, locale, initial.entries) : readFavoriteCollection(); }
  catch (error) { showFavoriteError(error); try { return readFavoriteCollection(); } catch { return initial; } }
}
export async function loadFavoriteArchive(client: FavoriteClient, signal: AbortSignal, initial?: FavoriteCollection): Promise<FavoriteArchive> {
  const locale = document.documentElement.lang || "en";
  try { initial ||= readFavoriteCollection(); } catch (error) { showFavoriteError(error); throw error; }
  let collection = initial, cards = [...initial.entries.values()].map(entry => selectedSnapshot(entry, locale));
  let base: ArchiveCollection | undefined, refreshFailed = false;
  try {
    base = await client.manifest(signal);
    const current = cards.length ? await client.lookup(cards.map(card => card.id), signal) : new Map<string, ArchiveCard>();
    signal.throwIfAborted();
    cards = cards.map(saved => current.has(saved.id) ? { ...snapshotCard(current.get(saved.id)!, base), snapshot_locale: locale } : { ...saved, unavailable: true });
    collection = await saveSnapshots(cards.filter(card => !card.unavailable), initial, locale);
  } catch { signal.throwIfAborted(); refreshFailed = true; }
  // A failed request does not prove that an article has been removed.
  return finishArchive(cards, initial, collection, base, refreshFailed, locale);
}
export async function reconcileFavoriteArchive(previous: FavoriteArchive, client: Pick<ArchiveClient, "lookup">, signal: AbortSignal, initial = readFavoriteCollection()): Promise<FavoriteArchive> {
  const locale = document.documentElement.lang || "en", references = snapshotReferences(initial.entries, locale);
  const old = new Map(previous.cards.map(card => [card.id, card])), missing: string[] = [];
  let collection = initial, cards = [...initial.entries.values()].map(entry => {
    const prior = old.get(entry.id);
    if (prior && references.get(entry.id) === previous.snapshots.get(entry.id)) return prior;
    if (!prior) missing.push(entry.id);
    // A previous current-language server card remains useful when its snapshot
    // could not be persisted and the store contains only another language.
    const selected = !Object.hasOwn(entry.snapshots, locale) && prior?.snapshot_locale === locale ? prior : selectedSnapshot(entry, locale);
    return { ...selected, unavailable: Boolean(prior?.unavailable) };
  });
  // Local edits cannot resolve an earlier failed article refresh. Keep its
  // retry hint until a full refresh succeeds or the collection becomes empty.
  let refreshFailed = previous.refreshFailed;
  if (missing.length) {
    try {
      const current = await client.lookup(missing, signal); signal.throwIfAborted();
      const fresh = [...current.values()].map(card => snapshotCard(card, previous.sourceManifest));
      const byId = new Map(fresh.map(card => [card.id, card]));
      cards = cards.map(card => byId.has(card.id) ? { ...byId.get(card.id)!, snapshot_locale: locale } : card);
      collection = await saveSnapshots(fresh, initial, locale);
    } catch { signal.throwIfAborted(); refreshFailed = true; }
  }
  return finishArchive(cards, initial, collection, previous.sourceManifest, refreshFailed, locale);
}
export async function refreshFavoriteArchive(client: FavoriteClient, signal: AbortSignal, previous?: FavoriteArchive): Promise<FavoriteArchive> {
  let collection: FavoriteCollection;
  try { collection = readFavoriteCollection(); } catch (error) { showFavoriteError(error); throw error; }
  if (!previous) return loadFavoriteArchive(client, signal, collection);
  if (previous.revision === collection.revision) return previous;
  return reconcileFavoriteArchive(previous, client, signal, collection);
}
const collectionBitmaps = new WeakMap<ArchiveCard[], Map<string, Uint8Array>>();
export function selectFavorites(cards: ArchiveCard[], manifest: ArchiveCollection, state: ReturnType<typeof archiveState>): ArchiveMatches {
  let cached = collectionBitmaps.get(cards);
  if (!cached) { cached = new Map(); collectionBitmaps.set(cards, cached); }
  const missing = new Set(state.keys.filter(key => !cached.has(key)));
  for (const key of missing) cached.set(key, new Uint8Array(Math.ceil(cards.length / 8)));
  if (missing.size) {
    cards.forEach((card, ordinal) => {
      for (const [name, ids] of Object.entries(card.facets)) for (const id of ids) {
        const key = name + "/" + id; if (missing.has(key)) cached!.get(key)![ordinal >> 3]! |= 1 << (ordinal & 7);
      }
    });
  }
  const bitmaps = Object.fromEntries(state.keys.map(key => [key, cached!.get(key)!]));
  while (cached.size > 20) cached.delete(cached.keys().next().value!);
  return matchArchive(cards.length, manifest.page_size, state.query, bitmaps);
}
export function renderFavoriteFilters(root: HTMLElement, manifest: ArchiveCollection): void {
  const host = root.querySelector<HTMLElement>("[data-favorites-facets]")!;
  // Preserve the localized names supplied by the server before replacing options.
  const names = new Map([["source", root.dataset.sourcesLabel || "Sources"], ["topic", root.dataset.topicsLabel || "Topics"]]);
  host.replaceChildren();
  for (const [name, options] of Object.entries(manifest.facets)) {
    const nav = textElement("nav", "", "tag-filter archive-facet"), heading = textElement("h2", names.get(name) || name, "archive-facet-label"), list = textElement("ul", "", "tag-filter__list"); nav.setAttribute("aria-label", heading.textContent!);
    for (const option of [{ id: "", name: root.dataset.allLabel || "All", count: manifest.total }, ...options]) {
      const button = textElement("button", "", "tag-chip"); button.type = "button"; button.dataset.archiveFacet = name; button.dataset.archiveValue = option.id;
      button.append(document.createTextNode(option.name + " "), textElement("span", String(option.count))); const li = document.createElement("li"); li.append(button); list.append(li);
    }
    const headingHost = textElement("div", "", "archive-facet-heading"); headingHost.append(heading);
    nav.append(headingHost, list); host.append(nav);
  }
  for (const nav of document.querySelectorAll<HTMLElement>("[data-timeline-nav]")) {
    const title = nav.querySelector("h2"); nav.replaceChildren(); if (title) nav.append(title);
    for (const year of Object.keys(manifest.years).filter(year => year !== "Undated").sort().reverse()) {
      const section = textElement("section", "", "archive-timeline__year archive-timeline__year--days"), heading = textElement("h3", ""), list = textElement("ul", "");
      const link = (name: "year" | "day", value: string, label: string, count: number) => {
        const a = textElement("a", ""); a.href = `${location.pathname}?${name}=${encodeURIComponent(value)}`;
        a.setAttribute(`data-${name}-filter-option`, ""); a.setAttribute(`data-filter-${name}`, value);
        a.append(textElement("span", label), textElement("span", String(count), "archive-timeline__count")); return a;
      };
      const bounds = manifest.years[year]!; heading.append(link("year", year, year, bounds[1] - bounds[0]));
      for (const day of Object.keys(manifest.days).filter(day => day.startsWith(year)).sort().reverse()) { const range = manifest.days[day]!, li = document.createElement("li"); li.append(link("day", day, day.slice(5), range[1] - range[0])); list.append(li); }
      section.append(heading, list); nav.append(section);
    }
    nav.hidden = !Object.keys(manifest.days).length;
  }
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-dialog-open="context"]')) button.hidden = !Object.keys(manifest.days).length;
  const empty = root.querySelector<HTMLElement>("[data-archive-empty]")!;
  if (!manifest.total) empty.replaceChildren(document.createTextNode(favoritesUI().empty || "No favorites yet. Save an entry to find it here."));
}
