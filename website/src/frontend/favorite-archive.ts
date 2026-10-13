import { archiveState, matchArchive, type ArchiveCard, type ArchiveManifest, type ArchiveMatches } from "./archive-query";
import type { ArchiveClient } from "./archive-client";
import { readFavorites, snapshotCard, updateFavoriteSnapshots } from "./favorites-store";
import { favoritesUI, showFavoriteError } from "./favorite-controls";
import { textElement } from "./archive-ledger";

export function favoriteManifest(cards: ArchiveCard[], base?: ArchiveManifest): ArchiveManifest {
  const facets: ArchiveManifest["facets"] = {}, prefixes = { ...(base?.prefixes || { source: "source/", topic: "topics/" }) }, labels = { ...base?.labels };
  const years: ArchiveManifest["years"] = {}, months: ArchiveManifest["months"] = {}, days: ArchiveManifest["days"] = {};
  for (const name of Object.keys(base?.prefixes || { source: "source/", topic: "topics/" })) facets[name] = [];
  cards.forEach((card, ordinal) => {
    for (const [name, ids] of Object.entries(card.facets)) {
      prefixes[name] ||= name + "/"; facets[name] ||= [];
      for (const id of ids) {
        const key = prefixes[name]! + id; labels[key] ||= card.favorite_labels?.[name + "/" + id] || id;
        let option = facets[name]!.find(option => option.id === id);
        if (!option) { option = { id, name: labels[key]!, count: 0, posting: "" }; facets[name]!.push(option); }
        option.count++;
      }
    }
    for (const [mapping, key] of [[years, card.year], [months, card.month], [days, card.display_date]] as const) if (key) { mapping[key] ||= [ordinal, ordinal]; mapping[key]![1] = ordinal + 1; }
  });
  for (const options of Object.values(facets)) options.sort((a, b) => b.count - a.count || a.id.localeCompare(b.id));
  return { version: 1, generation: base?.generation || "0".repeat(64), total: cards.length, page_size: 50, export_max_days: base?.export_max_days || 7,
    facets, prefixes, labels, aliases: base?.aliases || {}, years, months, days, chunks: [], ledger_group_by: "day" };
}
export async function loadFavoriteArchive(client: Pick<ArchiveClient, "manifest" | "lookup">, signal: AbortSignal): Promise<{ cards: ArchiveCard[]; manifest: ArchiveManifest; refreshFailed: boolean }> {
  const locale = document.documentElement.lang || "en";
  let entries: ReturnType<typeof readFavorites>;
  try { entries = readFavorites(); } catch (error) { showFavoriteError(); throw error; }
  const savedEntries = [...entries.values()];
  let cards: ArchiveCard[] = savedEntries.map(entry => {
    const language = Object.hasOwn(entry.snapshots, locale) ? locale : Object.keys(entry.snapshots)[0]!;
    return { ...entry.snapshots[language]!, snapshot_locale: language };
  });
  let base: ArchiveManifest | undefined, refreshFailed = false;
  try {
    base = await client.manifest(signal);
    const current = savedEntries.length ? await client.lookup(savedEntries.map(entry => entry.id), signal) : new Map<string, ArchiveCard>();
    signal.throwIfAborted();
    cards = cards.map(saved => current.has(saved.id) ? { ...snapshotCard(current.get(saved.id)!, base), snapshot_locale: locale } : { ...saved, unavailable: true });
    try { updateFavoriteSnapshots(cards.filter(card => !card.unavailable), locale); } catch { showFavoriteError(); }
  } catch (error) { signal.throwIfAborted(); refreshFailed = true; }
  // A failed request does not prove that an article has been removed.
  cards = cards.map(card => ({ ...card, facets: Object.fromEntries(Object.entries(card.facets).map(([name, ids]) => [name, [...new Set(ids.map(id => {
    const prefix = base?.prefixes[name] || name + "/", alias = base?.aliases[prefix + id];
    return alias?.startsWith(prefix) ? alias.slice(prefix.length) : id;
  }))]])) }));
  cards.sort((a, b) => (a.display_date || "") > (b.display_date || "") ? -1 : (a.display_date || "") < (b.display_date || "") ? 1 : a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
  return { cards, manifest: favoriteManifest(cards, base), refreshFailed };
}
export function selectFavorites(cards: ArchiveCard[], manifest: ArchiveManifest, state: ReturnType<typeof archiveState>): ArchiveMatches {
  const bitmaps: Record<string, Uint8Array> = Object.create(null);
  cards.forEach((card, ordinal) => {
    for (const [name, ids] of Object.entries(card.facets)) for (const id of ids) {
      const key = name + "/" + id; bitmaps[key] ||= new Uint8Array(Math.ceil(cards.length / 8)); bitmaps[key]![ordinal >> 3]! |= 1 << (ordinal & 7);
    }
  });
  return matchArchive(cards.length, manifest.page_size, state.query, bitmaps);
}
export function renderFavoriteFilters(root: HTMLElement, manifest: ArchiveManifest): void {
  const host = root.querySelector<HTMLElement>("[data-favorites-facets]")!;
  // Preserve the localized names supplied by the server before replacing options.
  const names = { source: root.dataset.sourcesLabel || "Sources", topic: root.dataset.topicsLabel || "Topics" };
  host.replaceChildren();
  for (const [name, options] of Object.entries(manifest.facets)) {
    const nav = textElement("nav", "", "tag-filter archive-facet"), heading = textElement("h2", names[name as keyof typeof names] || name, "archive-facet-label"), list = textElement("ul", "", "tag-filter__list"); nav.setAttribute("aria-label", heading.textContent!);
    for (const option of [{ id: "", name: root.dataset.allLabel || "All", count: manifest.total }, ...options]) {
      const button = textElement("button", "", "tag-chip"); button.type = "button"; button.dataset.archiveFacet = name; button.dataset.archiveValue = option.id;
      button.append(document.createTextNode(option.name + " "), textElement("span", String(option.count))); const li = document.createElement("li"); li.append(button); list.append(li);
    }
    nav.append(heading, list); host.append(nav);
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
