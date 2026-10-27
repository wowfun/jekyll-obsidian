import { expect, test } from "@playwright/test";

const themes = ["minimal", "docs"] as const;
// These existing fixtures contain long/short documents and a long post in both locales.
const site = (theme: string, route: string, locale = "en") =>
  `/__site__/${theme}-back-to-top${locale === "en" ? "" : `/${locale}`}${route}`;

for (const theme of themes) {
  for (const locale of ["en", "zh-CN"]) {
    test(`${theme} ${locale} shows reading time only on long bodies`, async ({ page }) => {
      for (const route of ["/docs/long/", "/posts/story/"]) {
        await page.goto(site(theme, route, locale));
        const hint = page.locator(".note-meta .note-reading-time");
        await expect(hint).toHaveCount(1);
        await expect(hint).toBeVisible();
        await expect(hint).toHaveText(locale === "en" ? "About 5 min read" : "约 5 分钟阅读");
        await expect(hint).toHaveAttribute("lang", locale);
        await expect(page.locator("main h1")).toHaveCount(1);
        const geometry = await hint.evaluate((element) => {
          const rect = element.getBoundingClientRect();
          const actions = document.querySelector("[data-page-actions]")!.getBoundingClientRect();
          return {
            withinViewport: rect.left >= 0 && rect.right <= window.innerWidth,
            overlapsActions: rect.left < actions.right && rect.right > actions.left
              && rect.top < actions.bottom && rect.bottom > actions.top
          };
        });
        expect(geometry).toEqual({ withinViewport: true, overlapsActions: false });
      }
      for (const route of ["/", "/docs/short/", "/404.html"]) {
        await page.goto(site(theme, route, locale));
        await expect(page.locator(".note-reading-time")).toHaveCount(0);
      }
    });
  }

  test(`${theme} reading time fits RTL metadata`, async ({ page }, testInfo) => {
    await page.goto(site(theme, "/docs/long/", "ar"));
    const hint = page.locator(".note-reading-time");
    await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
    await expect(hint).toHaveAttribute("lang", "ar");
    await expect(hint).toHaveText("حوالي 5 دقائق للقراءة");
    await expect(hint).toBeVisible();
    await expect(hint).toHaveCSS("direction", "rtl");
    const bounds = await hint.boundingBox();
    expect(bounds!.x).toBeGreaterThanOrEqual(0);
    expect(bounds!.x + bounds!.width).toBeLessThanOrEqual(page.viewportSize()!.width);
    await page.locator(".note-header").screenshot({ path: testInfo.outputPath("reading-time-ar.png") });
  });

  test(`${theme} reading time fallback preserves English language in an RTL interface`, async ({ page }, testInfo) => {
    await page.goto(site(theme, "/docs/long/", "fa"));
    const hint = page.locator(".note-reading-time");
    await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
    await expect(hint).toHaveAttribute("lang", "en");
    await expect(hint).toHaveAttribute("dir", "ltr");
    await expect(hint).toHaveText("About 5 min read");
    await expect(hint).toHaveCSS("text-transform", "none");
    await expect(hint).toHaveCSS("letter-spacing", "normal");
    await page.locator(".note-header").screenshot({ path: testInfo.outputPath("reading-time-fallback.png") });
  });

  test(`${theme} refreshes reading time with document navigation and history`, async ({ page }, testInfo) => {
    const longUrl = site(theme, "/docs/long/");
    const shortUrl = site(theme, "/docs/short/");
    await page.goto(longUrl);
    await expect(page.locator(".note-reading-time")).toHaveCount(1);
    await expect(page.locator("[data-docs-navigation]").first()).toHaveAttribute("data-docs-navigation-ready", "true");
    await page.locator(".site-header").evaluate((header) => header.setAttribute("data-shell-test", "preserved"));
    if (testInfo.project.name === "mobile-chromium") {
      await page.locator('.mobile-toolbar [data-dialog-open="browse"]').click();
      await page.locator('dialog[data-dialog="browse"] .docs-tree--dialog a').filter({ hasText: "Short page" }).click();
    } else {
      await page.locator('[data-docs-navigation] a').filter({ hasText: "Short page" }).click();
    }
    await expect(page).toHaveURL(shortUrl);
    await expect(page.locator(".note-reading-time")).toHaveCount(0);
    await expect(page.locator(".site-header")).toHaveAttribute("data-shell-test", "preserved");
    await page.goBack();
    await expect(page).toHaveURL(longUrl);
    await expect(page.locator(".note-reading-time")).toHaveCount(1);
    await expect(page.locator(".site-header")).toHaveAttribute("data-shell-test", "preserved");
    await page.goForward();
    await expect(page).toHaveURL(shortUrl);
    await expect(page.locator(".note-reading-time")).toHaveCount(0);
  });
}

test.describe("reading time without JavaScript", () => {
  test.use({ javaScriptEnabled: false });
  for (const theme of themes) {
    test(`${theme} serves the hint in HTML`, async ({ page }) => {
      await page.goto(site(theme, "/docs/long/", "zh-CN"));
      await expect(page.locator(".note-reading-time")).toHaveText("约 5 分钟阅读");
      await expect(page.locator(".note-reading-time")).toBeVisible();
      await page.goto(site(theme, "/docs/short/", "zh-CN"));
      await expect(page.locator(".note-reading-time")).toHaveCount(0);
    });
  }
});
