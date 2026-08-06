import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

type Theme = "minimal" | "docs";

const themes = ["minimal", "docs"] as const satisfies readonly Theme[];
const site = (theme: Theme, route = "/") => `/__site__/${theme}${route}`;
const localizedDocs = (route = "/") => `/__site__/docs-i18n${route}`;

for (const theme of themes) {
  test(`${theme} exposes an accessible presentation`, async ({ page }) => {
    const route = theme === "minimal" ? "/blog/One%20vault%2C%20three%20readings/" : "/";
    await page.goto(site(theme, route));
    await expect(page.locator("body")).toHaveClass(new RegExp(`theme-${theme}`));
    await expect(page.locator("main")).toBeVisible();
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
}

for (const theme of themes) {
  test(`${theme} copies the exact generated Markdown resource`, async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          async writeText(value: string) {
            (window as typeof window & { __copiedMarkdown?: string }).__copiedMarkdown = value;
          }
        }
      });
    });
    const route = theme === "minimal"
      ? "/blog/One%20vault%2C%20three%20readings/"
      : "/docs/Getting%20Started/";
    await page.goto(site(theme, route));

    const actions = page.locator("[data-page-actions]");
    await expect(actions.locator(".page-actions__primary")).toBeVisible();
    const view = actions.locator("a.page-actions__item[href]");
    const markdownUrl = await view.getAttribute("href");
    expect(markdownUrl).toBeTruthy();
    const markdownResponse = await page.request.get(markdownUrl!);
    expect(markdownResponse.ok()).toBe(true);
    expect(markdownResponse.headers()["content-type"]).toContain("text/markdown");
    const markdown = await markdownResponse.text();
    expect(markdown).not.toMatch(/^---\s*(?:\r?\n)/);
    expect(markdown.endsWith("\n")).toBe(true);
    expect(markdown.endsWith("\n\n")).toBe(false);

    await actions.locator(".page-actions__primary").click();
    await expect(actions.locator("[role='status']")).toHaveText("Copied");
    expect(await page.evaluate(() =>
      (window as typeof window & { __copiedMarkdown?: string }).__copiedMarkdown
    )).toBe(markdown);

    await actions.locator("summary").click();
    await expect(view).toBeVisible();
    await expect(actions.getByRole("link", { name: /View as Markdown/ })).toBeVisible();
    await expect(view).toHaveAttribute("target", "_blank");
    await expect(view).toHaveAttribute("rel", "noopener");
  });
}

test("View as Markdown remains reachable without JavaScript", async ({ browser }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one no-JS browser contract is sufficient");
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));

  const actions = page.locator("[data-page-actions]");
  await expect(actions.locator(".page-actions__primary")).toBeHidden();
  await actions.locator("summary").click();
  await expect(actions.getByRole("button", { name: "Copy page" })).toHaveCount(0);
  const view = actions.getByRole("link", { name: /View as Markdown/ });
  await expect(view).toBeVisible();
  await expect(view).toHaveAttribute("href", /\.md$/);
  await context.close();
});

test("Copy failure opens a visible Markdown fallback", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one visible failure contract is sufficient");
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  await page.route(/\.md$/, (route) => route.fulfill({ status: 503, body: "Unavailable" }));

  const actions = page.locator("[data-page-actions]");
  await actions.locator(".page-actions__primary").click();

  await expect(actions.locator("[data-copy-page-error]")).toBeVisible();
  await expect(actions.locator("[data-copy-page-error]")).toContainText("View as Markdown");
  await expect(actions.getByRole("link", { name: /View as Markdown/ })).toBeVisible();
});

