import { test, expect } from "@playwright/test";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";

async function outputSizes(theme: string) {
  const root = path.resolve(`_site-browser-${theme}`);
  const entries = await readdir(root, { recursive: true, withFileTypes: true });
  const files = entries.filter((entry) => entry.isFile());
  const sizes = await Promise.all(files.map(async (entry) => {
    const absolute = path.join(entry.parentPath, entry.name);
    return { absolute, bytes: (await stat(absolute)).size };
  }));
  const html = sizes.filter((file) => file.absolute.endsWith(".html"));
  return {
    total: sizes.reduce((sum, file) => sum + file.bytes, 0),
    averageHtml: html.reduce((sum, file) => sum + file.bytes, 0) / html.length
  };
}

test("production theme outputs stay within site and average HTML budgets", async () => {
  for (const theme of ["minimal", "docs"] as const) {
    const sizes = await outputSizes(theme);
    expect(sizes.total, `${theme} site bytes`).toBeLessThan(10 * 1024 * 1024);
    expect(sizes.averageHtml, `${theme} average HTML bytes`).toBeLessThan(50 * 1024);
  }
});

for (const theme of ["minimal", "docs"] as const) {
  test(`${theme} matches its presentation baseline`, async ({ page }) => {
    await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
    await page.addInitScript(() =>
      localStorage.setItem("website:color-scheme", "light")
    );
    await page.goto(`/__site__/${theme}/`);
    await expect(page.locator("main")).toBeVisible();
    await page.evaluate(() => document.fonts.ready);

    await expect(page).toHaveScreenshot(`${theme}.png`, {
      animations: "disabled",
      fullPage: true,
      maxDiffPixelRatio: 0.01
    });
  });
}
