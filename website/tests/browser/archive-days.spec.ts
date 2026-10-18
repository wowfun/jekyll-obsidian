import { expect, test } from "@playwright/test";
import { archiveReady as ready } from "./archive-helpers";

const base = "/__site__/minimal-archive/";
for (const locale of ["en", "zh-CN"]) {
  const root = base + (locale === "en" ? "" : "zh-CN/");
  test(`date presentation metadata belongs to archive pages in ${locale}`, async ({ page }) => {
    await page.goto(root); await ready(page);
    await expect(page.locator("main")).toHaveAttribute("data-ledger-current-year", /\d{4}/);
    await expect(page.locator("[data-ledger-day-ui]")).toHaveCount(1);
    await page.goto(root + "items/a/");
    await expect(page.locator("main")).not.toHaveAttribute("data-ledger-current-year");
    await expect(page.locator("main")).not.toHaveAttribute("data-ledger-group-by");
    await expect(page.locator("[data-ledger-day-ui]")).toHaveCount(0);
  });

  test(`day disclosures retain choices through filters, pagination and history in ${locale}`, async ({ page }) => {
    await page.goto(root); await ready(page);
    const newest = page.locator('[data-ledger-day="2026-10-10"]');
    const middle = page.locator('[data-ledger-day="2026-10-09"]');
    await expect(newest).toHaveAttribute("open", ""); await expect(middle).not.toHaveAttribute("open");
    await expect(newest.locator("summary")).toContainText(locale === "en" ? "Saturday" : "星期六");
    await expect(newest.locator("[data-ledger-day-count]")).toHaveText(locale === "en" ? "1 entry" : "1 条");
    await middle.locator("summary").press("Enter"); await expect(middle).toHaveAttribute("open", "");
    await newest.locator("summary").press("Space"); await expect(newest).not.toHaveAttribute("open");
    await page.locator('[data-archive-page="next"]').click(); await ready(page);
    await expect(page.locator('[data-ledger-day="2025-12-31"]')).toHaveAttribute("open", "");
    await expect(page.locator(".archive-day summary h2")).toContainText("2025");
    await page.goBack(); await ready(page);
    await expect(newest).not.toHaveAttribute("open"); await expect(middle).toHaveAttribute("open", "");
    await page.locator('button[data-archive-facet="topic"][data-archive-value="tools"]').click(); await ready(page);
    await expect(middle).toHaveAttribute("open", "");
    await page.goBack(); await ready(page); await expect(newest).not.toHaveAttribute("open");
    await page.goForward(); await ready(page); await expect(middle).toHaveAttribute("open", "");
    await page.goto(root); await ready(page);
    await expect(newest).toHaveAttribute("open", ""); await expect(middle).not.toHaveAttribute("open");
    await newest.locator("summary").click(); await page.reload(); await ready(page);
    await expect(newest).toHaveAttribute("open", "");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  });

  test(`closed days defer reading and retain loaded bodies when reopened in ${locale}`, async ({ page }) => {
    const requests: string[] = [];
    page.on("request", request => { if (/\/items\/[ab]\/$/.test(request.url())) requests.push(request.url()); });
    await page.goto(root); await ready(page);
    await page.locator("[data-archive-reading-toggle]").click();
    await expect(page.locator("[data-reading-loaded]")).toHaveCount(1);
    const middle = page.locator('[data-ledger-day="2026-10-09"]');
    await expect(middle.locator(".archive-reading__body")).toHaveCount(0);
    await middle.locator("summary").click();
    await expect(page.locator("[data-reading-loaded]")).toHaveCount(2);
    await middle.locator("summary").click(); await expect(middle.locator(".archive-reading__body")).toBeHidden();
    await middle.locator("summary").click(); await expect(middle.locator(".archive-reading__body")).toBeVisible();
    expect(requests).toHaveLength(2);
  });

  test(`static days remain localized and operable without JavaScript in ${locale}`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ baseURL: baseURL!, javaScriptEnabled: false, timezoneId: "America/Los_Angeles" });
    try {
      const page = await context.newPage(); await page.goto(root);
      const groups = page.locator("details[data-ledger-day]");
      await expect(groups).toHaveCount(2);
      await expect(groups.first()).toHaveAttribute("open", ""); await expect(groups.last()).not.toHaveAttribute("open");
      await expect(groups.first().locator("summary")).toContainText(locale === "en" ? "Saturday" : "星期六");
      await expect(groups.first().locator("h2")).toHaveText(locale === "en" ? "October 10" : "10月10日");
      await groups.last().locator("summary").press("Enter"); await expect(groups.last().locator("[data-filter-item]")).toBeVisible();
    } finally { await context.close(); }
  });

  test(`same-day counts describe only each page in ${locale}`, async ({ page }) => {
    await page.goto("/__site__/minimal-export/" + (locale === "en" ? "" : "zh-CN/") + "?day=2026-10-09"); await ready(page);
    const group = page.locator('[data-ledger-day="2026-10-09"]');
    await expect(group.locator("[data-ledger-day-count]")).toHaveText(locale === "en" ? "2 entries" : "2 条");
    await group.locator("summary").click();
    await page.locator('[data-archive-page="next"]').click(); await ready(page);
    await expect(group).not.toHaveAttribute("open");
    await expect(group.locator("[data-ledger-day-count]")).toHaveText(locale === "en" ? "2 entries" : "2 条");
  });
}