test("Minimal Home combines authored content with at most six recent posts", async ({ page }, testInfo) => {
  await page.goto(site("minimal"));

  const article = page.locator(".minimal-entry");
  await expect(article).toHaveClass(/website-home/);
  await expect(article.getByRole("heading", { level: 1, name: "One vault, two ways to publish" })).toBeVisible();
  await expect(article).toContainText("Minimal combines a Home page, Blog, Docs, and custom sections");
  await expect(article.locator(".source-actions")).toBeVisible();

  const recent = page.locator(".minimal-recent");
  await expect(recent.getByRole("heading", { level: 2, name: "Recent posts" })).toBeVisible();
  const cards = recent.locator(".minimal-post-card");
  await expect(cards).toHaveCount(2);
  expect(await cards.count()).toBeLessThanOrEqual(6);
  await expect(cards.first().getByRole("link", { name: "One vault, two site models" })).toBeVisible();
  await expect(cards.first().locator(".minimal-post-card__excerpt"))
    .toHaveText("Why Minimal and Docs share one compiler but not one layout.");
  await expect(cards.first().locator("time")).toHaveAttribute("datetime", "2026-08-01T00:00:00Z");
  await expect(cards.first().locator(".minimal-post-card__media img"))
    .toHaveAttribute("src", /\/__site__\/minimal\/assets\/vault\/assets\/research-folio\.svg$/);
  await expect(cards.nth(1).locator(".minimal-post-card__media")).toHaveCount(0);
  await expect(recent.getByRole("link", { name: /View all/ }))
    .toHaveAttribute("href", site("minimal", "/blog/"));
  await expect(cards.locator(":not(.minimal-post-card--with-image) .minimal-post-card__media"))
    .toHaveCount(0);
  await expect(page.locator(".blog-post-feed, .blog-pager, link[rel='next']")).toHaveCount(0);

  if (testInfo.project.name === "desktop-chromium") {
    const firstTitle = cards.getByRole("heading", { level: 3 }).first();
    expect(Number.parseFloat(await firstTitle.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeLessThanOrEqual(29);
  }
});

test("Minimal navigation defaults to Home, Blog, Docs and marks the active scope", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop primary navigation assertion");

  for (const [route, current] of [["/", "Home"], ["/blog/", "Blog"], ["/docs/Getting%20Started/", "Docs"]] as const) {
    await page.goto(site("minimal", route));
    const navigation = page.getByRole("navigation", { name: "Primary navigation" });
    await expect(navigation.locator(":scope > ul > li > a")).toHaveText(["Home", "Blog", "Docs"]);
    await expect(navigation.getByRole("link", { name: current, exact: true })).toHaveAttribute("aria-current", "page");
  }
});

test("Minimal Home owns counted Topics and article pages do not repeat them", async ({ page }, testInfo) => {
  if (testInfo.project.name === "desktop-chromium") {
    await page.goto(site("minimal"));
    const topics = page.locator("[data-context-panel]");
    await expect(topics).toHaveAttribute("aria-label", "Page context");
    await expect(topics.locator("[data-local-graph-section]")).toBeVisible();
    await expect(topics.getByRole("heading", { name: "On this page" })).toBeVisible();
    const capsule = topics.locator(".context-tag-list a", { hasText: "release-notes" });
    await expect(capsule.locator(".context-tag__count")).toHaveText("1");
    await expect(capsule).toHaveAttribute("href", /\/blog\/\?topic=/);
    await expect(capsule).not.toContainText("#");
    await expect(capsule).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");

    await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
    await expect(page.locator("[data-context-panel]").getByRole("heading", { name: "Topics" })).toHaveCount(0);
  } else {
    await page.goto(site("minimal"));
    await page.getByRole("button", { name: "Context" }).tap();
    const dialog = page.locator('dialog[data-dialog="context"]');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator(".context-tag-list a", { hasText: "release-notes" })
      .locator(".context-tag__count")).toHaveText("1");
  }
});

