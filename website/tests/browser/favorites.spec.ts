import { archiveReady as ready, expandArchiveDays } from "./archive-helpers";
import { test, expect } from "@playwright/test";

test.describe('favorites without JavaScript', () => {
  test.use({ javaScriptEnabled: false });
  for (const locale of ['en', 'zh-CN']) test(`explains browser storage access without claiming it is empty in ${locale}`, async ({ page }) => {
    await page.goto('/__site__/minimal-archive/' + (locale === 'en' ? '' : locale + '/') + 'favorites/');
    const notice = page.locator('noscript p');
    await expect(notice).toBeVisible();
    await expect(notice).toHaveText(locale === 'en' ? 'Enable JavaScript to show favorites saved in this browser.' : '请启用 JavaScript，以查看保存在此浏览器中的收藏。');
    await expect(notice).not.toContainText(locale === 'en' ? 'No favorites yet' : '还没有收藏');
  });
});

const base = "/__site__/minimal-archive/";
for (const locale of ["en", "zh-CN"]) {
  const root = base + (locale === "en" ? "" : locale + "/");
  test(`favorites persist across archive, article, locales and browser navigation in ${locale}`, async ({ page, context }) => {
    await page.goto(root); await ready(page);
    const dates = page.locator("[data-filter-list] > section .archive-day summary time");
    await expect(dates).toHaveText(locale === "en" ? ["October 10", "October 9"] : ["10月10日", "10月9日"]);
    expect(await dates.evaluateAll(nodes => nodes.map(node => node.getAttribute("datetime")))).toEqual(["2026-10-10", "2026-10-09"]);
    await expect(page.locator(".blog-ledger__meta")).toHaveCount(0);
    const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
    await save.focus(); await page.keyboard.press("Space"); await expect(save).toHaveAttribute("aria-pressed", "true");
    const article = await page.locator(".blog-ledger__main").first().getAttribute("href");
    await page.goto(article!); await expect(page.locator("[data-page-actions] [data-favorite-toggle]")).toHaveAttribute("aria-pressed", "true");
    const other = await context.newPage(); await other.goto(root + "favorites/"); await ready(other);
    await expect(other.locator(".blog-ledger__main strong")).toHaveText(["Newest"]);
    await expect(other.locator("[data-archive-export-open]")).toHaveCount(0);
    await other.locator("[data-archive-reading-toggle]").click();
    await expect(other.locator("[data-reading-loaded]")).toHaveCount(1);
    await expect(other.locator(".archive-reading__body")).toContainText("First paragraph of Newest.");
    await other.locator("[data-language-switcher] summary").click();
    const language = locale === "en" ? "zh-CN" : "en";
    await other.locator(`[data-language-switcher] a[lang="${language}"]`).click(); await ready(other);
    await expect(other.locator("[data-favorite-toggle]")).toHaveAttribute("aria-pressed", "true");
    await other.reload(); await ready(other); await expect(other.locator(".blog-ledger__main strong")).toHaveText(["Newest"]);
    await other.locator("[data-favorite-toggle]").click(); await expect(other.locator("[data-filter-item]")).toHaveCount(0);
    await expect(other.locator("[data-timeline-nav]")).not.toBeVisible();
    await expect(page.locator("[data-favorite-toggle]")).toHaveAttribute("aria-pressed", "false");
    await page.locator("[data-favorite-toggle]").click(); await expect(other.locator("[data-filter-item]")).toHaveCount(1);
    await other.locator('button[data-archive-facet="source"][data-archive-value="hn"]').click(); await ready(other);
    await expect(other.locator("[data-filter-item]")).toHaveCount(1);
    expect(await other.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  });

  test(`removed articles retain snapshots and network failures allow retry in ${locale}`, async ({ page }) => {
    await page.goto(root); await ready(page); await page.locator("[data-filter-item] [data-favorite-toggle]").first().click();
    await page.route("**/manifest.json", route => route.abort());
    await page.goto(root + "favorites/"); await ready(page);
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["Newest"]);
    await expect(page.locator("[data-favorite-unavailable]")).toHaveCount(0);
    await expect(page.locator("[data-archive-retry]")).toBeVisible();
    await page.unroute("**/manifest.json");
    await page.route("**/identities.json", async route => {
      const response = await route.fetch(), body = await response.json();
      body.ids = body.ids.map((id: string) => id === "items/a.md" ? "removed-a.md" : id);
      await route.fulfill({ response, json: body });
    });
    await page.locator("[data-archive-retry]").click(); await ready(page);
    await expect(page.locator("[data-favorite-unavailable]")).toHaveCount(1);
    await expect(page.locator(".archive-source-url")).toHaveAttribute("href", "https://example.com/a");
    await expect(page.locator("a.blog-ledger__main")).toHaveCount(0);
    await page.locator("[data-archive-reading-toggle]").click(); await expect(page.locator(".archive-reading__body")).toHaveCount(0);
    await page.locator("[data-favorite-toggle]").click(); await expect(page.locator("[data-filter-item]")).toHaveCount(0);
  });
}

