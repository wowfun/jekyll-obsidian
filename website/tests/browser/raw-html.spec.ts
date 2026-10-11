import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test.beforeEach(async ({ page }) => {
  // Optional remote fonts must not hold up route, interaction, and accessibility checks.
  await page.route("https://fonts.googleapis.com/**", (route) =>
    route.fulfill({ contentType: "text/css", body: "" }));
});

for (const theme of ["minimal", "docs"] as const) {
  test(`${theme} serves the shared raw HTML slide bundle at its baseurl-aware route`, async ({ page }) => {
    await page.goto(`/__site__/${theme}/slides/jekyll-obsidian/`);

    await expect(page.getByRole("heading", { name: /把写作，.*直接变成网站。/ })).toBeVisible();
    await expect(page.locator("#currentSlide")).toHaveText("1");
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#currentSlide")).toHaveText("2");
    await expect(page).toHaveURL(new RegExp(`/__site__/${theme}/slides/jekyll-obsidian/#slide-2$`));

    await page.keyboard.press("End");
    await expect(page.locator("#currentSlide")).toHaveText("15");
    const gettingStarted = page.getByRole("link", { name: /继续阅读快速开始/ });
    await expect(gettingStarted).toHaveAttribute("href", "../../docs/Getting%20Started/");
    expect(await gettingStarted.evaluate((link) => (link as HTMLAnchorElement).href))
      .toContain(`/__site__/${theme}/docs/Getting%20Started/`);
    expect(await page.evaluate(() => document.documentElement.scrollWidth))
      .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));
    // A visible slide can still contain translucent text during its staggered reveal.
    await expect.poll(() => page.locator("#slide-15 .reveal").evaluateAll((elements) =>
      elements.every((element) => getComputedStyle(element).opacity === "1")))
      .toBe(true);
    expect((await new AxeBuilder({ page }).analyze()).violations).toEqual([]);
  });
}
