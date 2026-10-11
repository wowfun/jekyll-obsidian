import { expect, test } from "@playwright/test";

const themes = ["minimal", "docs"] as const;
const locales = ["en", "zh-CN"] as const;
const longName = "long_property_name_without_any_word_boundary_to_check_wrapping";

function route(theme: string, locale: string) {
  return "/__site__/" + theme + "-properties/" + (locale === "en" ? "" : locale + "/");
}

for (const theme of themes) {
  for (const locale of locales) {
    test(theme + " localized property layout and navigation in " + locale, async ({ page }, testInfo) => {
      const root = route(theme, locale);
      await page.goto(root + "properties/");
      const fields = page.locator("[data-note-properties]");
      const value = (name: string) => fields.locator('[data-property-name="' + name + '"] dd');
      await expect(fields).toBeVisible();
      await expect(fields).toHaveAttribute("lang", locale);
      // Compiler and Jekyll integration tests own the value/type and escaping table.
      await expect(page.locator(".note-source-url a")).toHaveAttribute("href", "https://example.test/original");
      await expect(page.locator(".note-header .tag-chip").first()).toBeVisible();
      expect(await page.evaluate(() => {
        const tags = document.querySelector(".note-header .tag-chip")!;
        const source = document.querySelector(".note-source-url")!;
        const properties = document.querySelector("[data-note-properties]")!;
        const body = document.querySelector(".note-content")!;
        const precedes = (a: Element, b: Element) => Boolean(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
        return precedes(tags, source) && precedes(source, properties) && precedes(properties, body);
      })).toBe(true);
      const screenshot = testInfo.outputPath("properties.png");
      await page.screenshot({ path: screenshot, fullPage: true });
      await testInfo.attach("properties", { path: screenshot, contentType: "image/png" });
      await expect(value("project").locator("a")).toHaveAttribute("href", root + "#%E4%BD%A0%E5%A5%BD-%E4%B8%96%E7%95%8C");
      await value("project").locator("a").click();
      await expect(page.locator(".note-content h2[id='你好-世界']")).toBeVisible();
      await expect(page.locator(".note-content")).toContainText(locale === "en" ? "Target marker." : "目标正文。");
    });
  }

  test(theme + " property layout at responsive boundaries", async ({ page }, testInfo) => {
    for (const width of [320, 520, 521, 600]) {
      await page.setViewportSize({ width, height: 1000 });
      await page.goto(route(theme, "en") + "properties/");
      await expect(page.locator("[data-note-properties]")).toBeVisible();
      const layout = await page.locator('[data-property-name="' + longName + '"]').evaluate(row => {
        const label = row.querySelector("dt")!.getBoundingClientRect();
        const value = row.querySelector("dd")!.getBoundingClientRect();
        return {
          stacked: value.top >= label.bottom,
          width: document.documentElement.scrollWidth,
          viewport: window.innerWidth,
          valueRight: value.right
        };
      });
      expect(layout.stacked).toBe(width <= 520);
      expect(layout.width).toBeLessThanOrEqual(layout.viewport);
      expect(layout.valueRight).toBeLessThanOrEqual(layout.viewport);
      const screenshot = testInfo.outputPath("width-" + width + ".png");
      await page.screenshot({ path: screenshot, fullPage: true });
      await testInfo.attach("width-" + width, { path: screenshot, contentType: "image/png" });
    }
  });
}

test.describe("server-rendered properties", () => {
  test.use({ javaScriptEnabled: false });
  for (const theme of themes) {
    for (const locale of locales) {
      test(theme + " without JavaScript in " + locale, async ({ page }) => {
        await page.goto(route(theme, locale) + "properties/");
        const fields = page.locator("[data-note-properties]");
        await expect(fields).toBeVisible();
        await expect(fields.locator('[data-property-name="nothing"] dd')).toHaveText("[]");
        await fields.locator('[data-property-name="project"] a').click();
        await expect(page.locator(".note-content h2[id='你好-世界']")).toBeVisible();
        await expect(page.locator(".note-content")).toContainText(locale === "en" ? "Target marker." : "目标正文。");
      });
    }
  }
});