test("failed browser storage does not show an entry as saved", async ({ page }) => {
  await page.addInitScript(() => { Storage.prototype.setItem = () => { throw new DOMException("full", "QuotaExceededError"); }; });
  await page.goto(base); await ready(page);
  const button = page.locator("[data-filter-item] [data-favorite-toggle]").first(); await button.click();
  await expect(button).toHaveAttribute("aria-pressed", "false"); await expect(page.locator("[data-favorite-status]")).toContainText("Could not save favorites");
});

for (const networkFailure of [false, true]) test(`deployment discovery shares concurrent tab saves when the network ${networkFailure ? "fails" : "succeeds"}`, async ({ page, context }) => {
  await page.goto(base); await ready(page);
  const manifestUrl = (await page.locator("[data-paged-archive]").getAttribute("data-archive-url"))!;
  const original = await (await page.request.get(manifestUrl)).json();
  const first = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  await first.click(); await expect(first).toHaveAttribute("aria-pressed", "true");
  const other = await context.newPage(); await other.goto(base); await ready(other);
  await page.goto(base + "favorites/"); await ready(page);
  let release!: () => void, requested!: () => void;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const started = new Promise<void>(resolve => { requested = resolve; });
  await page.route("**/assets/website/archive/current.json", async route => {
    requested(); await gate;
    if (networkFailure) await route.abort();
    else await route.fulfill({ json: { version: 1, url: "/concurrent-generation/manifest.json" } });
  });
  await page.route("**/concurrent-generation/**", async route => {
    const cards = await other.evaluate(() => JSON.parse(localStorage.getItem("website:favorites:v1:/__site__/minimal-archive")!).entries.map((entry: { snapshots: { en: { title: string } } }) => ({ ...entry.snapshots.en, title: "Updated " + entry.snapshots.en.title })));
    const generation = "c".repeat(64), url = route.request().url();
    const calendar: Record<string, Record<string, [number, number]>> = { years: {}, months: {}, days: {} };
    cards.forEach((card: { year: string; month: string; display_date: string }, ordinal: number) => {
      for (const [name, key] of [["years", card.year], ["months", card.month], ["days", card.display_date]]) {
        calendar[name!]![key!] ||= [ordinal, ordinal]; calendar[name!]![key!]![1] = ordinal + 1;
      }
    });
    await route.fulfill({ json: url.endsWith("manifest.json") ? { ...original, ...calendar, generation, total: cards.length, chunks: ["cards-0.json"] } : url.endsWith("identities.json") ? { generation, ids: cards.map((card: { id: string }) => card.id) } : { generation, start: 0, cards } });
  });
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true })));
  await started;
  await expandArchiveDays(other);
  const second = other.locator("[data-filter-item] [data-favorite-toggle]").nth(1);
  await second.click(); await expect(second).toHaveAttribute("aria-pressed", "true");
  // Hold discovery long enough for a competing refresh to finish with the old generation.
  await page.waitForTimeout(300); release();
  await ready(page); await expect(page.locator("[data-filter-item]")).toHaveCount(2);
  if (networkFailure) {
    await expect(page.locator("[data-archive-retry]")).toBeVisible();
    await expect(page.locator("[data-favorite-unavailable]")).toHaveCount(0);
  } else {
    await expect(page.locator(".blog-ledger__main strong").filter({ hasText: /^Updated / })).toHaveCount(2);
    await expect(page.locator("[data-archive-status]")).toBeEmpty();
  }
});

