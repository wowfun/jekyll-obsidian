import { afterEach, beforeEach, expect, it, vi } from "vitest";
import type { ArchiveCard } from "../../src/frontend/archive-query";
import { archiveState } from "../../src/frontend/archive-query";
import { favoriteCard, favoriteRecoveryCopies, clearFavoriteRecovery, restoreFavoriteRecovery, favoritesKey, readFavorites, readFavoriteCollection, toggleFavorite, updateFavoriteSnapshots } from "../../src/frontend/favorites-store";
import { favoriteButton, initialiseFavorites, refreshFavoriteButtons } from "../../src/frontend/favorite-controls";
import { favoriteManifest, loadFavoriteArchive, reconcileFavoriteArchive, selectFavorites } from "../../src/frontend/favorite-archive";

const card = (id: string, date = "2026-10-10", source = "hn"): ArchiveCard => ({ id, title: "Title " + id, url: "/garden/items/" + id + "/", markdown_url: "/garden/items/" + id + ".md", published_at: date + "T12:00:00+08:00", display_date: date, year: date.slice(0, 4), month: date.slice(0, 7), facets: { source: [source], topic: ["agents"] }, source_url: "https://example.test/" + id, summary: "Summary " + id });
let dispose = () => {};
beforeEach(() => {
  const entries = new Map<string, string>();
  vi.stubGlobal("localStorage", {
    get length() { return entries.size; }, clear() { entries.clear(); },
    key(index: number) { return [...entries.keys()][index] ?? null; },
    getItem(key: string) { return entries.get(key) ?? null; },
    setItem(key: string, value: string) { entries.set(key, value); }, removeItem(key: string) { entries.delete(key); }
  });
  let queue = Promise.resolve();
  vi.stubGlobal("navigator", { locks: { request(_name: string, operation: () => unknown) {
    const next = queue.then(operation); queue = next.then(() => {}, () => {}); return next;
  } } });
  localStorage.clear(); document.documentElement.lang = "en";
  document.head.innerHTML = '<meta name="website:favorites-scope" content="/garden">';
  document.body.innerHTML = '<div data-favorites-ui data-save="Save" data-remove="Remove favorite" data-saved="Saved"></div><p data-favorite-status></p>';
});
afterEach(() => { dispose(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it("shares identity across languages, preserves snapshots, and isolates sites", async () => {
  await toggleFavorite(card("a")); document.documentElement.lang = "zh-CN";
  expect(readFavorites().has("a")).toBe(true);
  expect(readFavorites().get("a")!.snapshots.en!.summary).toBe("Summary a");
  document.querySelector<HTMLMetaElement>('meta[name="website:favorites-scope"]')!.content = "/other";
  expect(readFavorites().size).toBe(0);
  document.querySelector<HTMLMetaElement>('meta[name="website:favorites-scope"]')!.content = "/garden";
  await toggleFavorite(card("a")); expect(readFavorites().size).toBe(0);
});

it("updates state only after storage succeeds and refreshes on other-tab events", async () => {
  const button = favoriteButton(card("a")); document.body.append(button); dispose = initialiseFavorites();
  const set = vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new Error("QuotaExceededError"); });
  button.click(); await vi.waitFor(() => expect(button.disabled).toBe(false)); expect(button.getAttribute("aria-pressed")).toBe("false"); expect(document.querySelector('[data-favorite-status]')!.textContent).toContain("Could not save");
  set.mockRestore(); button.click(); await vi.waitFor(() => expect(button.disabled).toBe(false)); expect(button.getAttribute("aria-pressed")).toBe("true");
  localStorage.removeItem(favoritesKey()); window.dispatchEvent(new StorageEvent("storage", { key: favoritesKey() }));
  expect(button.getAttribute("aria-pressed")).toBe("false");
});

it("rejects unsafe links and preserves malformed stored bytes", async () => {
  expect(() => favoriteCard({ ...card("a"), source_url: "javascript:alert(1)" })).toThrow();
  localStorage.setItem(favoritesKey(), "broken"); await expect(toggleFavorite(card("a"))).rejects.toThrow();
  expect(localStorage.getItem(favoritesKey())).toBe("broken");
});

it("preserves the displayed saved state when storage reads become unavailable", async () => {
  const button = favoriteButton(card("a")); document.body.append(button); dispose = initialiseFavorites(); button.click(); await vi.waitFor(() => expect(button.disabled).toBe(false));
  expect(button.getAttribute("aria-pressed")).toBe("true");
  vi.stubGlobal("localStorage", { getItem() { throw new Error("SecurityError"); } });
  window.dispatchEvent(new Event("pageshow"));
  expect(button.getAttribute("aria-pressed")).toBe("true");
  expect(document.querySelector("[data-favorite-status]")!.textContent).toContain("Could not save");
});

it("uses current language, keeps removed snapshots, and distinguishes network failure", async () => {
  await toggleFavorite(card("a")); await toggleFavorite(card("gone", "2025-12-31"));
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

it("keeps concurrent writes from different tabs instead of overwriting the collection", async () => {
  const set = localStorage.setItem.bind(localStorage);
  let second: unknown;
  vi.spyOn(localStorage, "setItem").mockImplementationOnce((key, raw) => {
    second = toggleFavorite(card("b"));
    set(key, raw);
  });
  await toggleFavorite(card("a")); await second;
  expect([...readFavorites().keys()].sort()).toEqual(["a", "b"]);
});

it("shows healthy entries alongside corruption and backs up the original bytes before repair", async () => {
  await toggleFavorite(card("a"));
  const data = JSON.parse(localStorage.getItem(favoritesKey())!);
  data.entries.push({ id: "bad", saved_at: "invalid", snapshots: {} });
  const raw = JSON.stringify(data); localStorage.setItem(favoritesKey(), raw);
  expect([...readFavorites().keys()]).toEqual(["a"]);
  expect(localStorage.getItem(favoritesKey())).toBe(raw);
  await toggleFavorite(card("b"));
  expect([...readFavorites().keys()].sort()).toEqual(["a", "b"]);
  expect(Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i)!).some(key => key.startsWith(favoritesKey() + ":recovery:") && localStorage.getItem(key) === raw)).toBe(true);
});

it("rejects non-existent calendar days, not only malformed date strings", () => {
  expect(() => favoriteCard({ ...card("a"), display_date: "2026-02-30" })).toThrow();
  expect(() => favoriteCard({ ...card("a"), display_date: "2026-99-99" })).toThrow();
  expect(favoriteCard(card("leap", "2024-02-29")).display_date).toBe("2024-02-29");
});

it("isolates a malformed button without aborting healthy controls", () => {
  const bad = favoriteButton(card("bad")), good = favoriteButton(card("good"));
  bad.dataset.favoriteCard = "{"; bad.hidden = true; good.hidden = true; document.body.append(bad, good);
  expect(() => refreshFavoriteButtons()).not.toThrow();
  expect(bad.disabled).toBe(true); expect(good.hidden).toBe(false);
});

it("does not restore a favorite removed while snapshot refresh is waiting for its lock", async () => {
  await toggleFavorite(card("a"));
  const removal = toggleFavorite(card("a"));
  const refresh = updateFavoriteSnapshots([{ ...card("a"), title: "Refreshed" }]);
  await Promise.all([removal, refresh]);
  expect(readFavorites().size).toBe(0);
});

it("reports unsupported locking without modifying storage or showing a successful save", async () => {
  vi.stubGlobal("navigator", {});
  const button = favoriteButton(card("a")); document.body.append(button); dispose = initialiseFavorites();
  button.click(); await vi.waitFor(() => expect(button.disabled).toBe(false));
  expect(localStorage.getItem(favoritesKey())).toBe(null);
  expect(button.getAttribute("aria-pressed")).toBe("false");
  expect(document.querySelector('[data-favorite-status]')!.textContent).toContain("HTTPS or localhost");
});

it("preserves damaged bytes if the recovery backup cannot be saved", async () => {
  await toggleFavorite(card("a"));
  const data = JSON.parse(localStorage.getItem(favoritesKey())!); data.entries.push(null);
  const raw = JSON.stringify(data); localStorage.setItem(favoritesKey(), raw);
  vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new DOMException("full", "QuotaExceededError"); });
  await expect(toggleFavorite(card("b"))).rejects.toThrow();
  expect(localStorage.getItem(favoritesKey())).toBe(raw);
});

