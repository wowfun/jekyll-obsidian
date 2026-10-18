import { beforeEach, expect, it } from "vitest";
import { renderArchiveLedger } from "../../src/frontend/archive-ledger";
import type { ArchiveCard } from "../../src/frontend/archive-query";
import { favoriteManifest } from "../../src/frontend/favorite-archive";
import { archiveDayUI } from "./support/archive-days";
import { initialiseArchiveDays } from "../../src/frontend/archive-days";

const card: ArchiveCard = { id: "a", title: "A", url: "/garden/a/", markdown_url: "/garden/a.md", published_at: "2026-10-10T00:00:00Z", display_date: "2026-10-10", year: "2026", month: "2026-10", facets: { source: ["hn"], topic: ["systems"] } };
beforeEach(() => {
  history.replaceState(null, "", "/garden/?source=hn&topic=agents&day=2026-10-10&page=4");
  document.body.innerHTML = `<main data-ledger-current-year="2026">${archiveDayUI}<div data-filter-list></div></main>`;
});

it("facet links toggle their value while preserving other filters for new-tab navigation", () => {
  renderArchiveLedger(document.querySelector("main")!, [card], favoriteManifest([card]));
  expect(document.querySelector<HTMLAnchorElement>('[data-archive-facet="source"]')!.getAttribute("href")).toBe("/garden/?topic=agents&day=2026-10-10");
  expect(document.querySelector<HTMLAnchorElement>('[data-archive-facet="topic"]')!.getAttribute("href")).toBe("/garden/?source=hn&day=2026-10-10&topic=agents&topic=systems");
});

it("uses current manifest grouping after a deployment and updates the CSS grouping attribute", () => {
  const root = document.querySelector<HTMLElement>("main")!; root.dataset.ledgerGroupBy = "day";
  renderArchiveLedger(root, [card], { ...favoriteManifest([card]), ledger_group_by: "year" });
  expect(root.dataset.ledgerGroupBy).toBe("year");
  expect(root.querySelector("h2")!.textContent).toBe("2026");
  expect(root.querySelectorAll(".blog-ledger__meta")).toHaveLength(1);
});

it("uses the serialized UI and controller when a new manifest switches a year archive to day grouping", () => {
  const root = document.querySelector<HTMLElement>("main")!;
  root.dataset.ledgerGroupBy = "year";
  const days = initialiseArchiveDays(root);
  try {
    days.replace(() => renderArchiveLedger(root, [card], favoriteManifest([card])));
    expect(root.querySelector("h2")!.textContent).toBe("October 10");
    expect(root.querySelector<HTMLDetailsElement>("details")!.open).toBe(true);
    expect(root.querySelector("[data-ledger-day-count]")!.textContent).toBe("1 entry");
  } finally { days.dispose(); }
});
