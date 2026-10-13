import { beforeEach, expect, it } from "vitest";
import { renderArchiveLedger } from "../../src/frontend/archive-ledger";
import type { ArchiveCard } from "../../src/frontend/archive-query";
import { favoriteManifest } from "../../src/frontend/favorite-archive";

const card: ArchiveCard = { id: "a", title: "A", url: "/garden/a/", markdown_url: "/garden/a.md", published_at: "2026-10-10T00:00:00Z", display_date: "2026-10-10", year: "2026", month: "2026-10", facets: { source: ["hn"], topic: ["systems"] } };
beforeEach(() => {
  history.replaceState(null, "", "/garden/?source=hn&topic=agents&day=2026-10-10&page=4");
  document.body.innerHTML = '<main><div data-filter-list></div></main>';
});

it("facet links toggle their value while preserving other filters for new-tab navigation", () => {
  renderArchiveLedger(document.querySelector("main")!, [card], favoriteManifest([card]));
  expect(document.querySelector<HTMLAnchorElement>('[data-archive-facet="source"]')!.getAttribute("href")).toBe("/garden/?topic=agents&day=2026-10-10");
  expect(document.querySelector<HTMLAnchorElement>('[data-archive-facet="topic"]')!.getAttribute("href")).toBe("/garden/?source=hn&day=2026-10-10&topic=agents&topic=systems");
});
