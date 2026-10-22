import { expect, test, type Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const themes = ["minimal", "docs"] as const;
const locales = ["en", "zh-CN"] as const;
const site = (theme: string, locale: string, route = "/") =>
  `/__site__/${theme}-back-to-top${locale === "en" ? "" : "/zh-CN"}${route}`;
const scrollDown = (page: Page) => page.evaluate(() =>
  window.scrollTo({ top: window.innerHeight + 100, behavior: "instant" }));

test("archive, favorites and not-found layouts include one initially hidden control", async ({ page }) => {
  for (const route of ["minimal-governance/", "minimal-governance/favorites/", "minimal-i18n/404.html", "docs-i18n/404.html"]) {
    await page.goto(`/__site__/${route}`);
    await expect(page.locator("[data-back-to-top]")).toHaveCount(1);
    await expect(page.locator("[data-back-to-top]")).toBeHidden();
  }
});

for (const theme of themes) {
  test(`${theme} keeps keyboard focus visible in forced colors`, async ({ page }) => {
    await page.emulateMedia({ forcedColors: "active", reducedMotion: "reduce" });
    await page.goto(site(theme, "en", "/docs/long/"));
    await page.keyboard.press("Tab");
    await scrollDown(page);
    const button = page.locator("[data-back-to-top]");
    await expect(button).toBeVisible();
    await button.focus();
    await expect(button).toBeFocused();
    await expect(button).toHaveCSS("outline-style", "solid");
    await button.press("Enter");
    const main = page.locator("#main-content");
    await expect(main).toBeFocused();
    await expect(main).toHaveCSS("outline-style", "solid");
    await expect(main).toHaveCSS("outline-width", "2px");
  });
  for (const locale of locales) {
    for (const route of ["/", "/posts/story/"]) {
      test(`${theme} ${locale} returns to top on ${route}`, async ({ page }) => {
        await page.goto(site(theme, locale, route));
        await expect(page.locator("html")).toHaveClass("js");
        const button = page.locator("[data-back-to-top]");
        const label = locale === "en" ? "Back to top" : "回到顶部";
        await expect(button).toHaveCount(1);
        await expect(button).toHaveAttribute("aria-label", label);
        await expect(button).toHaveAttribute("title", label);
        await expect(button).toBeHidden();
        await page.evaluate(() => window.scrollTo({ top: window.innerHeight, behavior: "instant" }));
        await expect(button).toBeHidden();
        await scrollDown(page);
        await expect(button).toBeVisible();
        await expect(button).toHaveAccessibleName(label);
        const before = await page.evaluate(() => ({ url: location.href, history: history.length }));
        await button.click();
        await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
        await expect(button).toBeHidden();
        await expect(page.locator("#main-content")).toBeFocused();
        expect(await page.evaluate(() => ({ url: location.href, history: history.length }))).toEqual(before);

        await page.emulateMedia({ reducedMotion: "reduce" });
        for (const key of ["Enter", "Space"]) {
          await scrollDown(page);
          await expect(button).toBeVisible();
          await button.focus();
          await button.press(key);
          await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
          await expect(button).toBeHidden();
          await expect(page.locator("#main-content")).toBeFocused();
        }
      });
    }

    test(`${theme} ${locale} refreshes the control through documentation navigation and history`, async ({ page }, testInfo) => {
      const longUrl = site(theme, locale, "/docs/long/");
      const shortUrl = site(theme, locale, "/docs/short/");
      await page.goto(`${longUrl}#section-60`);
      const button = page.locator("[data-back-to-top]");
      await expect(button).toBeVisible();
      await button.click();
      await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
      await expect(page).toHaveURL(`${longUrl}#section-60`);
      await page.locator(".site-header").evaluate((header) => header.setAttribute("data-shell-test", "preserved"));
      await expect(page.locator("[data-docs-navigation]").first()).toHaveAttribute("data-docs-navigation-ready", "true");
      if (testInfo.project.name === "mobile-chromium") {
        await page.locator('.mobile-toolbar [data-dialog-open="browse"]').click();
        await page.locator('dialog[data-dialog="browse"] .docs-tree--dialog a').filter({ hasText: "Short page" }).click();
      } else {
        await page.locator('[data-docs-navigation] a').filter({ hasText: "Short page" }).click();
      }
      await expect(page).toHaveURL(shortUrl);
      await expect(page.locator(".site-header")).toHaveAttribute("data-shell-test", "preserved");
      await expect(button).toHaveCount(1);
      await expect(button).toHaveAttribute("aria-label", locale === "en" ? "Back to top" : "回到顶部");
      await page.evaluate(() => window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "instant" }));
      await expect(button).toBeHidden();

      await page.goBack();
      await expect(page).toHaveURL(`${longUrl}#section-60`);
      await expect(button).toBeVisible();
      await button.click();
      await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
      await expect(button).toBeHidden();
      await page.goForward();
      await expect(page).toHaveURL(shortUrl);
      await expect(button).toHaveCount(1);
      await expect(button).toBeHidden();
      await expect(page.locator(".site-header")).toHaveAttribute("data-shell-test", "preserved");
    });
  }

  test(`${theme} uses the theme focus ring when returning to main content`, async ({ page }, testInfo) => {
    for (const scheme of ["light", "dark"] as const) for (const method of ["back-to-top", "skip-link"]) {
      await page.emulateMedia({ colorScheme: scheme });
      await page.goto(site(theme, "en", "/docs/long/"));
      await expect(page.locator("html")).toHaveAttribute("data-color-scheme", scheme);
      if (method === "back-to-top") {
        await scrollDown(page);
        const button = page.locator("[data-back-to-top]");
        await expect(button).toBeVisible();
        await button.focus();
        await button.press("Enter");
      } else {
        await page.keyboard.press("Tab");
        await expect(page.locator(".skip-link")).toBeFocused();
        await page.keyboard.press("Enter");
      }
      const main = page.locator("#main-content");
      await expect(main).toBeFocused();
      await expect(main).toHaveCSS("outline-style", "none");
      await expect(main).not.toHaveCSS("box-shadow", "none");
      if (method === "back-to-top") await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
      await page.screenshot({ path: testInfo.outputPath(`${theme}-${scheme}-${method}-focus.png`) });
    }
  });

  test(`${theme} places the visible control immediately after the skip link in keyboard order`, async ({ page }) => {
    await page.goto(site(theme, "en", "/docs/long/"));
    await page.keyboard.press("Tab");
    await expect(page.locator(".skip-link")).toBeFocused();
    await scrollDown(page);
    const button = page.locator("[data-back-to-top]");
    await expect(button).toBeVisible();
    await page.keyboard.press("Tab");
    await expect(button).toBeFocused();
    await page.keyboard.press("Enter");
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
    await expect(page.locator("#main-content")).toBeFocused();
  });

  test(`${theme} keeps translation notices clear of the control on narrow screens`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 360, height: 800 });
    await page.goto(`/__site__/${theme}-i18n/zh-CN/docs/Architecture/`);
    const notice = page.locator(".translation-fallback");
    await expect(notice).toBeVisible();
    // Keep the transient notice visible while checking responsive geometry.
    await notice.evaluate((element) => {
      for (const animation of element.getAnimations()) {
        animation.pause();
        animation.currentTime = 0;
      }
    });
    const button = page.locator("[data-back-to-top]");
    for (const width of [360, 320, 412]) {
      await page.setViewportSize({ width, height: 800 });
      await scrollDown(page);
      await expect(button).toBeVisible();
      await expect(notice).toBeVisible();
      const noticeBox = (await notice.boundingBox())!;
      const buttonBox = (await button.boundingBox())!;
      expect(noticeBox.x).toBeGreaterThanOrEqual(0);
      expect(noticeBox.x + noticeBox.width).toBeLessThanOrEqual(buttonBox.x - 8);
      const toolbarBox = (await page.locator(".mobile-toolbar").boundingBox())!;
      expect(noticeBox.y + noticeBox.height).toBeLessThan(toolbarBox.y);
    }
    await page.screenshot({ path: testInfo.outputPath(`${theme}-translation-notice.png`) });
  });

  test(`${theme} keeps the control clear of the toolbar and below modal dialogs`, async ({ page }, testInfo) => {
    await page.goto(site(theme, "en"));
    await scrollDown(page);
    const button = page.locator("[data-back-to-top]");
    await expect(button).toBeVisible();
    for (const scheme of ["light", "dark"] as const) {
      if (await page.locator("html").getAttribute("data-color-scheme") !== scheme) {
        const toggle = page.locator("[data-color-scheme-toggle]");
        // Keep header focus from starting a smooth scroll during geometry checks.
        await toggle.evaluate(element => (element as HTMLElement).focus({ preventScroll: true }));
        await page.keyboard.press("Enter");
      }
      await expect(page.locator("html")).toHaveAttribute("data-color-scheme", scheme);
      await scrollDown(page);
      await expect(button).toBeVisible();
      await button.focus();
      const geometry = await button.evaluate((element) => {
        const box = element.getBoundingClientRect();
        const toolbar = document.querySelector(".mobile-toolbar")!.getBoundingClientRect();
        return {
          width: box.width, height: box.height, top: box.top, bottom: box.bottom, right: box.right,
          viewportWidth: innerWidth, viewportHeight: innerHeight,
          toolbarTop: toolbar.height ? toolbar.top : null,
          outline: getComputedStyle(element).outlineStyle
        };
      });
      expect(geometry.width).toBeGreaterThanOrEqual(44);
      expect(geometry.height).toBeGreaterThanOrEqual(44);
      expect(geometry.top).toBeGreaterThan(0);
      expect(geometry.right).toBeLessThan(geometry.viewportWidth);
      expect(geometry.bottom).toBeLessThan(geometry.toolbarTop ?? geometry.viewportHeight);
      expect(geometry.outline).toBe("solid");
      expect((await new AxeBuilder({ page }).include("[data-back-to-top]").analyze()).violations).toEqual([]);
      await page.screenshot({ path: testInfo.outputPath(`${theme}-${scheme}.png`) });
    }
    const dialogs = testInfo.project.name === "mobile-chromium" ? ["search", "context"] : ["search"];
    for (const kind of dialogs) {
      if (kind === "search") await page.keyboard.press("ControlOrMeta+k");
      else await page.locator('.mobile-toolbar [data-dialog-open="context"]').click();
      const dialog = page.locator(`dialog[data-dialog="${kind}"]`);
      await expect(dialog).toBeVisible();
      const modalOwnsHit = await button.evaluate((element) => {
        const box = element.getBoundingClientRect();
        return Boolean(document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2)?.closest("dialog"));
      });
      expect(modalOwnsHit).toBe(true);
      await page.keyboard.press("Escape");
      await expect(dialog).toBeHidden();
    }
  });

  test(`${theme} hides an exposed button in print and restores it on screen`, async ({ page }) => {
    await page.goto(site(theme, "en", "/docs/long/"));
    const button = page.locator("[data-back-to-top]");
    await scrollDown(page);
    await expect(button).toBeVisible();

    await page.emulateMedia({ media: "print" });
    await scrollDown(page);
    // Keep the scroll controller's visibility condition true: print CSS must
    // hide the button independently of the initial hidden attribute.
    await expect(button).not.toHaveAttribute("hidden");
    await expect(button).toBeHidden();

    await page.emulateMedia({ media: "screen" });
    await scrollDown(page);
    await expect(button).toBeVisible();
    await button.click();
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0);
  });

  test(`${theme} leaves the button hidden without JavaScript`, async ({ browser, baseURL }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    try {
      const page = await context.newPage();
      await page.goto(new URL(site(theme, "en", "/docs/long/"), baseURL).href);
      await page.keyboard.press("End");
      await expect(page.locator("[data-back-to-top]")).toBeHidden();
      await expect(page.locator("[data-back-to-top]")).toHaveAttribute("hidden", "");
    } finally {
      await context.close();
    }
  });
}
