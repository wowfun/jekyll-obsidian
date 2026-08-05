import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const pages = [
  { name: "home", route: "/__site__/minimal/" },
  { name: "note", route: "/__site__/minimal/docs/Getting%20Started/" },
  { name: "syntax", route: "/__site__/minimal/docs/Syntax/" },
  { name: "404", route: "/__site__/minimal/404.html" }
] as const;

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: "light", reducedMotion: "reduce" });
  await page.addInitScript(() => localStorage.setItem("website:color-scheme", "light"));
});

for (const pageUnderTest of pages) {
  test(`${pageUnderTest.name} matches the production visual baseline`, async ({ page }) => {
    await page.goto(pageUnderTest.route);
    await expect(page.locator("main")).toBeVisible();
    await page.evaluate(() => document.fonts.ready);

    if (pageUnderTest.name === "syntax") {
      await expect(page.locator("[data-math-rendered]").first()).toBeVisible();
      await expect(page.locator("[data-mermaid-rendered]")).toBeVisible();
    }
    if (pageUnderTest.name === "home") {
      await expect(page.locator("[data-local-graph-section] [data-graph-view]"))
        .toHaveAttribute("data-graph-ready", "true");
    }

    await expect(page).toHaveScreenshot(`${pageUnderTest.name}.png`, {
      animations: "disabled",
      fullPage: true,
      maxDiffPixelRatio: 0.01
    });
  });
}

test("the production home has no detectable accessibility violations", async ({ page }) => {
  await page.goto("/__site__/minimal/");
  await page.evaluate(() => document.fonts.ready);
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});

test("local and complete graphs match their production visual baselines", async ({ page }) => {
  await page.goto("/__site__/minimal/docs/Getting%20Started/");
  if (await page.locator("[data-context-panel]").isHidden()) {
    await page.getByRole("button", { name: "Context" }).tap();
  }
  const localGraph = page.locator("[data-local-graph-section]");
  await expect(localGraph.locator("[data-graph-view]")).toHaveAttribute("data-graph-ready", "true");
  await expect(localGraph).toHaveScreenshot("local-graph.png", { animations: "disabled", maxDiffPixelRatio: 0.01 });

  await localGraph.getByRole("button", { name: "Open full graph" }).click();
  const fullGraph = page.locator('dialog[data-dialog="graph-global"]');
  await expect(fullGraph.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  await expect(fullGraph).toHaveScreenshot("full-graph-dialog.png", { animations: "disabled", maxDiffPixelRatio: 0.01 });
});

test.describe("production site without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  test("keeps the local graph fallback and mobile note context available", async ({ page }, testInfo) => {
    await page.goto("/__site__/minimal/docs/Syntax/");
    await expect(page.locator(".local-graph__fallback")).toBeVisible();
    await expect(page.locator("pre[lang='mermaid']")).toBeVisible();
    if (testInfo.project.name === "mobile-chromium") {
      await expect(page.getByRole("complementary", { name: "Page context" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "Backlinks" })).toBeVisible();
    }
  });
});
