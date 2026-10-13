import { test, expect } from "@playwright/test";

const base = "/__site__/minimal-archive/";
const ready = async (page: import("@playwright/test").Page) => {
  await expect(page.locator("[data-paged-archive]")).not.toHaveAttribute("aria-busy", "true");
  await expect(page.locator("[data-archive-page-status]")).not.toBeEmpty();
};
for (const locale of ["en", "zh-CN"]) {
  const root = base + (locale === "en" ? "" : locale + "/");
  test(`favorites persist across archive, article, locales and browser navigation in ${locale}`, async ({ page, context }) => {
    await page.goto(root); await ready(page);
    await expect(page.locator("[data-filter-list] > section > h2")).toHaveText(["2026-10-10", "2026-10-09"]);
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