test("Blog filters by topic and exposes only populated chronology periods", async ({ page }, testInfo) => {
  await page.goto(site("minimal", "/blog/"));
  await expect(page.getByRole("heading", { level: 1, name: "Blog" })).toHaveCount(1);
  await expect(page.getByRole("heading", { name: "Archive" })).toHaveCount(0);

  const filter = page.getByRole("navigation", { name: "Filter by topic" });
  await expect(filter.getByRole("link", { name: /^All\b/ })).toHaveAttribute("aria-current", "page");
  await filter.getByRole("link", { name: /release-notes/ }).click();
  await expect(page).toHaveURL(/\/blog\/\?topic=release-notes$/);
  await expect(filter.getByRole("link", { name: /release-notes/ })).toHaveAttribute("aria-current", "page");
  await expect(filter.getByRole("link", { name: /release-notes/ })).not.toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
  await expect(page.locator("[data-filter-item]:visible").getByRole("link", { name: "One vault, two site models" })).toBeVisible();
  await expect(page.locator("[data-filter-item]", { hasText: "从笔记到发布" })).toBeHidden();
  await filter.getByRole("link", { name: /^All\b/ }).click();
  await expect(page).toHaveURL(site("minimal", "/blog/"));
  await expect(page.locator("[data-filter-item]:visible")).toHaveCount(2);

  if (testInfo.project.name === "desktop-chromium") {
    const chronology = page.getByRole("navigation", { name: "Chronology" });
    await expect(chronology.locator('[data-filter-year="2026"] .archive-timeline__count')).toHaveText("2");
    await expect(chronology.locator('[data-filter-month="2026-08"] .archive-timeline__count')).toHaveText("1");
    await expect(chronology.locator('[data-filter-month="2026-07"] .archive-timeline__count')).toHaveText("1");
    await expect(chronology.locator('[data-filter-month="2026-06"]')).toHaveCount(0);

    await chronology.locator('[data-filter-month="2026-07"]').click();
    await expect(page).toHaveURL(/\/blog\/\?month=2026-07$/);
    await expect(page.locator("[data-filter-item]:visible")).toHaveCount(1);
    await chronology.locator('[data-filter-year="2026"]').click();
    await expect(page).toHaveURL(/\/blog\/\?year=2026$/);
    await expect(page.locator("[data-filter-item]:visible")).toHaveCount(2);

    const year = page.locator(".archive-ledger > section > h2", { hasText: "2026" });
    expect(Number.parseFloat(await year.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeGreaterThanOrEqual(24);
  } else {
    await page.getByRole("button", { name: "Chronology" }).tap();
    const dialog = page.locator('dialog[data-dialog="context"]');
    await expect(dialog).toBeVisible();
    await dialog.locator('[data-filter-month="2026-07"]').tap();
    await expect(page).toHaveURL(/\/blog\/\?month=2026-07$/);
    await expect(dialog.locator('[data-filter-month="2026-07"]')).toHaveAttribute("aria-current", "page");
    await expect(page.locator("[data-filter-item]:not([hidden])")).toHaveCount(1);
  }
});

test("legacy Archive, paginated Home, and Notes routes are absent", async ({ page }) => {
  for (const route of ["/archive/", "/page/2/", "/notes/"] as const) {
    const response = await page.goto(site("minimal", route));
    expect(response?.status(), route).toBe(404);
    await expect(page.locator("body")).toHaveText("Not found");
  }
});

test("short Blog pages keep the footer at the viewport edge", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop footer geometry assertion");
  await page.goto(site("minimal", "/blog/"));
  const geometry = await page.locator(".site-footer").evaluate((footer) => ({
    bottom: footer.getBoundingClientRect().bottom,
    viewport: window.innerHeight
  }));
  expect(Math.abs(geometry.bottom - geometry.viewport)).toBeLessThanOrEqual(1);
});

for (const theme of themes) {
  test(`${theme} documentation navigation preserves its shell`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop documentation navigation assertion");
    await page.goto(site(theme, "/docs/Getting%20Started/"));

    const header = page.locator(".site-header");
    const sidebar = page.locator(theme === "minimal" ? ".minimal-docs-sidebar" : ".docs-sidebar");
    await header.evaluate((element) => element.setAttribute("data-shell-instance", "header"));
    await sidebar.evaluate((element) => element.setAttribute("data-shell-instance", "sidebar"));

    const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
    await expect(navigation).toHaveAttribute("data-docs-navigation-ready", "true");
    await navigation.getByRole("link", { name: "Syntax" }).click();
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
    await expect(page.getByRole("heading", { level: 1, name: "Syntax" })).toBeVisible();
    await expect(header).toHaveAttribute("data-shell-instance", "header");
    await expect(sidebar).toHaveAttribute("data-shell-instance", "sidebar");
    await expect(page.locator("[data-context-panel] [data-graph-view]")).toHaveAttribute("data-graph-ready", "true");

    await page.goBack();
    await expect(page).toHaveURL(site(theme, "/docs/Getting%20Started/"));
    await expect(header).toHaveAttribute("data-shell-instance", "header");
    await expect(sidebar).toHaveAttribute("data-shell-instance", "sidebar");
  });

  test(`${theme} documentation fragments preserve the page shell through history`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop documentation fragment assertion");
    await page.goto(site(theme, "/docs/Getting%20Started/"));

    const header = page.locator(".site-header");
    const sidebar = page.locator(theme === "minimal" ? ".minimal-docs-sidebar" : ".docs-sidebar");
    await header.evaluate((element) => element.setAttribute("data-shell-instance", "header"));
    await sidebar.evaluate((element) => element.setAttribute("data-shell-instance", "sidebar"));

    await page.getByRole("navigation", { name: "Documentation", exact: true })
      .getByRole("link", { name: "Syntax" }).click();
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
    await expect(page.getByRole("heading", { level: 1, name: "Syntax" })).toBeVisible();
    const main = page.locator("[data-docs-main]");
    await main.evaluate((element) => element.setAttribute("data-page-instance", "syntax"));

    const fragment = page.locator("[data-page-context]")
      .getByRole("link", { name: "Tags and comments" });
    await fragment.click();
    await expect(page).toHaveURL(`${site(theme, "/docs/Syntax/")}#tags-and-comments`);
    await page.waitForLoadState("networkidle");
    await expect(page.locator("#tags-and-comments")).toBeInViewport();
    await expect(main).toHaveAttribute("data-page-instance", "syntax");

    await page.goBack();
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
    await page.waitForLoadState("networkidle");
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeLessThanOrEqual(1);
    await expect(main).toHaveAttribute("data-page-instance", "syntax");

    await page.goForward();
    await expect(page).toHaveURL(`${site(theme, "/docs/Syntax/")}#tags-and-comments`);
    await page.waitForLoadState("networkidle");
    await expect(page.locator("#tags-and-comments")).toBeInViewport();
    await expect(header).toHaveAttribute("data-shell-instance", "header");
    await expect(sidebar).toHaveAttribute("data-shell-instance", "sidebar");
  });
}

test("Minimal Docs keeps its three-column context and active top-level scope", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop Minimal Docs assertion");
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await expect(page.locator(".minimal-docs-sidebar")).toBeVisible();
  await expect(page.locator(".minimal-reading-column")).toBeVisible();
  await expect(page.locator(".minimal-context")).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Primary navigation" })
    .getByRole("link", { name: "Docs" })).toHaveAttribute("aria-current", "page");
  await expect(page.getByRole("navigation", { name: "Documentation sequence" })).toContainText("Syntax");
});

