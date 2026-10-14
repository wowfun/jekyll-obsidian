import { test, expect, type Page } from "@playwright/test";

const root = "/__site__/minimal-archive/";
const ready = async (page: Page) => {
  await expect(page.locator("[data-paged-archive]")).not.toHaveAttribute("aria-busy", "true");
  await expect(page.locator("[data-archive-page-status]")).not.toBeEmpty();
};

test("concurrent tab saves wait for the shared lock and keep both articles", async ({ page, context }) => {
  await page.goto(root); await ready(page);
  const other = await context.newPage(); await other.goto(root + "zh-CN/"); await ready(other);
  const guard = await context.newPage(); await guard.goto(root); await ready(guard);
  await guard.evaluate(() => {
    const state = window as unknown as { acquired: boolean; release: () => void };
    void navigator.locks.request("website:favorites:v1:/__site__/minimal-archive", () => {
      state.acquired = true; return new Promise<void>(resolve => { state.release = resolve; });
    });
  });
  await expect.poll(() => guard.evaluate(() => (window as unknown as { acquired: boolean }).acquired)).toBe(true);
  const first = page.locator("[data-filter-item] [data-favorite-toggle]").nth(0);
  const second = other.locator("[data-filter-item] [data-favorite-toggle]").nth(1);
  await Promise.all([first.click(), second.click()]);
  await expect(first).toBeDisabled(); await expect(second).toBeDisabled();
  await expect(first).toHaveAttribute("aria-pressed", "false"); await expect(second).toHaveAttribute("aria-pressed", "false");
  await guard.evaluate(() => (window as unknown as { release: () => void }).release());
  await expect(first).toHaveAttribute("aria-pressed", "true"); await expect(second).toHaveAttribute("aria-pressed", "true");
  await page.goto(root + "favorites/"); await ready(page);
  await expect(page.locator("[data-filter-item]")).toHaveCount(2);
});

test("a damaged snapshot leaves healthy favorites usable and preserves a recovery copy", async ({ page }) => {
  await page.goto(root); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  const raw = await page.evaluate(() => {
    const key = "website:favorites:v1:/__site__/minimal-archive", data = JSON.parse(localStorage.getItem(key)!);
    data.entries.push({ id: "damaged", saved_at: "invalid", snapshots: {} });
    const raw = JSON.stringify(data); localStorage.setItem(key, raw); return raw;
  });
  await page.goto(root + "favorites/"); await ready(page);
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
  await page.goto(root); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  const card = JSON.parse((await save.getAttribute("data-favorite-card"))!);
  const oldUrl = (await page.locator("[data-paged-archive]").getAttribute("data-archive-url"))!;
  const original = await (await page.request.get(oldUrl)).json();
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  await page.goto(root + "favorites/"); await ready(page);
  const generation = "b".repeat(64), updated = { ...card, title: "Updated after deployment" };
  const data = { ...original, generation, total: 1, chunks: ["cards-0.json"],
    years: { [card.year]: [0, 1] }, months: { [card.month]: [0, 1] }, days: { [card.display_date]: [0, 1] } };
  await page.route("**/review-generation/**", route => {
    const url = route.request().url();
    return route.fulfill({ json: url.endsWith("manifest.json") ? data : url.endsWith("identities.json") ? { generation, ids: [card.id] } : { generation, start: 0, cards: [updated] } });
  });
  await page.route("**/minimal-archive/favorites/", async route => {
    const response = await route.fetch();
    await route.fulfill({ response, body: (await response.text()).replace(oldUrl, "/review-generation/manifest.json") });
  });
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true })));
  await expect(page.locator(".blog-ledger__main strong")).toHaveText("Updated after deployment"); await ready(page);
});

test("recovery copies can be downloaded, restored without overwriting, and explicitly cleared", async ({ page }) => {
  await page.goto(root); await ready(page);
  const save = page.locator("[data-filter-item] [data-favorite-toggle]").first();
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "true");
  const originalTitle = await page.locator("[data-filter-item] strong").first().innerText();
  const raw = await page.evaluate(() => {
    const key = "website:favorites:v1:/__site__/minimal-archive", backup = JSON.parse(localStorage.getItem(key)!);
    backup.entries[0].snapshots.en.title = "Old backup title";
    const raw = JSON.stringify(backup); localStorage.setItem(key + ":recovery:old", raw); return raw;
  });
  await save.click(); await expect(save).toHaveAttribute("aria-pressed", "false");
  await page.goto(root + "favorites/"); await ready(page);
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