it("keeps an offline custom facet named constructor without inheriting Object properties", () => {
  const saved = { ...card("custom"), facets: { constructor: ["books"] }, favorite_labels: { "constructor/books": "Books" } };
  const data = favoriteManifest([saved]);
  expect(data.prefixes.constructor).toBe("constructor/");
  expect(data.facets.constructor).toEqual([{ id: "books", name: "Books", count: 1 }]);
});

it("resolves saved custom facets even when the current configuration no longer defines them", async () => {
  await toggleFavorite({ ...card("custom"), facets: { constructor: ["books"] } });
  const base = favoriteManifest([]); base.aliases = { "constructor/books": "constructor/novels" };
  const loaded = await loadFavoriteArchive({ manifest: async () => base, lookup: async () => new Map() }, new AbortController().signal);
  expect(loaded.cards[0]!.facets.constructor).toEqual(["novels"]);
});

it("keeps the storage failure reason visible when a damaged collection cannot be repaired", async () => {
  await toggleFavorite(card("a"));
  const data = JSON.parse(localStorage.getItem(favoritesKey())!); data.entries.push(null);
  localStorage.setItem(favoritesKey(), JSON.stringify(data));
  const button = favoriteButton(card("b")); document.body.append(button); dispose = initialiseFavorites();
  vi.spyOn(localStorage, "setItem").mockImplementation(() => { throw new DOMException("full", "QuotaExceededError"); });
  button.click(); await vi.waitFor(() => expect(button.disabled).toBe(false));
  expect(document.querySelector('[data-favorite-status]')!.textContent).toContain("storage is full");
});