test("documentation sidebars expose the complete index by default", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop documentation index assertion");
  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
    const topLevel = navigation.locator(":scope > .docs-tree__list > .docs-tree__item");
    await expect(topLevel.first().locator(":scope > a")).toHaveText("Getting Started");
    await expect(navigation.getByText("Documentation", { exact: true })).toHaveCount(0);
    await expect(navigation.getByRole("link", { name: "Architecture" })).toBeVisible();
    await expect(page.getByRole("link", { name: "View full documentation index" })).toHaveCount(0);
  }
});

test("Minimal Docs puts primary and documentation navigation into the mobile Browse sheet", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile Browse assertion");
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await expect(page.locator(".minimal-docs-sidebar")).toBeHidden();
  await expect(page.locator(".minimal-context")).toBeHidden();
  await page.getByRole("button", { name: "Browse" }).tap();
  const dialog = page.locator('dialog[data-dialog="browse"]');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("navigation", { name: "Primary navigation" }).getByRole("link"))
    .toHaveText(["Home", "Blog", "Docs"]);
  await expect(dialog.getByRole("navigation", { name: "Documentation" })
    .getByRole("link", { name: "Syntax" })).toBeVisible();
});

test("Minimal mobile Browse documentation links preserve the shell", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile Browse navigation assertion");
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  const header = page.locator(".site-header");
  await header.evaluate((element) => element.setAttribute("data-shell-instance", "header"));

  await page.getByRole("button", { name: "Browse" }).tap();
  const dialog = page.locator('dialog[data-dialog="browse"]');
  await dialog.getByRole("navigation", { name: "Documentation" })
    .getByRole("link", { name: "Syntax" }).tap();

  await expect(page).toHaveURL(site("minimal", "/docs/Syntax/"));
  await expect(page.getByRole("heading", { level: 1, name: "Syntax" })).toBeVisible();
  await expect(header).toHaveAttribute("data-shell-instance", "header");
});

test("priority navigation folds custom tabs into an accessible More menu", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop priority navigation assertion");
  await page.goto("/__fixture__/features/minimal/navigation/");
  const navigation = page.getByRole("navigation", { name: "Primary navigation" });
  await expect(navigation).toHaveAttribute("data-priority-navigation-ready", "true");
  await navigation.evaluate((element) => {
    element.style.flex = "0 0 230px";
    element.style.inlineSize = "230px";
    element.style.maxInlineSize = "230px";
  });

  const more = navigation.locator("[data-priority-navigation-more]");
  await expect(more).toBeVisible();
  await expect(more).toHaveAttribute("data-has-current", "true");
  const primaryIds = await navigation.locator("[data-priority-navigation-list] > li")
    .evaluateAll((items) => items.map((item) => item.getAttribute("data-navigation-id")));
  const overflowIds = await navigation.locator("[data-priority-navigation-overflow] > li")
    .evaluateAll((items) => items.map((item) => item.getAttribute("data-navigation-id")));
  expect([...primaryIds, ...overflowIds]).toEqual([
    "home", "blog", "docs", "page:about.md", "folder:portfolio", "page:projects.md", "folder:team", "page:contact.md"
  ]);

  const summary = more.locator("summary");
  await summary.focus();
  await page.keyboard.press("Enter");
  await expect(more).toHaveAttribute("open", "");
  await expect(more.getByRole("link", { name: "Projects" })).toHaveAttribute("aria-current", "page");
  await page.keyboard.press("Tab");
  await expect(more.locator("[data-priority-navigation-overflow] a").first()).toBeFocused();
  await page.getByRole("heading", { name: "Independent context" }).click();
  await expect(more).not.toHaveAttribute("open", "");

  await navigation.evaluate((element) => {
    element.style.flexBasis = "900px";
    element.style.inlineSize = "900px";
    element.style.maxInlineSize = "900px";
  });
  await expect(more).toBeHidden();
  await expect(navigation.locator("[data-priority-navigation-list] > li")).toHaveCount(8);
});

test("mobile Browse preserves all configured tabs and their active state", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile custom navigation assertion");
  await page.goto("/__fixture__/features/minimal/navigation/");
  await page.getByRole("button", { name: "Browse" }).tap();
  const navigation = page.locator('dialog[data-dialog="browse"]')
    .getByRole("navigation", { name: "Primary navigation" });
  await expect(navigation.getByRole("link")).toHaveText([
    "Home", "Blog", "Docs", "About", "Portfolio", "Projects", "Team", "Contact"
  ]);
  await expect(navigation.getByRole("link", { name: "Projects" })).toHaveAttribute("aria-current", "page");
});