for (const locale of ["en", "zh-CN"]) test(`empty filter results differ from an empty favorites collection in ${locale}`, async ({ page }) => {
  const root = base + (locale === "en" ? "" : locale + "/");
  await page.goto(root); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first(); await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  await page.goto(root + "favorites/?source=missing"); await ready(page);
  const empty = page.locator("[data-archive-empty]"); await expect(empty).toBeVisible();
  await expect(empty).toContainText(locale === "en" ? "No entries match" : "没有符合");
  await expect(empty.locator("[data-archive-clear]")).toBeVisible(); await empty.locator("button").click(); await ready(page);
  await expect(page.locator("[data-filter-item]")).toHaveCount(1);
  await page.locator("[data-favorite-toggle]").click(); await expect(page.locator("[data-filter-item]")).toHaveCount(0);
  await expect(empty).toContainText(locale === "en" ? "No favorites yet" : "还没有收藏");
});

test("concurrent tab saves wait for the shared lock and keep both articles", async ({ page, context }) => {
  await page.goto(base); await ready(page);
  const other = await context.newPage(); await other.goto(base + "zh-CN/"); await ready(other);
  const guard = await context.newPage(); await guard.goto(base); await ready(guard);
  await guard.evaluate(() => {
    const state = window as unknown as { acquired: boolean; release: () => void };
    void navigator.locks.request("website:favorites:v1:/__site__/minimal-archive", () => {
      state.acquired = true; return new Promise<void>(resolve => { state.release = resolve; });
    });
  });
  await expect.poll(() => guard.evaluate(() => (window as unknown as { acquired: boolean }).acquired)).toBe(true);
  const first = page.locator("[data-filter-item] [data-favorite-toggle]").nth(0);
  await expandArchiveDays(other);
  const second = other.locator("[data-filter-item] [data-favorite-toggle]").nth(1);
  await Promise.all([first.click(), second.click()]);
  await expect(first).toBeDisabled(); await expect(second).toBeDisabled();
  await expect(first).toHaveAttribute("aria-pressed", "false"); await expect(second).toHaveAttribute("aria-pressed", "false");
  await guard.evaluate(() => (window as unknown as { release: () => void }).release());
  await expect(first).toHaveAttribute("aria-pressed", "true"); await expect(second).toHaveAttribute("aria-pressed", "true");
  await page.goto(base + "favorites/"); await ready(page);
  await expect(page.locator("[data-filter-item]")).toHaveCount(2);
});

test("a damaged snapshot leaves healthy favorites usable and preserves a recovery copy", async ({ page }) => {
  await page.goto(base); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  const raw = await page.evaluate(() => {
    const key = "website:favorites:v1:/__site__/minimal-archive", data = JSON.parse(localStorage.getItem(key)!);
    data.entries.push({ id: "damaged", saved_at: "invalid", snapshots: {} });
    const raw = JSON.stringify(data); localStorage.setItem(key, raw); return raw;
  });
  await page.goto(base + "favorites/"); await ready(page);
  await expect(page.locator("[data-filter-item]")).toHaveCount(1);
  await page.locator("[data-favorite-toggle]").click(); await expect(page.locator("[data-filter-item]")).toHaveCount(0);
  expect(await page.evaluate(raw => Object.keys(localStorage).some(key => key.startsWith("website:favorites:v1:/__site__/minimal-archive:recovery:") && localStorage.getItem(key) === raw), raw)).toBe(true);
});

test("favorite filtering reuses loaded cards and keeps an unfinished page input", async ({ page }) => {
  const base = "/__site__/minimal-export/";
  await page.goto(base); await ready(page);
  const url = await page.locator("[data-paged-archive]").getAttribute("data-archive-url");
  const manifest = await (await page.request.get(url!)).json();
  const cards = [];
  for (const file of manifest.chunks) cards.push(...(await (await page.request.get(new URL(file, new URL(url!, page.url())).href)).json()).cards);
  await page.evaluate(cards => localStorage.setItem("website:favorites:v1:/__site__/minimal-export", JSON.stringify({ version: 1, entries: cards.map((card: { id: string }) => ({ id: card.id, saved_at: "2026-10-13T00:00:00Z", snapshots: { en: card } })) })), cards);
  await page.goto(base + "favorites/"); await ready(page);
  let requests = 0; page.on("request", request => { if (/cards-\d+\.json/.test(request.url())) requests++; });
  await page.locator('button[data-archive-facet="source"][data-archive-value="hn"]').click(); await ready(page);
  await page.locator('[data-archive-page-numbers] a[data-archive-page="2"]').click(); await ready(page);
  expect(requests).toBe(0);
  const input = page.locator("[data-archive-page-jump] input"); await input.fill("12");
  await page.evaluate(() => window.dispatchEvent(new Event("website:favorites-change"))); await ready(page);
  await expect(input).toHaveValue("12");
});

