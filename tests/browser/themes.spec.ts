import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

for (const theme of ["blog", "docs", "digital-garden"] as const) {
  test(`${theme} exposes its own accessible presentation`, async ({ page }) => {
    await page.goto(`/__fixture__/${theme}/`);
    await expect(page.locator("body")).toHaveClass(new RegExp(`theme-${theme}`));
    await expect(page.locator("main")).toBeVisible();
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
}

test("blog reads as a dated publishing ledger", async ({ page }) => {
  await page.goto("/__fixture__/blog/");
  await expect(page.getByRole("heading", { name: "Field dispatches" })).toBeVisible();
  await expect(page.locator(".blog-ledger time").first()).toHaveAttribute("datetime", "2026-07-31");
  await expect(page.getByRole("link", { name: "Browse the archive" })).toBeVisible();
});

test("docs exposes its handbook navigation and reading sequence", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop navigation assertion");
  await page.goto("/__fixture__/docs/");
  await expect(page.getByRole("navigation", { name: "Documentation", exact: true })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Breadcrumb" })).toContainText("Guides");
  await expect(page.getByRole("navigation", { name: "Documentation sequence" })).toContainText(
    "Syntax reference"
  );
});

test("docs breadcrumb marks only its final non-link item as current", async ({ page }) => {
  await page.goto("/__fixture__/docs/");
  const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
  const current = breadcrumb.locator('[aria-current="page"]');
  await expect(current).toHaveCount(1);
  await expect(current).not.toHaveJSProperty("tagName", "A");
  await expect(breadcrumb.locator('a[href="/docs/getting-started/"]')).toHaveCount(0);
});

test("docs puts browse and outline into mobile sheets", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile interaction assertion");
  await page.goto("/__fixture__/docs/");
  await expect(page.locator(".docs-sidebar")).toBeHidden();
  await expect(page.locator(".docs-context")).toBeHidden();
  await page.getByRole("button", { name: "On this page" }).tap();
  const dialog = page.locator('dialog[data-dialog="context"]');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("link", { name: "First build" })).toBeVisible();
});

test("digital garden keeps the annotated folio and relation rail", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop layout assertion");
  await page.goto("/__fixture__/digital-garden/");
  await expect(page.locator(".note-folio")).toBeVisible();
  const rail = page.locator(".relation-rail");
  await expect(rail).toBeVisible();
  expect(Math.round((await rail.boundingBox())?.width ?? 0)).toBe(288);
});

test("search loads on demand and finds CJK text", async ({ page }) => {
  await page.goto("/__fixture__/digital-garden/");
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await expect(dialog).toBeVisible();
  await dialog.locator("input").fill("花园");
  await expect(dialog.getByRole("link", { name: /中文搜索/ })).toBeVisible();
});

test("digital garden previews use catalog text without active content", async ({ page }) => {
  await page.goto("/__fixture__/digital-garden/");
  await page.locator(".obsidian-link[data-note-id='notes/中文搜索.md']").focus();
  const preview = page.locator("[data-note-preview]");
  await expect(preview).toContainText("中文搜索");
  await expect(preview).toContainText("中文内容使用稳定的单字和双字索引。");
  await expect(preview.locator("iframe, script")).toHaveCount(0);
});

test("color scheme state uses the neutral public contract", async ({ page }) => {
  await page.goto("/__fixture__/blog/");
  await page.locator("[data-color-scheme-toggle]").click();
  await expect(page.locator("html")).toHaveAttribute("data-color-scheme", /light|dark/);
  expect(
    await page.evaluate(() => localStorage.getItem("jekyll-obsidian:color-scheme"))
  ).toMatch(/light|dark/);
  expect(await page.evaluate(() => localStorage.getItem("garden-theme"))).toBeNull();
});

test("every theme follows dark preference and supports an explicit light override", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(() => localStorage.removeItem("jekyll-obsidian:color-scheme"));
  for (const theme of ["blog", "docs", "digital-garden"] as const) {
    await page.goto(`/__fixture__/${theme}/`);
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "dark");
    await page.locator("[data-color-scheme-toggle]").click();
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
  }
});

test("enabled taxonomy, graph, and feed routes stay discoverable once per theme", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop primary navigation assertion");
  for (const theme of ["blog", "docs", "digital-garden"] as const) {
    await page.goto(`/__fixture__/features/${theme}/navigation/`);
    const primary = page.getByRole("navigation", { name: "Primary navigation" });
    for (const route of ["/tags/", "/graph/", "/feed.xml"] as const) {
      await expect(primary.locator(`a[href="${route}"]`)).toHaveCount(1);
    }
    await expect(page.locator('head link[rel="alternate"][type="application/atom+xml"]'))
      .toHaveAttribute("href", "/feed.xml");
  }
});

test("docs Browse keeps enabled feature routes beside the documentation tree", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile browse assertion");
  await page.goto("/__fixture__/features/docs/navigation/");
  await page.getByRole("button", { name: "Browse" }).tap();
  const dialog = page.locator('dialog[data-dialog="browse"]');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("navigation", { name: "Documentation" })).toBeVisible();
  for (const route of ["/tags/", "/graph/", "/feed.xml"] as const) {
    await expect(dialog.locator(`a[href="${route}"]`)).toHaveCount(1);
  }
});