it("bounds recovery copies and preserves both damaged payloads until the earlier copy is cleared", async () => {
  await toggleFavorite(card("a"));
  const damage = () => { const data = JSON.parse(localStorage.getItem(favoritesKey())!); data.entries.push(null); const raw = JSON.stringify(data); localStorage.setItem(favoritesKey(), raw); return raw; };
  const first = damage(); await toggleFavorite(card("b"));
  const second = damage();
  await expect(toggleFavorite(card("c"))).rejects.toMatchObject({ code: "recovery_required" });
  const keys = Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i)!).filter(key => key.startsWith(favoritesKey() + ":recovery:"));
  expect(keys).toHaveLength(1); expect(localStorage.getItem(keys[0]!)).toBe(first);
  expect(localStorage.getItem(favoritesKey())).toBe(second);
});

it("restores healthy entries without overwriting newer snapshots, and clears only this site's recovery copies", async () => {
  await toggleFavorite(card("a"));
  const raw = localStorage.getItem(favoritesKey())!;
  localStorage.setItem(favoritesKey() + ":recovery:legacy", raw);
  localStorage.setItem("website:favorites:v1:/other:recovery:current", raw);
  await toggleFavorite({ ...card("a"), title: "Newer snapshot" }, "en", true); await toggleFavorite(card("b"));
  await restoreFavoriteRecovery(); expect([...readFavorites().keys()].sort()).toEqual(["a", "b"]);
  expect(readFavorites().get("a")!.snapshots.en!.title).toBe("Newer snapshot");
  expect(favoriteRecoveryCopies()[0]!.raw).toBe(raw);
  await clearFavoriteRecovery(); expect(favoriteRecoveryCopies()).toHaveLength(0);
  expect(localStorage.getItem("website:favorites:v1:/other:recovery:current")).toBe(raw);
  expect(readFavorites().size).toBe(2);
});

it("reconciles removals locally and looks up only new IDs without a current-language snapshot", async () => {
  await toggleFavorite(card("a")); await toggleFavorite(card("b"));
  const client = { manifest: async () => favoriteManifest([card("a"), card("b")]), lookup: vi.fn(async (ids: string[]) => new Map(ids.map(id => [id, card(id)]))) };
  const loaded = await loadFavoriteArchive(client, new AbortController().signal); client.lookup.mockClear();
  await toggleFavorite(card("a"));
  const removed = await reconcileFavoriteArchive(loaded, client, new AbortController().signal);
  expect(removed.cards.map(card => card.id)).toEqual(["b"]); expect(client.lookup).not.toHaveBeenCalled();
  await toggleFavorite(card("c"), "zh-CN");
  const added = await reconcileFavoriteArchive(removed, client, new AbortController().signal);
  expect(client.lookup).toHaveBeenCalledExactlyOnceWith(["c"], expect.any(AbortSignal));
  expect(added.cards.map(card => card.id)).toEqual(["b", "c"]);
});

