import { expandArchiveDays } from "./archive-helpers";
import { expect, test, type Page } from "@playwright/test";

const ready = async (page: Page) => {
  await expect(page.locator("[data-paged-archive]")).not.toHaveAttribute("aria-busy", "true");
  await expect(page.locator("[data-archive-page-status]")).not.toBeEmpty();
};

for (const locale of ["en", "zh-CN"]) {
  const root = "/__site__/minimal-archive/" + (locale === "en" ? "" : locale + "/");
  test(`collection actions share the first row only when there is no introduction in ${locale}`, async ({ page }) => {
    await page.goto(root + "plain/");
    await expect(page.locator(".minimal-entry--compact-collection")).toHaveCount(1);
    await expect(page.locator("h1.visually-hidden strong")).toHaveText("Collect");
    for (const direction of ["ltr", "rtl"]) {
      await page.locator("html").evaluate((element, value) => element.setAttribute("dir", value), direction);
      const geometry = await page.locator(".tab-collection h2").evaluate(element => {
        const action = document.querySelector("[data-page-actions]")!.getBoundingClientRect();
        const range = document.createRange(); range.selectNodeContents(element);
        return { titleY: element.getBoundingClientRect().y, actionY: action.y,
          overlap: [...range.getClientRects()].some(line => line.width > 0 && line.left < action.right && line.right > action.left && line.top < action.bottom && line.bottom > action.top),
          overflow: document.documentElement.scrollWidth > innerWidth + 1 };
      });
      expect(geometry.titleY).toBeCloseTo(geometry.actionY, 0);
      expect(geometry.overlap).toBe(false);
      expect(geometry.overflow).toBe(false);
    }
    await page.goto(root + "plain-intro/");
    await expect(page.locator(".minimal-entry--compact-collection")).toHaveCount(0);
    await expect(page.locator(".note-content > p")).toHaveText("An authored introduction.");
  });
  test(`custom archive intersects topics and dates within its own tab in ${locale}`, async ({ page }, testInfo) => {
    await page.goto(root + "news/"); await ready(page);
    const titles = page.locator(".blog-ledger__main strong");
    await expect(titles).toHaveText(["Newest", "Oldest"]);
    await expect(page.locator(".archive-day[open]")).toHaveCount(1);
    await expect(page.locator(".archive-day summary h2")).toHaveText(locale === "en" ? ["October 10", "December 31, 2025"] : ["10月10日", "2025年12月31日"]);
    await expect(page.locator("main h1")).toHaveClass("visually-hidden");
    await expect(page.locator(".tab-collection")).toHaveCount(0);
    await expect(page.locator("[data-paged-archive]")).toHaveAttribute("data-archive-current-url", /\/archive\/tabs\/news\/current\.json$/);
    await expect(page.locator('button[data-archive-facet="topic"][data-archive-value="tools"]')).toHaveCount(0);
    await expect(page.locator('a[data-day-filter-option][data-filter-day="2025-12-31"]')).toHaveAttribute("href", root + "news/?day=2025-12-31");
    await expect(page.locator('a[data-archive-facet="topic"]').first()).toHaveAttribute("href", root + "news/?topic=agents");
    await page.locator('button[data-archive-facet="topic"][data-archive-value="agents"]').click(); await ready(page);
    if (testInfo.project.name.includes("mobile")) await page.locator('[data-dialog-open="context"]').click();
    await page.locator('[data-day-filter-option][data-filter-day="2025-12-31"]').click();
    if (testInfo.project.name.includes("mobile")) await page.keyboard.press("Escape");
    await ready(page);
    await expect(titles).toHaveText(["Oldest"]);
    expect(new URL(page.url()).searchParams.get("topic")).toBe("agents");
    expect(new URL(page.url()).searchParams.get("day")).toBe("2025-12-31");
    await page.reload(); await ready(page); await expect(titles).toHaveText(["Oldest"]);
    await page.goBack(); await ready(page); await expect(titles).toHaveText(["Newest", "Oldest"]);
    await page.goForward(); await ready(page); await expect(titles).toHaveText(["Oldest"]);
    // A deployment refresh must keep the tab's own manifest rather than use the home index.
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true })));
    await ready(page); await expect(titles).toHaveText(["Oldest"]);
    await page.goto(root + "tools/"); await ready(page); await expect(titles).toHaveText(["Middle"]);
    await expect(page.locator('button[data-archive-facet="topic"][data-archive-value="agents"]')).toHaveCount(0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  });

  test(`favorites combine topic and time filters in ${locale}`, async ({ page }, testInfo) => {
    await page.goto(root); await ready(page);
    await expandArchiveDays(page);
    for (const button of await page.locator("[data-filter-item] [data-favorite-toggle]").all()) {
      await button.click(); await expect(button).toHaveAttribute("aria-pressed", "true");
    }
    await page.locator('[data-archive-page="next"]').click(); await ready(page);
    await page.locator("[data-filter-item] [data-favorite-toggle]").click();
    await expect(page.locator("[data-filter-item] [data-favorite-toggle]")).toHaveAttribute("aria-pressed", "true");
    await page.goto(root + "favorites/"); await ready(page);
    await expect(page.locator(".archive-day")).toHaveCount(3);
    await expect(page.locator(".archive-day[open]")).toHaveCount(1);
    await page.locator('button[data-archive-facet="topic"][data-archive-value="agents"]').click(); await ready(page);
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["Newest", "Oldest"]);
    if (testInfo.project.name.includes("mobile")) await page.locator('[data-dialog-open="context"]').click();
    await page.locator('[data-day-filter-option][data-filter-day="2025-12-31"]').click();
    if (testInfo.project.name.includes("mobile")) await page.keyboard.press("Escape");
    await ready(page);
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["Oldest"]);
    await page.reload(); await ready(page);
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["Oldest"]);
  });
}