test("search loads on demand and finds CJK content", async ({ page }) => {
  await page.goto(site("minimal"));
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveAttribute("data-search-ready", "true");
  const headerNavigation = page.locator(".site-header [data-priority-navigation-item]");
  const searchNavigation = dialog.locator("[data-search-navigation] [data-navigation-id]");
  await expect(searchNavigation).toHaveCount(await headerNavigation.count());
  await expect(searchNavigation.locator("a")).toHaveText(await headerNavigation.locator("a").allTextContents());
  await dialog.locator("input").fill("Docs");
  expect(await searchNavigation.filter({ hasNotText: "Docs" }).evaluateAll((items) =>
    items.every((item) => (item as HTMLElement).hidden)
  )).toBe(true);
  await expect(searchNavigation.filter({ hasText: "Docs" })).toBeVisible();
  await dialog.locator("input").fill("CJK");
  await expect(dialog.locator("[data-search-navigation]")).toBeHidden();
  await expect(dialog.getByRole("link", { name: "CJK Showcase" })).toBeVisible();
});

test("search input focus does not add a focus frame", async ({ page }) => {
  await page.goto(site("docs"));
  await page.keyboard.press("ControlOrMeta+k");
  const box = page.locator(".search-box");
  const input = box.locator("[data-search-input]");
  await input.evaluate((element) => element.blur());
  const quietBorder = await box.evaluate((element) => getComputedStyle(element).borderTopColor);
  await input.focus();
  await expect(box).toHaveCSS("border-top-color", quietBorder);
  await expect(box).toHaveCSS("box-shadow", "none");
  await expect(input).toHaveCSS("outline-style", "none");
  await expect(input).toHaveCSS("box-shadow", "none");
});

test("Minimal previews use catalog text without injecting active content", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop preview assertion");
  await page.goto(site("minimal"));
  await page.locator(".website-link[data-note-id='docs/中文示例.md']").focus();
  const preview = page.locator("[data-note-preview]");
  await expect(preview).toContainText("CJK Showcase");
  await expect(preview.locator(".note-preview__body")).toHaveAttribute("data-preview-body-ready", "true");
  await expect(preview).toContainText("中文、日文和拉丁字母可以写在同一个知识库里");
  await expect(preview.locator("iframe, script")).toHaveCount(0);
});

test("every theme places the local graph first in documentation context", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph context assertion");
  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    const context = page.locator("[data-context-panel]");
    await expect(context).toBeVisible();
    await expect(context.locator(":scope > .local-graph")).toHaveCount(1);
    await expect(context.locator(":scope > section").first()).toHaveClass(/local-graph/);
    await expect(context.getByRole("button", { name: "Open full graph" })).toBeVisible();
    await expect(context.getByRole("button", { name: "Expand local graph" })).toBeVisible();
    await expect(context.locator("[data-graph-view]")).toHaveAttribute("data-graph-ready", "true");
  }
});

test("graph dialogs cache the complete graph and dispose expanded local graphs", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph dialog assertion");
  let graphRequests = 0;
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.endsWith("/assets/website/graph.v1.json")) graphRequests += 1;
  });
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  const context = page.locator("[data-context-panel]");
  await context.getByRole("button", { name: "Open full graph" }).click();
  const full = page.locator('dialog[data-dialog="graph-global"]');
  await expect(full.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  await full.getByRole("button", { name: "Close full graph" }).click();
  await context.getByRole("button", { name: "Open full graph" }).click();
  await expect(full.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  expect(graphRequests).toBe(1);
  await full.getByRole("button", { name: "Close full graph" }).click();

  await context.getByRole("button", { name: "Expand local graph" }).click();
  const local = page.locator('dialog[data-dialog="graph-local"]');
  await expect(local.locator(".graph-node")).not.toHaveCount(0);
  await local.getByRole("button", { name: "Close local graph" }).click();
  await expect(local.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-disposed", "true");
});

test("graph nodes have no frame and darken only on interaction", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph interaction assertion");
  await page.goto(site("docs", "/docs/Syntax/"));
  const view = page.locator("[data-context-panel] [data-graph-view]");
  await expect(view).toHaveAttribute("data-graph-ready", "true");
  const currentCircle = view.locator(".graph-node--current circle");
  const target = view.locator(".graph-node[role='link']").first();
  const targetCircle = target.locator("circle");
  await expect(targetCircle).toHaveCSS("stroke", "none");
  const quiet = await targetCircle.evaluate((element) => getComputedStyle(element).fill);
  expect(await currentCircle.evaluate((element) => getComputedStyle(element).fill)).toBe(quiet);
  await target.hover();
  await expect.poll(() => targetCircle.evaluate((element) => getComputedStyle(element).fill)).not.toBe(quiet);
  await page.mouse.move(0, 0);
  await target.focus();
  await expect.poll(() => targetCircle.evaluate((element) => getComputedStyle(element).fill)).not.toBe(quiet);
});