it("refreshes a restored current-language snapshot by looking up only its new ID", async () => {
  await toggleFavorite(card("a"));
  const client = { manifest: async () => favoriteManifest([card("a"), card("b")]), lookup: vi.fn(async (ids: string[]) => new Map(ids.map(id => [id, { ...card(id), title: "Current " + id }]))) };
  const loaded = await loadFavoriteArchive(client, new AbortController().signal); client.lookup.mockClear();
  localStorage.setItem(favoritesKey() + ":recovery:current", JSON.stringify({ version: 1, entries: [{ id: "b", saved_at: "2026-10-10T00:00:00Z", snapshots: { en: { ...card("b"), title: "Old backup title" } } }] }));
  await restoreFavoriteRecovery();
  const restored = await reconcileFavoriteArchive(loaded, client, new AbortController().signal);
  expect(client.lookup).toHaveBeenCalledExactlyOnceWith(["b"], expect.any(AbortSignal));
  expect(restored.cards.find(card => card.id === "b")!.title).toBe("Current b");
});

it("uses a rendered button's card directly without serializing or parsing it again", () => {
  readFavorites();
  const parse = vi.spyOn(JSON, "parse"), stringify = vi.spyOn(JSON, "stringify");
  const button = favoriteButton(card("a")); document.body.append(button); refreshFavoriteButtons();
  expect(parse).not.toHaveBeenCalled(); expect(stringify).not.toHaveBeenCalled();
  expect(button.hasAttribute("data-favorite-card")).toBe(false);
  expect(button.getAttribute("aria-label")).toBe("Save: Title a");
});

it("checks recovery visibility without reading recovery payloads", () => {
  const key = favoritesKey() + ":recovery:current";
  localStorage.setItem(key, "original damaged data".repeat(1000));
  document.body.insertAdjacentHTML("beforeend", "<details data-favorites-recovery hidden></details>");
  const read = vi.spyOn(localStorage, "getItem"); dispose = initialiseFavorites();
  window.dispatchEvent(new Event("pageshow"));
  expect(document.querySelector<HTMLElement>("[data-favorites-recovery]")!.hidden).toBe(false);
  expect(read.mock.calls.some(([name]) => name === key)).toBe(false);
});

it("computes implicit toggle intent under the shared lock", async () => {
  await Promise.all([toggleFavorite(card("a")), toggleFavorite(card("a"))]);
  expect(readFavorites().size).toBe(0);
});

it("does not mark a stale loading collection current when favorites change during lookup", async () => {
  await toggleFavorite(card("a"));
  let release!: () => void; const gate = new Promise<void>(resolve => { release = resolve; });
  const client = { manifest: async () => favoriteManifest([card("a"), card("b")]), lookup: vi.fn(async () => { await gate; return new Map([["a", card("a")]]); }) };
  const pending = loadFavoriteArchive(client, new AbortController().signal);
  await vi.waitFor(() => expect(client.lookup).toHaveBeenCalled());
  await toggleFavorite(card("b")); release();
  const loaded = await pending;
  expect(loaded.cards.map(card => card.id).sort()).toEqual([...loaded.snapshots.keys()].sort());
});

it("does not retain a removed favorite when a new-ID lookup is pending", async () => {
  await toggleFavorite(card("a"));
  const base = favoriteManifest([card("a"), card("c")]);
  const loaded = await loadFavoriteArchive({ manifest: async () => base, lookup: async () => new Map([["a", card("a")]]) }, new AbortController().signal);
  await toggleFavorite(card("c"));
  let release!: () => void; const gate = new Promise<void>(resolve => { release = resolve; });
  const client = { lookup: vi.fn(async () => { await gate; return new Map([["c", card("c")]]); }) };
  const pending = reconcileFavoriteArchive(loaded, client, new AbortController().signal);
  await vi.waitFor(() => expect(client.lookup).toHaveBeenCalled());
  await toggleFavorite(card("a")); release();
  expect((await pending).cards.map(card => card.id)).toEqual(["c"]);
});