test("search-disabled pages leave Cmd/Ctrl-K to the browser", async ({ page }) => {
  const searchRequests: string[] = [];
  page.on("request", (request) => {
    if (/\/search-[^/]+\.js$/.test(new URL(request.url()).pathname)) {
      searchRequests.push(request.url());
    }
  });
  await page.goto("/__fixture__/features/blog/none/");
  const prevented = await page.evaluate(() => {
    const event = new KeyboardEvent("keydown", {
      key: "k",
      ctrlKey: true,
      bubbles: true,
      cancelable: true
    });
    document.dispatchEvent(event);
    return event.defaultPrevented;
  });
  expect(prevented).toBe(false);
  await page.waitForTimeout(50);
  expect(searchRequests).toEqual([]);
});

test("docs home follows its authored introduction with a compact handbook index", async ({ page }) => {
  await page.goto("/__fixture__/home/docs/");
  const article = page.locator("main > article");
  const browse = page.locator("main > .docs-home-browse");
  await expect(article).toContainText("This authored introduction remains first");
  await expect(browse.getByRole("heading", { name: "Browse the handbook" })).toBeVisible();
  await expect(browse.getByRole("link", { name: "Getting started" })).toBeVisible();
  await expect(page.locator("main > article + .docs-home-browse")).toHaveCount(1);
});

test("digital garden home follows authored content with server-rendered ways to explore", async ({ page }) => {
  await page.goto("/__fixture__/home/digital-garden/");
  const article = page.locator("main > article");
  const overview = page.locator("main > .garden-home-overview");
  await expect(article).toContainText("This authored introduction remains first");
  await expect(overview.getByRole("heading", { name: "Explore the garden" })).toBeVisible();
  for (const route of ["/notes/", "/tags/", "/graph/"] as const) {
    await expect(overview.locator(`a[href="${route}"]`)).toHaveCount(1);
  }
  await expect(page.locator("main > article + .garden-home-overview")).toHaveCount(1);
});

test("frontend identifiers are neutral outside the garden visual shell", async ({ page }) => {
  await page.goto("/__fixture__/digital-garden/");
  await expect(page.locator("meta[name^='obsidian:']")).toHaveCount(4);
  await expect(page.locator("[data-garden-dialog], .garden-dialog, .garden-link, .garden-embed"))
    .toHaveCount(0);
  await expect(page.locator(".obsidian-link")).toBeVisible();
  await expect(page.locator(".obsidian-embed")).toBeVisible();
});

for (const fixture of [
  { theme: "blog", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "blog", feature: "relations", visible: "Backlinks", hidden: "On this page" },
  { theme: "docs", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "docs", feature: "relations", visible: "Backlinks", hidden: "On this page" },
  { theme: "digital-garden", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "digital-garden", feature: "relations", visible: "Backlinks", hidden: "On this page" }
] as const) {
  test(`${fixture.theme} renders ${fixture.feature} independently`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop server-rendered panel assertion");
    await page.goto(`/__fixture__/features/${fixture.theme}/${fixture.feature}/`);
    const panel = page.locator("[data-context-panel]");
    await expect(panel).toBeVisible();
    await expect(panel.getByRole("heading", { name: fixture.visible })).toBeVisible();
    await expect(panel.getByRole("heading", { name: fixture.hidden })).toHaveCount(0);
  });
}

test("all themes remove context UI when outline and relations are disabled", async ({ page }) => {
  for (const theme of ["blog", "docs", "digital-garden"] as const) {
    await page.goto(`/__fixture__/features/${theme}/none/`);
    await expect(page.locator("[data-context-panel]")).toHaveCount(0);
    await expect(page.locator('[data-dialog="context"]')).toHaveCount(0);
    await expect(page.getByRole("button", { name: /Context|On this page/ })).toHaveCount(0);
  }
});

test("non-default context features remain available in mobile sheets", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile interaction assertion");
  for (const [theme, feature, heading] of [
    ["blog", "outline", "On this page"],
    ["blog", "relations", "Backlinks"],
    ["docs", "outline", "On this page"],
    ["docs", "relations", "Backlinks"],
    ["digital-garden", "outline", "On this page"],
    ["digital-garden", "relations", "Backlinks"]
  ] as const) {
    await page.goto(`/__fixture__/features/${theme}/${feature}/`);
    await expect(page.locator("[data-context-panel]")).toBeHidden();
    await page.getByRole("button", { name: feature === "outline" ? "On this page" : "Context" }).tap();
    const dialog = page.locator('dialog[data-dialog="context"]');
    await expect(dialog).toBeVisible();
    await expect(
      dialog.locator(".relation-section__title").filter({ hasText: heading })
    ).toBeVisible();
  }
});

test.describe("without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  for (const theme of ["blog", "docs", "digital-garden"] as const) {
    test(`${theme} retains authored content and navigation`, async ({ page }) => {
      await page.goto(`/__fixture__/${theme}/`);
      await expect(page.locator("main article")).toBeVisible();
      await expect(page.getByRole("navigation").first()).toBeVisible();
      await expect(page.locator(".mobile-toolbar")).toBeHidden();
    });
  }

  test("non-default context features have a mobile server-rendered fallback", async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "mobile-chromium", "mobile fallback assertion");
    for (const theme of ["blog", "docs", "digital-garden"] as const) {
      await page.goto(`/__fixture__/features/${theme}/relations/`);
      await expect(page.locator("[data-context-panel]")).toBeVisible();
      await expect(page.getByRole("heading", { name: "Backlinks" })).toBeVisible();
    }
  });
});