test("Comments use the managed Giscus client and remain narrow-layout safe", async ({ page }) => {
  let requestedClient = false;
  await page.addInitScript(() => localStorage.setItem("website:color-scheme", "dark"));
  await page.route("https://giscus.app/client.js", async (route) => {
    requestedClient = true;
    await route.fulfill({ contentType: "text/javascript", body: "" });
  });
  await page.setViewportSize({ width: 320, height: 760 });
  await page.goto("/__fixture__/comments/");
  const comments = page.getByRole("region", { name: "Comments" });
  await expect(comments).toBeVisible();
  await expect(comments.getByText("Discussion", { exact: true })).toHaveCount(0);
  const heading = comments.getByRole("heading", { name: "Comments" });
  expect((await heading.boundingBox())!.x).toBeCloseTo((await comments.boundingBox())!.x, 0);
  expect(await heading.evaluate((element) => Number.parseFloat(getComputedStyle(element).fontSize)))
    .toBeLessThanOrEqual(28);
  await expect.poll(() => requestedClient).toBe(true);
  const client = comments.locator("script[data-website-comments-client]");
  await expect(client).toHaveAttribute("data-mapping", "specific");
  await expect(client).toHaveAttribute("data-strict", "1");
  await expect(client).toHaveAttribute("data-theme", "dark");
  expect(await comments.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
  const results = await new AxeBuilder({ page }).include(".website-comments").analyze();
  expect(results.violations).toEqual([]);
});

test("Comments retain their GitHub fallback when Giscus is unavailable", async ({ page }) => {
  await page.route("https://giscus.app/client.js", (route) => route.abort());
  await page.goto("/__fixture__/comments/");
  const comments = page.getByRole("region", { name: "Comments" });
  await expect(comments).toHaveAttribute("data-website-comments-state", "unavailable");
  await expect(comments.getByText("Comments could not be loaded.")).toBeVisible();
  await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
});

test("Minimal articles use centered Previous and Next cards", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop sequence geometry assertion");
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  const previous = page.locator(".sequence-navigation a[rel='prev']");
  await expect(previous.locator("span")).toHaveText("Previous");
  await expect(previous).toHaveCSS("text-align", "center");
  await expect(previous).toHaveCSS("border-top-width", "1px");
  await page.goto(site("minimal", "/blog/%E4%BB%8E%E7%AC%94%E8%AE%B0%E5%88%B0%E5%8F%91%E5%B8%83/"));
  const next = page.locator(".sequence-navigation a[rel='next']");
  await expect(next.locator("span")).toHaveText("Next");
  await expect(next).toHaveCSS("text-align", "center");
  await expect(next).toHaveCSS("grid-column-start", "2");
});

test("themes follow system dark mode and support explicit light override", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(() => localStorage.removeItem("website:color-scheme"));
  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "dark");
    await page.locator("[data-color-scheme-toggle]").click();
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
  }
});

test("saved light preference is applied before the deferred theme bundle", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "first-paint timing assertion");
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(() => localStorage.setItem("website:color-scheme", "light"));
  await page.route(/\/(?:minimal|docs)-[A-Z0-9]+\.js(?:\?.*)?$/, (route) => route.abort());
  for (const theme of themes) {
    await page.goto(site(theme), { waitUntil: "domcontentloaded" });
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
    expect(await page.locator("head").evaluate((head) => {
      const children = [...head.children];
      const bootstrap = children.findIndex((element) =>
        element instanceof HTMLScriptElement && element.src.includes("color-scheme-bootstrap-")
      );
      const stylesheet = children.findIndex((element) =>
        element instanceof HTMLLinkElement && element.rel === "stylesheet"
      );
      return bootstrap >= 0 && stylesheet >= 0 && bootstrap < stylesheet;
    })).toBe(true);
  }
});

test("themes use neutral dark surfaces, warm paper light, and one restrained type scale", async ({ page }) => {
  for (const theme of themes) {
    await page.emulateMedia({ colorScheme: "dark" });
    await page.addInitScript(() => localStorage.removeItem("website:color-scheme"));
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    for (const selector of ["body", "pre"] as const) {
      const channels = await page.locator(selector).first().evaluate((element) =>
        getComputedStyle(element).backgroundColor.match(/\d+/g)?.slice(0, 3).map(Number) || []
      );
      expect(Math.max(...channels) - Math.min(...channels), `${theme} ${selector}`).toBeLessThanOrEqual(4);
    }

    await page.emulateMedia({ colorScheme: "light" });
    await page.evaluate(() => localStorage.setItem("website:color-scheme", "light"));
    await page.reload();
    const paper = await page.locator("body").evaluate((element) =>
      getComputedStyle(element).backgroundColor.match(/\d+/g)?.slice(0, 3).map(Number) || []
    );
    expect(paper[0]!, theme).toBeGreaterThan(paper[2]!);

    const title = page.getByRole("heading", { level: 1, name: "Getting Started" });
    const section = page.getByRole("heading", { level: 2, name: "Install the toolchain" });
    const paragraph = page.locator(".note-content > p").first();
    const typography = (locator: typeof title) => locator.evaluate((element) => {
      const style = getComputedStyle(element);
      return { family: style.fontFamily, size: Number.parseFloat(style.fontSize) };
    });
    const [titleType, sectionType, bodyType] = await Promise.all([
      typography(title), typography(section), typography(paragraph)
    ]);
    expect(titleType.family).toBe(bodyType.family);
    expect(sectionType.family).toBe(bodyType.family);
    expect(bodyType.family).toContain("Segoe UI");
    expect(titleType.size / bodyType.size).toBeLessThan(3);
    expect(sectionType.size / bodyType.size).toBeLessThan(2);
  }
});