test("removing a favorite does not reload evicted card chunks or report a network failure", async ({ page }) => {
  const base = "/__site__/minimal-export/";
  await page.goto(base); await ready(page);
  const url = await page.locator("[data-paged-archive]").getAttribute("data-archive-url");
  const manifest = await (await page.request.get(url!)).json(), cards = [];
  for (const file of manifest.chunks) cards.push(...(await (await page.request.get(new URL(file, new URL(url!, page.url())).href)).json()).cards);
  await page.evaluate(cards => localStorage.setItem("website:favorites:v1:/__site__/minimal-export", JSON.stringify({ version: 1, entries: cards.map((card: { id: string }) => ({ id: card.id, saved_at: "2026-10-13T00:00:00Z", snapshots: { en: card } })) })), cards);
  await page.goto(base + "favorites/"); await ready(page);
  let requests = 0;
  await page.route("**/cards-*.json", route => { requests++; return route.abort(); });
  await page.locator('[data-filter-item] [data-favorite-toggle]').first().click();
  await expect(page.locator('[data-archive-page-status]')).toContainText(String(cards.length - 1));
  await ready(page);
  expect(requests).toBe(0); await expect(page.locator('[data-archive-status]')).toBeEmpty();
});

test("restored pages discover the new deployment instead of using obsolete identity paths", async ({ page }) => {
  await page.goto(base); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  const oldUrl = (await page.locator("[data-paged-archive]").getAttribute("data-archive-url"))!;
  const original = await (await page.request.get(oldUrl)).json();
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  const card = await page.evaluate(() => JSON.parse(localStorage.getItem("website:favorites:v1:/__site__/minimal-archive")!).entries[0].snapshots.en);
  await page.goto(base + "favorites/"); await ready(page);
  let pageRequests = 0; page.on("request", request => { if (new URL(request.url()).pathname === base + "favorites/") pageRequests++; });
  const generation = "b".repeat(64), updated = { ...card, title: "Updated after deployment" };
  const data = { ...original, generation, total: 1, chunks: ["cards-0.json"],
    years: { [card.year]: [0, 1] }, months: { [card.month]: [0, 1] }, days: { [card.display_date]: [0, 1] } };
  await page.route("**/review-generation/**", route => {
    const url = route.request().url();
    return route.fulfill({ json: url.endsWith("manifest.json") ? data : url.endsWith("identities.json") ? { generation, ids: [card.id] } : { generation, start: 0, cards: [updated] } });
  });
  await page.route("**/assets/website/archive/current.json", route => route.fulfill({ json: { version: 1, url: "/review-generation/manifest.json" } }));
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true })));
  await expect(page.locator(".blog-ledger__main strong")).toHaveText("Updated after deployment"); await ready(page); expect(pageRequests).toBe(0);
});

test("recovery copies can be downloaded, restored without overwriting, and explicitly cleared", async ({ page }) => {
  await page.goto(base); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  const originalTitle = await page.locator("[data-filter-item] strong").first().innerText();
  const raw = await page.evaluate(() => {
    const key = "website:favorites:v1:/__site__/minimal-archive", backup = JSON.parse(localStorage.getItem(key)!);
    backup.entries[0].snapshots.en.title = "Old backup title";
    const raw = JSON.stringify(backup); localStorage.setItem(key + ":recovery:old", raw); return raw;
  });
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "false");
  await page.goto(base + "favorites/"); await ready(page);
  const recovery = page.locator("[data-favorites-recovery]"); await recovery.locator("summary").click();
  const download = page.waitForEvent("download"); await recovery.locator('[data-favorite-recovery="download"]').click();
  const file = await download; expect(file.suggestedFilename()).toBe("favorites-recovery.json");
  const stream = await file.createReadStream(); const chunks = []; for await (const chunk of stream!) chunks.push(chunk);
  expect(JSON.parse(Buffer.concat(chunks).toString()).copies[0].raw).toBe(raw);
  await recovery.locator('[data-favorite-recovery="restore"]').click(); await expect(page.locator("[data-filter-item]")).toHaveCount(1);
  await expect(page.locator("[data-filter-item] strong")).toHaveText(originalTitle);
  await recovery.locator('[data-favorite-recovery="clear"]').click(); await expect(recovery).toBeHidden();
  await expect(page.locator("[data-filter-item]")).toHaveCount(1);
});
