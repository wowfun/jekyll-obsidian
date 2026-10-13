import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ArchiveCard } from "../../src/frontend/archive-query";
import { archiveState } from "../../src/frontend/archive-query";
import { favoriteCard, favoritesKey, readFavorites, toggleFavorite } from "../../src/frontend/favorites-store";
import { favoriteButton, initialiseFavorites } from "../../src/frontend/favorite-controls";
import { favoriteManifest, loadFavoriteArchive, selectFavorites } from "../../src/frontend/favorite-archive";

const card = (id: string, date = "2026-10-10", source = "hn"): ArchiveCard => ({ id, title: "Title " + id, url: "/garden/items/" + id + "/", markdown_url: "/garden/items/" + id + ".md", published_at: date + "T12:00:00+08:00", display_date: date, year: date.slice(0, 4), month: date.slice(0, 7), facets: { source: [source], topic: ["agents"] }, source_url: "https://example.test/" + id, summary: "Summary " + id });
let dispose = () => {};
beforeEach(() => {
  localStorage.clear(); document.documentElement.lang = "en";
  document.head.innerHTML = '<meta name="website:favorites-scope" content="/garden">';
  document.body.innerHTML = '<div data-favorites-ui data-save="Save" data-remove="Remove favorite" data-saved="Saved"></div><p data-favorite-status></p>';
});
afterEach(() => { dispose(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("shares identity across languages, preserves snapshots, and isolates sites", () => {
  toggleFavorite(card("a")); document.documentElement.lang = "zh-CN";
  expect(readFavorites().has("a")).toBe(true);
  expect(readFavorites().get("a")!.snapshots.en!.summary).toBe("Summary a");
  document.querySelector<HTMLMetaElement>('meta[name="website:favorites-scope"]')!.content = "/other";
  expect(readFavorites().size).toBe(0);
  document.querySelector<HTMLMetaElement>('meta[name="website:favorites-scope"]')!.content = "/garden";
  toggleFavorite(card("a")); expect(readFavorites().size).toBe(0);
});

it("updates state only after storage succeeds and refreshes on other-tab events", () => {
  const button = favoriteButton(card("a")); document.body.append(button); dispose = initialiseFavorites();
  const set = vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("QuotaExceededError"); });
  button.click(); expect(button.getAttribute("aria-pressed")).toBe("false"); expect(document.querySelector('[data-favorite-status]')!.textContent).toContain("Could not save");
  set.mockRestore(); button.click(); expect(button.getAttribute("aria-pressed")).toBe("true");
  localStorage.removeItem(favoritesKey()); window.dispatchEvent(new StorageEvent("storage", { key: favoritesKey() }));
  expect(button.getAttribute("aria-pressed")).toBe("false");
});

it("rejects unsafe links and preserves malformed stored bytes", () => {
  expect(() => favoriteCard({ ...card("a"), source_url: "javascript:alert(1)" })).toThrow();
  localStorage.setItem(favoritesKey(), "broken"); expect(() => toggleFavorite(card("a"))).toThrow();
  expect(localStorage.getItem(favoritesKey())).toBe("broken");
});

it("preserves the displayed saved state when storage reads become unavailable", () => {
  const button = favoriteButton(card("a")); document.body.append(button); dispose = initialiseFavorites(); button.click();
  expect(button.getAttribute("aria-pressed")).toBe("true");
  vi.stubGlobal("localStorage", { getItem() { throw new Error("SecurityError"); } });
  window.dispatchEvent(new Event("pageshow"));
  expect(button.getAttribute("aria-pressed")).toBe("true");
  expect(document.querySelector("[data-favorite-status]")!.textContent).toContain("Could not save");
});

it("uses current language, keeps removed snapshots, and distinguishes network failure", async () => {
  toggleFavorite(card("a")); toggleFavorite(card("gone", "2025-12-31"));
  const fresh = { ...card("a"), title: "中文标题", url: "/garden/zh-CN/items/a/" };
  document.documentElement.lang = "zh-CN";
  const base = favoriteManifest([card("a")]);
  const client = { manifest: vi.fn(async () => base), lookup: vi.fn(async () => new Map([["a", fresh]])) };
  const loaded = await loadFavoriteArchive(client, new AbortController().signal);
  expect(loaded.cards.map(card => card.title)).toEqual(["中文标题", "Title gone"]);
  expect(loaded.cards[1]!.unavailable).toBe(true); expect(loaded.cards[1]!.snapshot_locale).toBe("en");
  expect(readFavorites().get("a")!.snapshots["zh-CN"]!.title).toBe("中文标题");
  client.manifest.mockRejectedValue(new Error("offline"));
  const fallback = await loadFavoriteArchive(client, new AbortController().signal);
  expect(fallback.refreshFailed).toBe(true); expect(fallback.cards.some(card => card.unavailable)).toBe(false);
  expect(fallback.cards).toHaveLength(2);
});

it("paginates 101 favorites, combines facets and dates, and clamps page after removal", () => {
  const cards = Array.from({ length: 101 }, (_, i) => card(String(i), i < 51 ? "2026-10-10" : "2026-10-09", i % 2 ? "dsh" : "hn"));
  const data = favoriteManifest(cards);
  expect(selectFavorites(cards, data, archiveState(data, "?page=3"))).toMatchObject({ count: 101, page: 3, pages: 3, ordinals: [100] });
  expect(selectFavorites(cards, data, archiveState(data, "?source=hn&source=dsh&topic=agents&day=2026-10-10"))).toMatchObject({ count: 51 });
  expect(selectFavorites(cards, data, archiveState(data, "?source=missing"))).toMatchObject({ count: 0 });
  const reduced = cards.slice(0, 50), reducedData = favoriteManifest(reduced);
  expect(selectFavorites(reduced, reducedData, archiveState(reducedData, "?page=3"))).toMatchObject({ count: 50, page: 1, pages: 1 });
});