test("Minimal omits decorative reading chrome", async ({ page }) => {
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await expect(page.locator(".note-kicker, .breadcrumbs")).toHaveCount(0);
  await expect(page.locator(".note-header")).toHaveCSS("border-bottom-width", "0px");
  await expect(page.locator(".site-header")).toHaveCSS("border-top-width", "0px");
  const section = page.getByRole("heading", { level: 2, name: "Install the toolchain" });
  expect(await section.evaluate((element) => getComputedStyle(element, "::before").content)).toBe("none");
});

test("feed discovery stays out of primary navigation", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop navigation assertion");
  for (const theme of themes) {
    await page.goto(`/__fixture__/features/${theme}/navigation/`);
    const primary = page.getByRole("navigation", { name: "Primary navigation" });
    await expect(primary.locator('a[href="/tags/"], a[href="/feed.xml"], a[href="/graph/"]')).toHaveCount(0);
    await expect(page.locator('head link[rel="alternate"][type="application/atom+xml"]'))
      .toHaveAttribute("href", "/feed.xml");
  }

  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  const primary = page.getByRole("navigation", { name: "Primary navigation" });
  await expect(primary.getByRole("link", { name: /^(Feed|Topics|Tags)$/ })).toHaveCount(0);
  await expect(page.locator('head link[rel="alternate"][type="application/atom+xml"]'))
    .toHaveAttribute("href", /\/__site__\/minimal\/feed\.xml$/);
});

test("localized docs language navigation and fallback metadata remain correct", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/docs/Getting%20Started/"));
  await expect(page.locator(".site-mark__name")).toHaveText("Browser i18n fixture");
  await expect(page.locator("html")).toHaveAttribute("lang", "zh-CN");
  const switcher = page.locator("[data-language-switcher]");
  await switcher.locator("summary").click();
  await expect(switcher.getByRole("link", { name: "简体中文" })).toHaveAttribute("aria-current", "page");
  await expect(switcher.getByRole("link", { name: "English" }))
    .toHaveAttribute("href", localizedDocs("/docs/Getting%20Started/"));
  await switcher.getByRole("link", { name: "English" }).focus();
  await page.keyboard.press("Escape");
  await expect(switcher.locator("summary")).toBeFocused();

  await page.goto(localizedDocs("/zh-CN/docs/Customization/"));
  await expect(page.locator(".translation-fallback")).toContainText("本页尚无译文");
  await expect(page.locator(".note-content")).toHaveAttribute("lang", "en");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex");
  await expect(page.locator('link[rel="alternate"][hreflang]')).toHaveCount(0);
});

test("localized docs search loads the locale index and finds CJK content", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/"));
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await dialog.locator("input").fill("快速");
  await expect(dialog.getByRole("link", { name: "快速开始" })).toBeVisible();
  await expect(dialog.locator("[data-search-status]")).toHaveText(/找到 \d+ 篇笔记。/);
});

test("Tweet embeds load near the viewport with DNT and keep a static fallback", async ({ page }) => {
  await page.route("https://platform.twitter.com/widgets.js", async (route) => {
    await route.fulfill({
      contentType: "text/javascript",
      body: `window.twttr = { widgets: { createTweet(id, target, options) {
        target.dataset.renderedTweet = id;
        target.dataset.dnt = String(options.dnt);
        target.dataset.theme = options.theme;
        target.textContent = "Rendered post";
        return Promise.resolve(target);
      } } };`
    });
  });
  await page.goto("/__fixture__/tweet/");

  const tweet = page.locator("[data-website-tweet]");
  const mount = tweet.locator("[data-website-tweet-mount]");
  await expect(mount).toHaveAttribute("data-rendered-tweet", "1580548874246443010");
  await expect(mount).toHaveAttribute("data-dnt", "true");
  await expect(mount).toHaveAttribute("data-theme", /^(light|dark)$/);
  await expect(tweet.locator("[data-website-tweet-fallback]")).toBeHidden();
  await expect(page.locator("script[data-website-x-widgets]")).toHaveAttribute(
    "src",
    "https://platform.twitter.com/widgets.js"
  );
});