it("does not overwrite a snapshot saved by another tab while article lookup was pending", async () => {
  await toggleFavorite(card("a"));
  let release!: () => void; const gate = new Promise<void>(resolve => { release = resolve; });
  const client = { manifest: async () => favoriteManifest([card("a")]), lookup: vi.fn(async () => { await gate; return new Map([["a", { ...card("a"), title: "Earlier server title" }]]); }) };
  const pending = loadFavoriteArchive(client, new AbortController().signal);
  await vi.waitFor(() => expect(client.lookup).toHaveBeenCalled());
  await toggleFavorite({ ...card("a"), title: "Newer tab title" }, "en", true); release();
  expect((await pending).cards[0]!.title).toBe("Newer tab title");
  expect(readFavorites().get("a")!.snapshots.en!.title).toBe("Newer tab title");
});

it("does not write unchanged snapshots when facet or label key order changes", async () => {
  await toggleFavorite({ ...card("a"), favorite_labels: { "source/hn": "HN", "topic/agents": "Agents" } });
  const write = vi.spyOn(localStorage, "setItem");
  await updateFavoriteSnapshots([{ ...card("a"), facets: { topic: ["agents"], source: ["hn"] }, favorite_labels: { "topic/agents": "Agents", "source/hn": "HN" } }]);
  expect(write).not.toHaveBeenCalled();
});

it("does not rewrite the collection for an already-applied explicit save or removal", async () => {
  await toggleFavorite(card("a"), "en", true);
  const write = vi.spyOn(localStorage, "setItem");
  await toggleFavorite(card("a"), "en", true); await toggleFavorite(card("missing"), "en", false);
  expect(write).not.toHaveBeenCalled();
});

it("keeps cached snapshots immutable without cloning them on every read", async () => {
  await toggleFavorite({ ...card("a"), favorite_labels: { "source/hn": "HN" } });
  const collection = readFavoriteCollection(), entry = collection.entries.get("a")!, snapshot = entry.snapshots.en!;
  expect(Reflect.set(snapshot, "title", "Corrupted title")).toBe(false);
  expect(Reflect.set(snapshot.facets.topic!, "0", "corrupted-topic")).toBe(false);
  expect(Reflect.set(snapshot.favorite_labels!, "source/hn", "Corrupted label")).toBe(false);
  expect(Reflect.set(entry.snapshots, "en", card("bad"))).toBe(false);
  expect(Reflect.set(entry, "saved_at", "bad")).toBe(false);
  expect(readFavoriteCollection().entries.get("a")!.snapshots.en).toBe(snapshot);
  expect(readFavorites().get("a")!.snapshots.en!.title).toBe("Title a");
});

it("does not expose mutation methods or a mutable map through forEach", async () => {
  await toggleFavorite(card("a"));
  const collection = await updateFavoriteSnapshots([{ ...card("a"), title: "Updated a" }]);
  expect(() => (collection.entries as Map<string, unknown>).clear()).toThrow();
  collection.entries.forEach((_entry, _key, map) => expect(map).toBe(collection.entries));
  expect(readFavoriteCollection().entries.size).toBe(1);
  const copy = readFavorites(); copy.clear(); expect(readFavoriteCollection().entries.size).toBe(1);
});

it("refreshes the current locale while preserving a concurrent save in another locale", async () => {
  await toggleFavorite(card("a"));
  let release!: () => void; const gate = new Promise<void>(resolve => { release = resolve; });
  const client = { manifest: async () => favoriteManifest([card("a")]), lookup: vi.fn(async () => { await gate; return new Map([["a", { ...card("a"), title: "Current English" }]]); }) };
  const pending = loadFavoriteArchive(client, new AbortController().signal);
  await vi.waitFor(() => expect(client.lookup).toHaveBeenCalled());
  await toggleFavorite({ ...card("a"), title: "新的中文标题" }, "zh-CN", true); release();
  expect((await pending).cards[0]!.title).toBe("Current English");
  const snapshots = readFavorites().get("a")!.snapshots;
  expect(snapshots.en!.title).toBe("Current English"); expect(snapshots["zh-CN"]!.title).toBe("新的中文标题");
});

it("reparses a changed SSR button snapshot and updates its label", () => {
  const button = favoriteButton(card("a")); document.body.append(button);
  button.dataset.favoriteCard = JSON.stringify(card("a")); refreshFavoriteButtons();
  button.dataset.favoriteCard = JSON.stringify({ ...card("a"), title: "Changed title" }); refreshFavoriteButtons();
  expect(button.getAttribute("aria-label")).toBe("Save: Changed title");
});
