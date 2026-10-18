import { afterEach, beforeEach, expect, it } from "vitest";
import { archiveDayHeading, initialiseArchiveDays } from "../../src/frontend/archive-days";
import { renderArchiveLedger } from "../../src/frontend/archive-ledger";
import type { ArchiveCard } from "../../src/frontend/archive-query";
import { favoriteManifest } from "../../src/frontend/favorite-archive";
import { archiveDayUI } from "./support/archive-days";

let dispose = () => {};
const card = (date: string | null, id = date || "none"): ArchiveCard => ({ id, title: id, url: `/items/${id}/`, markdown_url: `/items/${id}.md`, published_at: date && `${date}T00:00:00+08:00`, display_date: date, year: date?.slice(0, 4) || "Undated", month: date?.slice(0, 7) || null, facets: {} });
beforeEach(() => {
  document.body.innerHTML = `<main data-ledger-current-year="2026">${archiveDayUI}<div data-filter-list></div></main>`;
});
afterEach(() => { dispose(); document.body.replaceChildren(); });
const root = () => document.querySelector<HTMLElement>("main")!;
const groups = () => [...document.querySelectorAll<HTMLDetailsElement>("details[data-ledger-day]")];
const render = (cards: ArchiveCard[]) => renderArchiveLedger(root(), cards, favoriteManifest(cards));

it("substitutes localized month names literally without interpreting dollar patterns or nested tokens", () => {
  const months = Array.from({ length: 12 }, () => "Month"); months[9] = "Oct$& {day} {year}";
  root().querySelector<HTMLElement>("[data-ledger-day-ui]")!.dataset.months = months.join("|");
  expect(archiveDayHeading(root(), "2026-10-15").date).toBe("Oct$& {day} {year} 15");
});

it("opens the newest day, counts only this projection, and localizes old years and undated entries", () => {
  render([card("2026-10-15"), card("2026-10-15", "second"), card("2025-12-31"), card(null)]);
  const days = initialiseArchiveDays(root()); dispose = days.dispose;
  expect(groups().map(group => group.open)).toEqual([true, false, false]);
  expect(groups().map(group => group.querySelector("summary")!.textContent)).toEqual([
    "October 15Thursday · 2 entries", "December 31, 2025Wednesday · 1 entry", "Undated1 entry"
  ]);
  expect(groups()[0]!.querySelector("time")!.dateTime).toBe("2026-10-15");
  render([card("2026-10-15")]);
  days.refresh();
  expect(groups()[0]!.querySelector("[data-ledger-day-count]")!.textContent).toBe("1 entry");
  render([card(null)]); days.refresh(); expect(groups()[0]!.open).toBe(true);
  render([]); days.refresh(); expect(groups()).toHaveLength(0);
});

it("retains explicit choices across replacement and filtering, and disposal starts a fresh view", () => {
  const cards = [card("2026-10-15"), card("2026-10-14")]; render(cards);
  let days = initialiseArchiveDays(root()); dispose = days.dispose;
  groups()[0]!.open = false; groups()[1]!.open = true;
  // Replace immediately, before either native toggle event can be delivered.
  days.replace(() => render([cards[1]!])); expect(groups()[0]!.open).toBe(true);
  days.replace(() => render(cards)); expect(groups().map(group => group.open)).toEqual([false, true]);
  const last = groups()[1]!; last.closest<HTMLElement>("[data-filter-group]")!.hidden = true;
  days.refresh(); expect(groups()[0]!.open).toBe(false);
  last.closest<HTMLElement>("[data-filter-group]")!.hidden = false;
  last.querySelector<HTMLElement>("[data-filter-item]")!.hidden = true;
  days.refresh(); expect(last.querySelector("[data-ledger-day-count]")!.textContent).toBe("0 entries");
  days.dispose(); render(cards); days = initialiseArchiveDays(root()); dispose = days.dispose;
  expect(groups().map(group => group.open)).toEqual([true, false]);
});

it("uses calendar keys rather than browser timezone for Chinese dates and weekdays", () => {
  root().insertAdjacentHTML("afterbegin", '<template data-ledger-day-ui data-date="{month}{day}日" data-date-year="{year}年{month}{day}日" data-months="1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月" data-weekdays="星期日|星期一|星期二|星期三|星期四|星期五|星期六" data-entry="{count} 条" data-entries="{count} 条" data-undated="未注明日期"></template>');
  expect(archiveDayHeading(root(), "2026-10-15")).toEqual({ date: "10月15日", weekday: "星期四", dated: true });
  expect(archiveDayHeading(root(), "2025-12-31").date).toBe("2025年12月31日");
  expect(archiveDayHeading(root(), "2026-02-30").dated).toBe(false);
  expect(archiveDayHeading(root(), "Undated").date).toBe("未注明日期");
  render([card("2026-10-15"), card("2026-10-15", "second")]);
  const days = initialiseArchiveDays(root()); dispose = days.dispose;
  expect(groups()[0]!.querySelector("[data-ledger-day-count]")!.textContent).toBe("2 条");
});

it("recomputes the latest visible day without treating automatic defaults as manual choices", () => {
  render([card("2026-10-15"), card("2026-10-14")]);
  const days = initialiseArchiveDays(root()); dispose = days.dispose;
  const newest = groups()[0]!.closest<HTMLElement>("[data-filter-group]")!;
  newest.hidden = true; days.refresh(); expect(groups()[1]!.open).toBe(true);
  newest.hidden = false; days.refresh(); expect(groups().map(group => group.open)).toEqual([true, false]);
});

it("retains explicit SSR disclosure changes made before hydration", () => {
  render([card("2026-10-15"), card("2026-10-14")]);
  // SSR opened the latest day; the user closes it and opens an older day before JS starts.
  groups()[0]!.dataset.ledgerDefaultOpen = "true";
  groups()[0]!.open = false;
  groups()[1]!.dataset.ledgerDefaultOpen = "false";
  groups()[1]!.open = true;
  const days = initialiseArchiveDays(root()); dispose = days.dispose;
  expect(groups().map(group => group.open)).toEqual([false, true]);
  days.replace(() => render([card("2026-10-15"), card("2026-10-14")]));
  expect(groups().map(group => group.open)).toEqual([false, true]);
});