for (const fixture of [
  { theme: "minimal", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "minimal", feature: "relations", visible: "Backlinks", hidden: "On this page" },
  { theme: "docs", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "docs", feature: "relations", visible: "Backlinks", hidden: "On this page" }
] as const) {
  test(`${fixture.theme} renders ${fixture.feature} independently`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop context assertion");
    await page.goto(`/__fixture__/features/${fixture.theme}/${fixture.feature}/`);
    const panel = page.locator("[data-context-panel]");
    await expect(panel).toBeVisible();
    await expect(panel.getByRole("heading", { name: fixture.visible })).toBeVisible();
    await expect(panel.getByRole("heading", { name: fixture.hidden })).toHaveCount(0);
  });
}

test("relation context puts collapsed direct links after backlinks", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop relation assertion");
  await page.goto("/__fixture__/features/minimal/relations/");
  const panel = page.locator("[data-context-panel]");
  const titles = await panel.locator(":scope > .relation-section").evaluateAll((sections) =>
    sections.map((section) => section.querySelector(".relation-section__title")?.textContent?.trim())
  );
  expect(titles.indexOf("Backlinks")).toBeLessThan(titles.indexOf("Direct links"));
  const directLinks = panel.locator("details.relation-disclosure");
  await expect(directLinks).not.toHaveAttribute("open", "");
  await expect(directLinks.getByRole("link", { name: "Linked note" })).toBeHidden();
  await directLinks.locator("summary").click();
  await expect(directLinks.getByRole("link", { name: "Linked note" })).toBeVisible();
});

test("themes remove context UI when outline and relations are disabled", async ({ page }) => {
  for (const theme of themes) {
    await page.goto(`/__fixture__/features/${theme}/none/`);
    await expect(page.locator("[data-context-panel], [data-dialog='context']")).toHaveCount(0);
    await expect(page.getByRole("button", { name: /Context|On this page/ })).toHaveCount(0);
  }
});

test("non-default context features remain available in mobile sheets", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile context assertion");
  for (const [theme, feature, heading] of [
    ["minimal", "outline", "On this page"],
    ["minimal", "relations", "Backlinks"],
    ["docs", "outline", "On this page"],
    ["docs", "relations", "Backlinks"]
  ] as const) {
    await page.goto(`/__fixture__/features/${theme}/${feature}/`);
    await expect(page.locator("[data-context-panel]")).toBeHidden();
    await page.getByRole("button", { name: feature === "outline" ? "On this page" : "Context" }).tap();
    await expect(page.locator('dialog[data-dialog="context"] .relation-section__title')
      .filter({ hasText: heading })).toBeVisible();
  }
});

test.describe("without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  for (const theme of themes) {
    test(`${theme} retains authored content and navigation`, async ({ page }) => {
      await page.goto(site(theme));
      await expect(page.locator(theme === "minimal" ? "main > .minimal-reading-column > .minimal-entry" : "main > .docs-article"))
        .toBeVisible();
      await expect(page.getByRole("navigation").first()).toBeVisible();
      await expect(page.locator(".mobile-toolbar")).toBeHidden();
    });
  }

  test("priority navigation exposes every custom link without JavaScript", async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop no-JavaScript navigation assertion");
    await page.goto("/__fixture__/features/minimal/navigation/");
    const navigation = page.getByRole("navigation", { name: "Primary navigation" });
    await expect(navigation.locator("[data-priority-navigation-list] > li > a")).toHaveText([
      "Home", "Blog", "Docs", "About", "Portfolio", "Projects", "Team", "Contact"
    ]);
    await expect(navigation.locator("[data-priority-navigation-more]")).toBeHidden();
    await expect(navigation.getByRole("link", { name: "Projects" })).toHaveAttribute("aria-current", "page");
  });

  test("docs serves its complete index without JavaScript", async ({ page }) => {
    await page.goto(site("docs", "/docs/Getting%20Started/"));
    const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
    await expect(navigation.getByRole("link", { name: "Architecture" })).toBeVisible();
    await expect(page.getByRole("link", { name: "View full documentation index" })).toHaveCount(0);
  });

  test("Comments retain the GitHub Discussions fallback", async ({ page }) => {
    await page.goto("/__fixture__/comments/");
    const comments = page.getByRole("region", { name: "Comments" });
    await expect(comments.locator("script[data-website-comments-client]")).toHaveCount(0);
    await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
  });

  test("Tweet embeds retain the X fallback", async ({ page }) => {
    await page.goto("/__fixture__/tweet/");
    await expect(page.locator("script[data-website-x-widgets]")).toHaveCount(0);
    await expect(page.getByRole("link", { name: "View post on X" }))
      .toHaveAttribute("href", "https://x.com/obsdmd/status/1580548874246443010");
  });

  test("documentation graphs and mobile context have server-rendered fallbacks", async ({ page }, testInfo) => {
    await page.goto(site("minimal", "/docs/Syntax/"));
    await expect(page.locator(".local-graph__fallback")).toBeVisible();
    await expect(page.locator("pre[lang='mermaid']")).toBeVisible();
    if (testInfo.project.name === "mobile-chromium") {
      await expect(page.getByRole("complementary", { name: "Page context" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "Backlinks" })).toBeVisible();
    }
  });
});
