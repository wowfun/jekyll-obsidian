import type { ArchiveCard, ArchiveCollection } from "./archive-query";
import { archiveUrl } from "./archive-client";
import { favoriteButton, favoritesUI, refreshFavoriteButtons } from "./favorite-controls";
import { facetLabel, favoriteLabels } from "./archive-facets";
import { createArchiveDay } from "./archive-days";

export function textElement<K extends keyof HTMLElementTagNameMap>(tag: K, value: string, className?: string): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag); element.textContent = value;
  if (className) element.className = className;
  return element;
}
export function renderArchiveLedger(root: HTMLElement, cards: ArchiveCard[], data: ArchiveCollection, selection?: ReadonlySet<string>): void {
  const grouping = data.ledger_group_by || root.dataset.ledgerGroupBy || "year";
  root.dataset.ledgerGroupBy = grouping;
  const fragment = document.createDocumentFragment(), daily = grouping === "day";
  const ui = favoritesUI(), favorites = Boolean(document.querySelector("[data-favorites-ui]"));
  const newest = cards.map(card => card.display_date).filter((date): date is string => Boolean(date)).sort().at(-1);
  const counts = new Map<string, number>();
  for (const card of cards) { const key = card.display_date || "Undated"; counts.set(key, (counts.get(key) || 0) + 1); }
  let label: string | undefined, ol: HTMLOListElement | undefined;
  for (const card of cards) {
    const group = (daily ? card.display_date : card.year) || ui.undated || "Undated";
    if (group !== label) {
      label = group; const section = document.createElement("section"); section.dataset.filterGroup = "";
      const key = card.display_date || "Undated";
      const container = daily ? createArchiveDay(root, key, counts.get(key)!, newest ? key === newest : fragment.childElementCount === 0) : section;
      if (!daily) section.append(textElement("h2", label));
      const ledger = textElement("section", "", "blog-ledger"); ol = document.createElement("ol"); ledger.append(ol); container.append(ledger);
      if (daily) section.append(container);
      fragment.append(section);
    }
    const row = document.createElement("li"); row.dataset.filterItem = "";
    if (!daily) {
      const meta = textElement("div", "", "blog-ledger__meta"), time = textElement("time", card.display_date || ""); time.dateTime = card.published_at || ""; meta.append(time); row.append(meta);
    }
    const content = textElement("div", "", "blog-ledger__content");
    const title = card.unavailable ? textElement("div", "", "blog-ledger__main") : textElement("a", "", "blog-ledger__main");
    if (title instanceof HTMLAnchorElement) title.href = archiveUrl(card.url).href;
    title.append(textElement("strong", card.title));
    if (card.snapshot_locale) title.lang = card.snapshot_locale;
    if (card.summary) title.append(textElement("span", card.summary, "blog-ledger__description"));
    if (favorites) {
      const heading = textElement("div", "", "blog-ledger__heading"); heading.append(title, favoriteButton({ ...card, favorite_labels: favoriteLabels(card, data) })); content.append(heading);
    } else content.append(title);
    const footer = textElement("footer", "", "archive-card-footer"), tags = textElement("ul", "", "blog-ledger__topics");
    for (const [name, ids] of Object.entries(card.facets)) for (const id of ids) {
      const label = facetLabel(card, name, id, data);
      const link = textElement("a", label); link.dataset.archiveFacet = name; link.dataset.archiveValue = id;
      const url = new URL(window.location.href), values = new Set(url.searchParams.getAll(name));
      values.has(id) ? values.delete(id) : values.add(id);
      url.searchParams.delete("page"); url.searchParams.delete(name);
      [...values].sort().forEach(value => url.searchParams.append(name, value));
      link.href = url.pathname + url.search;
      const li = document.createElement("li"); li.append(link); tags.append(li);
    }
    footer.append(tags);
    if (card.source_url) { const original = textElement("a", card.source_url, "archive-source-url"); original.href = archiveUrl(card.source_url, true).href; original.rel = "noopener noreferrer"; footer.append(original); }
    if (card.date_basis === "observed") footer.append(textElement("small", root.dataset.observedLabel || "First observed"));
    if (card.unavailable) { row.dataset.favoriteUnavailable = ""; footer.append(textElement("small", ui.removed || "This article is no longer published. Your saved summary and original link are kept.")); }
    content.append(footer); row.append(content); ol!.append(row);
  }
  root.querySelector<HTMLElement>("[data-filter-list]")!.replaceChildren(fragment);
  refreshFavoriteButtons(selection);
}
