import { test, expect } from "@playwright/test";

for (const theme of ["blog", "docs", "digital-garden"] as const) {
  test(`${theme} matches its presentation baseline`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
    await page.addInitScript(() =>
      localStorage.setItem("jekyll-obsidian:color-scheme", "light")
    );
    await page.goto(`/__fixture__/${theme}/`);
    await expect(page.locator("main")).toBeVisible();
    await page.evaluate(() => document.fonts.ready);

    await expect(page).toHaveScreenshot(`${theme}.png`, {
      animations: "disabled",
      fullPage: true,
      maxDiffPixelRatio: 0.01
    });
  });
}
