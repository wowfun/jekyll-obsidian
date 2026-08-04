import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const site = (theme: "blog" | "docs" | "digital-garden", route = "/") =>
  `/__site__/${theme}${route}`;
const localizedDocs = (route = "/") => `/__site__/docs-i18n${route}`;

for (const theme of ["blog", "docs", "digital-garden"] as const) {
  test(`${theme} exposes its own accessible presentation`, async ({ page }) => {
    await page.goto(site(theme));
    await expect(page.locator("body")).toHaveClass(new RegExp(`theme-${theme}`));
    await expect(page.locator("main")).toBeVisible();
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
}

test("blog reads as a dated publishing ledger", async ({ page }) => {
  await page.goto(site("blog"));
  await expect(page.getByRole("link", { name: /One vault, three readings/ })).toBeVisible();
  await expect(page.locator(".blog-ledger time").first()).toHaveAttribute("datetime", "2026-08-01T00:00:00Z");
  await expect(page.getByRole("link", { name: "Browse the archive" })).toBeVisible();
});

test("docs exposes its handbook navigation and reading sequence", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop navigation assertion");
  await page.goto(site("docs", "/docs/Getting%20Started/"));
  const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
  await expect(navigation).toBeVisible();
  await expect(navigation).toHaveAttribute("data-docs-navigation-ready", "true");
  await expect(navigation.getByRole("link", { name: "Syntax" })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Breadcrumb" })).toContainText("Documentation");
  await expect(page.getByRole("navigation", { name: "Documentation sequence" })).toContainText(
    "Syntax"
  );
});

test("docs language switcher uses real localized routes and restores focus", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/docs/Getting%20Started/"));
  await expect(page.locator("html")).toHaveAttribute("lang", "zh-CN");
  await expect(page.locator("h1").filter({ hasText: "快速开始" })).toBeVisible();
  const switcher = page.locator("[data-language-switcher]");
  await switcher.locator("summary").click();
  const currentLanguage = switcher.getByRole("link", { name: "简体中文" });
  await expect(currentLanguage).toHaveAttribute("aria-current", "page");
  expect(await currentLanguage.evaluate((element) => getComputedStyle(element).backgroundColor)).not.toBe("rgba(0, 0, 0, 0)");
  await expect(switcher.getByRole("link", { name: "English" })).toHaveAttribute(
    "href",
    "/__site__/docs-i18n/docs/Getting%20Started/"
  );
  await switcher.getByRole("link", { name: "English" }).focus();
  await page.keyboard.press("Escape");
  await expect(switcher).not.toHaveAttribute("open", "");
  await expect(switcher.locator("summary")).toBeFocused();
});

test("docs language controls remain usable at 320px in RTL flow", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 760 });
  await page.goto(localizedDocs("/zh-CN/docs/Getting%20Started/"));
  await page.locator("html").evaluate((element) => element.setAttribute("dir", "rtl"));

  const switcher = page.locator("[data-language-switcher]");
  await expect(switcher.locator("summary")).toBeVisible();
  await switcher.locator("summary").click();
  await expect(switcher.getByRole("link", { name: "English" })).toBeVisible();
  await expect(page.getByRole("button", { name: "搜索", exact: true })).toBeVisible();
  expect(await page.locator(".site-header__inner").evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
});

test("docs fallback pages keep locale URLs while opting out of duplicate SEO", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/docs/Customization/"));
  await expect(page.locator("html")).toHaveAttribute("lang", "zh-CN");
  await expect(page.locator(".translation-fallback")).toContainText("本页尚无译文");
  await expect(page.locator(".note-content")).toHaveAttribute("lang", "en");
  await expect(page.locator(".note-content")).toHaveAttribute("dir", "ltr");
  await expect(page.locator(".note-header")).toHaveAttribute("lang", "en");
  await expect(page.locator(".note-header")).toHaveAttribute("dir", "ltr");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex");
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    "href",
    "http://127.0.0.1:4173/__site__/docs-i18n/docs/Customization/"
  );
  await expect(page.locator('link[rel="alternate"][hreflang]')).toHaveCount(0);
});

test("localized Mermaid labels survive a color scheme redraw", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/docs/Syntax/"));
  const diagram = page.locator(".mermaid-diagram svg");
  await expect(diagram).toHaveAttribute("aria-label", "图表");
  await page.locator("[data-color-scheme-toggle]").click();
  await expect(diagram).toHaveAttribute("aria-label", "图表");
});

test("localized docs search loads its locale index and finds CJK content", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/"));
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await dialog.locator("input").fill("快速");
  await expect(dialog.getByRole("link", { name: "快速开始" })).toBeVisible();
  await expect(dialog.locator("[data-search-status]")).toHaveText(/找到 \d+ 篇笔记。/);
});

test("docs breadcrumb marks only its final non-link item as current", async ({ page }) => {
  await page.goto(site("docs", "/docs/Getting%20Started/"));
  const breadcrumb = page.getByRole("navigation", { name: "Breadcrumb" });
  const current = breadcrumb.locator('[aria-current="page"]');
  await expect(current).toHaveCount(1);
  await expect(current).not.toHaveJSProperty("tagName", "A");
  await expect(breadcrumb.locator('a[aria-current="page"]')).toHaveCount(0);
});

test("docs puts browse and outline into mobile sheets", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile interaction assertion");
  await page.goto(site("docs", "/docs/Getting%20Started/"));
  await expect(page.locator(".docs-sidebar")).toBeHidden();
  await expect(page.locator(".docs-context")).toBeHidden();
  await page.getByRole("button", { name: "Context" }).tap();
  const dialog = page.locator('dialog[data-dialog="context"]');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("link", { name: "Install the toolchain" })).toBeVisible();
});

test("digital garden keeps the annotated folio and relation rail", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop layout assertion");
  await page.goto(site("digital-garden", "/docs/Getting%20Started/"));
  await expect(page.locator(".note-folio")).toBeVisible();
  const rail = page.locator(".relation-rail");
  await expect(rail).toBeVisible();
  expect(Math.round((await rail.boundingBox())?.width ?? 0)).toBe(288);
});

test("search loads on demand and finds CJK text", async ({ page }) => {
  await page.goto(site("digital-garden"));
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await expect(dialog).toBeVisible();
  await dialog.locator("input").fill("花园");
  await expect(dialog.getByRole("link", { name: "CJK Showcase" })).toBeVisible();
});

test("digital garden previews use catalog text without active content", async ({ page }) => {
  await page.goto(site("digital-garden"));
  await page.locator(".website-link[data-note-id='docs/中文示例.md']").focus();
  const preview = page.locator("[data-note-preview]");
  await expect(preview).toContainText("CJK Showcase");
  await expect(preview).toContainText("Mixed Chinese, Japanese, Latin");
  await expect(preview.locator(".note-preview__body")).toHaveAttribute("data-preview-body-ready", "true");
  await expect(preview).toContainText("中文、日文和拉丁字母可以写在同一个知识库里");
  await expect(preview.locator("iframe, script")).toHaveCount(0);
  const previewBox = await preview.boundingBox();
  const viewport = page.viewportSize()!;
  expect(previewBox!.x).toBeGreaterThanOrEqual(11);
  expect(previewBox!.y).toBeGreaterThanOrEqual(11);
  expect(previewBox!.x + previewBox!.width).toBeLessThanOrEqual(viewport.width - 11);
  expect(previewBox!.y + previewBox!.height).toBeLessThanOrEqual(viewport.height - 11);
});

test("keyboard users can enter a preview body and continue to the next link", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop keyboard preview assertion");
  await page.goto(site("docs"));
  const customization = page.locator(".website-link[data-note-id='docs/Customization.md']").first();
  await customization.evaluate((element) => element.scrollIntoView({ block: "center", behavior: "instant" as ScrollBehavior }));
  await customization.focus();
  const previewBody = page.locator("[data-note-preview] .note-preview__body");
  await expect(previewBody).toHaveAttribute("data-preview-body-ready", "true");

  await page.keyboard.press("Tab");
  await expect(previewBody).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(page.locator(".website-link[data-note-id='docs/Comments.md']").first()).toBeFocused();
});

test("every theme places the local graph first in note context", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop context rail assertion");
  for (const theme of ["blog", "docs", "digital-garden"] as const) {
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

test("graph buttons open cached full and expanded local dialogs", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph dialog assertion");
  let graphRequests = 0;
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.endsWith("/assets/website/graph.v1.json")) graphRequests += 1;
  });
  await page.goto(site("docs", "/docs/Getting%20Started/"));
  const context = page.locator("[data-context-panel]");

  await context.getByRole("button", { name: "Open full graph" }).click();
  const full = page.locator('dialog[data-dialog="graph-global"]');
  await expect(full).toBeVisible();
  await expect(full.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  await full.getByRole("button", { name: "Close full graph" }).click();
  await context.getByRole("button", { name: "Open full graph" }).click();
  await expect(full.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  expect(graphRequests).toBe(1);
  await page.keyboard.press("Escape");
  await expect(full).toBeHidden();

  await context.getByRole("button", { name: "Expand local graph" }).click();
  const local = page.locator('dialog[data-dialog="graph-local"]');
  await expect(local).toBeVisible();
  await expect(local.locator(".graph-node")).not.toHaveCount(0);
  await local.getByRole("button", { name: "Close local graph" }).click();
  await expect(local.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-disposed", "true");
});

test("oversized complete graphs use the bounded browser fallback", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph fallback assertion");
  const nodes = Array.from({ length: 5_000 }, (_, index) => ({
    id: `large-${index}`,
    title: `Large ${index}`,
    url: `/large-${index}/`,
    degree: 0
  }));
  await page.route("**/assets/website/graph.v1.json", (route) => route.fulfill({
    contentType: "application/json",
    body: JSON.stringify({ schema_version: 1, nodes, edges: [] })
  }));
  await page.goto(site("docs", "/docs/Getting%20Started/"));
  await page.locator("[data-context-panel]").getByRole("button", { name: "Open full graph" }).click();

  const view = page.locator('dialog[data-dialog="graph-global"] [data-graph-dialog-view]');
  await expect(view).toHaveAttribute("data-graph-ready", "fallback");
  await expect(view.locator("[data-graph-status]")).toContainText("too large");
  await expect(view.locator("[data-graph-canvas], .graph-node")).toHaveCount(0);
});

test("local graph zooms, pans, drags nodes without accidental navigation, and scales node area by degree", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop pointer graph assertion");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto(site("digital-garden", "/docs/Getting%20Started/"));
  const view = page.locator("[data-context-panel] [data-graph-view]");
  const svg = view.locator("svg");
  await expect(view).toHaveAttribute("data-graph-ready", "true");
  const radiiByDegree = await view.evaluate((container) => {
    const section = container.closest("[data-local-graph-section]")!;
    const template = section.querySelector<HTMLTemplateElement>("template[data-local-graph-data]")!;
    return [...template.content.querySelectorAll<HTMLElement>("[data-graph-node]")].map((source) => {
      const rendered = container.querySelector<SVGGElement>(`.graph-node[data-node-id="${CSS.escape(source.dataset.nodeId || "")}"]`);
      return [Number(source.dataset.nodeDegree), Number(rendered?.querySelector("circle")?.getAttribute("r"))] as const;
    }).sort((left, right) => left[0] - right[0]);
  });
  for (let index = 1; index < radiiByDegree.length; index += 1) {
    if (radiiByDegree[index]![0] > radiiByDegree[index - 1]![0]) {
      expect(radiiByDegree[index]![1]).toBeGreaterThan(radiiByDegree[index - 1]![1]);
    }
  }

  const box = await svg.boundingBox();
  expect(box).not.toBeNull();
  const pageScroll = await page.evaluate(() => scrollY);
  await page.mouse.move(box!.x + box!.width * 0.75, box!.y + box!.height * 0.75);
  await page.mouse.wheel(0, -220);
  await expect.poll(async () => Number(await view.getAttribute("data-graph-scale"))).toBeGreaterThan(1);
  expect(await page.evaluate(() => scrollY)).toBe(pageScroll);

  const viewport = view.locator(".graph-viewport");
  const transformBeforePan = await viewport.getAttribute("transform");
  await page.mouse.move(box!.x + 8, box!.y + box!.height - 8);
  await page.mouse.down();
  await page.mouse.move(box!.x + 48, box!.y + box!.height - 38, { steps: 4 });
  await page.mouse.up();
  await expect.poll(async () => viewport.getAttribute("transform")).not.toBe(transformBeforePan);

  const currentNode = view.locator(".graph-node--current");
  const currentTransform = await currentNode.getAttribute("transform");
  const currentBox = await currentNode.boundingBox();
  await page.mouse.move(currentBox!.x + currentBox!.width / 2, currentBox!.y + currentBox!.height / 2);
  await page.mouse.down();
  await page.mouse.move(currentBox!.x + currentBox!.width / 2 + 24, currentBox!.y + currentBox!.height / 2 + 18, { steps: 4 });
  await page.mouse.up();
  expect(await currentNode.getAttribute("transform")).toBe(currentTransform);

  const target = view.locator(".graph-node[role='link']").first();
  const targetUrl = new URL((await target.getAttribute("data-node-url"))!, page.url()).href;
  const targetBox = await target.boundingBox();
  const urlBeforeDrag = page.url();
  await page.mouse.move(targetBox!.x + targetBox!.width / 2, targetBox!.y + targetBox!.height / 2);
  await page.mouse.down();
  await page.mouse.move(targetBox!.x + targetBox!.width / 2 + 24, targetBox!.y + targetBox!.height / 2 + 18, { steps: 4 });
  await page.mouse.up();
  await page.waitForTimeout(50);
  expect(page.url()).toBe(urlBeforeDrag);

  await page.reload();
  const resetView = page.locator("[data-context-panel] [data-graph-view]");
  await expect(resetView).toHaveAttribute("data-graph-ready", "true");
  const clickableTarget = resetView.locator(".graph-node[role='link']").first();
  expect(new URL((await clickableTarget.getAttribute("data-node-url"))!, page.url()).href).toBe(targetUrl);
  await clickableTarget.click();
  await expect(page).toHaveURL(targetUrl);
});

test("graph nodes support keyboard navigation and preview bodies scroll to the end", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop keyboard and wheel assertion");
  await page.goto(site("docs"));
  const previewLink = page.locator(".website-link[data-note-id='docs/Customization.md']").first();
  await previewLink.evaluate((element) => element.scrollIntoView({ block: "center", behavior: "instant" as ScrollBehavior }));
  await expect(previewLink).toBeInViewport();
  await previewLink.focus();
  const previewBody = page.locator("[data-note-preview] .note-preview__body");
  await expect(previewBody).toHaveAttribute("data-preview-body-ready", "true");
  expect(await previewBody.evaluate((element) => element.scrollHeight)).toBeGreaterThan(
    await previewBody.evaluate((element) => element.clientHeight)
  );
  await previewBody.hover();
  for (let index = 0; index < 20; index += 1) {
    await page.mouse.wheel(0, 1000);
    await page.waitForTimeout(20);
  }
  const previewScroll = await previewBody.evaluate((element) => ({
    maximum: element.scrollHeight - element.clientHeight,
    scrollTop: element.scrollTop
  }));
  expect(previewScroll.scrollTop).toBe(previewScroll.maximum);

  await page.goto(site("docs", "/docs/Getting%20Started/"));
  const target = page.locator("[data-context-panel] .graph-node[role='link']").first();
  const id = await target.getAttribute("data-node-id");
  const expectedPath = await page.locator("[data-local-graph-section]").evaluate((section, nodeId) =>
    section.querySelector<HTMLTemplateElement>("template[data-local-graph-data]")?.content
      .querySelector<HTMLElement>(`[data-node-id="${CSS.escape(nodeId || "")}"]`)?.dataset.nodeUrl,
  id);
  await target.focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(new RegExp(`${expectedPath!.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`));
});

test("expanded graph supports touch panning and pinch zoom", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile touch graph assertion");
  await page.goto(site("docs", "/docs/Getting%20Started/"));
  await page.getByRole("button", { name: "Context" }).tap();
  await page.getByRole("button", { name: "Expand local graph" }).tap();
  const view = page.locator('[data-graph-dialog-view="local"]');
  await expect(view).toHaveAttribute("data-graph-ready", "true");
  const result = await view.locator("svg").evaluate(async (svg) => {
    const point = (id: number, x: number, y: number) => new Touch({ identifier: id, target: svg, clientX: x, clientY: y });
    const fire = (type: string, touches: Touch[], changedTouches = touches) => svg.dispatchEvent(new TouchEvent(type, {
      bubbles: true,
      cancelable: true,
      touches,
      targetTouches: touches,
      changedTouches
    }));
    const viewport = svg.querySelector(".graph-viewport")!;
    const beforePan = viewport.getAttribute("transform");
    fire("touchstart", [point(1, 50, 50)]);
    fire("touchmove", [point(1, 90, 80)]);
    fire("touchend", [], [point(1, 90, 80)]);
    const afterPan = viewport.getAttribute("transform");
    await new Promise((resolve) => setTimeout(resolve, 550));
    const beforeScale = Number(svg.closest<HTMLElement>("[data-graph-dialog-view]")?.dataset.graphScale);
    fire("touchstart", [point(1, 90, 90), point(2, 150, 90)]);
    fire("touchmove", [point(1, 60, 90), point(2, 180, 90)]);
    fire("touchend", [], [point(1, 60, 90), point(2, 180, 90)]);
    const afterScale = Number(svg.closest<HTMLElement>("[data-graph-dialog-view]")?.dataset.graphScale);
    return { beforePan, afterPan, beforeScale, afterScale };
  });
  expect(result.afterPan).not.toBe(result.beforePan);
  expect(result.afterScale).toBeGreaterThan(result.beforeScale);
  expect(await page.locator('dialog[data-dialog="graph-local"]').evaluate((dialog) => dialog.scrollWidth <= dialog.clientWidth)).toBe(true);
});

test("color scheme state uses the neutral public contract", async ({ page }) => {
  await page.goto(site("blog"));
  await page.locator("[data-color-scheme-toggle]").click();
  await expect(page.locator("html")).toHaveAttribute("data-color-scheme", /light|dark/);
  expect(
    await page.evaluate(() => localStorage.getItem("website:color-scheme"))
  ).toMatch(/light|dark/);
  expect(await page.evaluate(() => localStorage.getItem("garden-theme"))).toBeNull();
});

test("blog comments load the managed Giscus client without breaking narrow layouts", async ({ page }) => {
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
  await expect.poll(() => requestedClient).toBe(true);
  const client = comments.locator("script[data-website-comments-client]");
  await expect(client).toHaveAttribute("src", "https://giscus.app/client.js");
  await expect(client).toHaveAttribute("data-mapping", "specific");
  await expect(client).toHaveAttribute("data-strict", "1");
  await expect(client).toHaveAttribute("data-loading", "lazy");
  await expect(client).toHaveAttribute("data-theme", "dark");
  await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
  expect(await comments.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);

  const results = await new AxeBuilder({ page }).include(".website-comments").analyze();
  expect(results.violations).toEqual([]);
});

test("blog comments remain usable when the Giscus client is unavailable", async ({ page }) => {
  await page.route("https://giscus.app/client.js", (route) => route.abort());
  await page.goto("/__fixture__/comments/");

  const comments = page.getByRole("region", { name: "Comments" });
  await expect(comments).toHaveAttribute("data-website-comments-state", "unavailable");
  await expect(comments.getByText("Comments could not be loaded.")).toBeVisible();
  await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
  await expect(page.locator("main")).toBeVisible();
});

test("every theme follows dark preference and supports an explicit light override", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(() => localStorage.removeItem("website:color-scheme"));
  for (const theme of ["blog", "docs", "digital-garden"] as const) {
    await page.goto(site(theme));
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "dark");
    await page.locator("[data-color-scheme-toggle]").click();
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
  }
});

test("enabled taxonomy and feed routes stay discoverable without a graph tab", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop primary navigation assertion");
  for (const theme of ["blog", "docs", "digital-garden"] as const) {
    await page.goto(`/__fixture__/features/${theme}/navigation/`);
    const primary = page.getByRole("navigation", { name: "Primary navigation" });
    for (const route of ["/tags/", "/feed.xml"] as const) {
      await expect(primary.locator(`a[href="${route}"]`)).toHaveCount(1);
    }
    await expect(primary.locator('a[href="/graph/"]')).toHaveCount(0);
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
  for (const route of ["/tags/", "/feed.xml"] as const) {
    await expect(dialog.locator(`a[href="${route}"]`)).toHaveCount(1);
  }
  await expect(dialog.locator('a[href="/graph/"]')).toHaveCount(0);
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
  await page.goto(site("docs"));
  const article = page.locator("main > article");
  const browse = page.locator("main > .docs-home-browse");
  await expect(article).toContainText("One Obsidian vault, three intentional ways to publish it");
  await expect(browse.getByRole("heading", { name: "Browse the handbook" })).toBeVisible();
  await expect(browse.getByRole("link", { name: "Documentation" })).toBeVisible();
  await expect(page.locator("main > article + .docs-home-browse")).toHaveCount(1);
});

test("digital garden home follows authored content with server-rendered ways to explore", async ({ page }) => {
  await page.goto(site("digital-garden"));
  const article = page.locator("main > article");
  const overview = page.locator("main > .garden-home-overview");
  await expect(article).toContainText("One Obsidian vault, three intentional ways to publish it");
  await expect(overview.getByRole("heading", { name: "Explore the garden" })).toBeVisible();
  for (const name of ["Notes", "Tags"] as const) {
    await expect(overview.getByRole("link", { name: new RegExp(`^${name}`) })).toBeVisible();
  }
  await expect(overview.getByRole("link", { name: /^Graph/ })).toHaveCount(0);
  await expect(page.locator("main > article + .garden-home-overview")).toHaveCount(1);
});

test("frontend identifiers are neutral outside the garden visual shell", async ({ page }) => {
  await page.goto(site("digital-garden", "/docs/Syntax/"));
  expect(await page.locator("meta[name^='website:']").count()).toBeGreaterThan(0);
  await expect(page.locator("meta[name^='obsidian:'], [class*='obsidian-'], [src^='/assets/obsidian/'], [href^='/assets/obsidian/']"))
    .toHaveCount(0);
  expect(await page.evaluate(() => Array.from(document.querySelectorAll("*")).flatMap((element) =>
    Array.from(element.attributes, (attribute) => attribute.name)
  ).filter((name) => name.startsWith("data-obsidian-") || name === "data-obsidian"))).toEqual([]);
  await expect(page.locator("[data-garden-dialog], .garden-dialog, .garden-link, .garden-embed"))
    .toHaveCount(0);
  await expect(page.locator(".website-link").first()).toBeVisible();
  await expect(page.locator(".website-embed").first()).toBeVisible();
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
      await page.goto(site(theme));
      await expect(page.locator("main article")).toBeVisible();
      await expect(page.getByRole("navigation").first()).toBeVisible();
      await expect(page.locator(".mobile-toolbar")).toBeHidden();
    });
  }

  test("docs language links remain usable", async ({ page }) => {
    await page.goto(localizedDocs("/zh-CN/docs/Getting%20Started/"));
    const switcher = page.locator("[data-language-switcher]");
    await switcher.locator("summary").click();
    await switcher.getByRole("link", { name: "English" }).click();
    await expect(page).toHaveURL(/\/__site__\/docs-i18n\/docs\/Getting%20Started\/$/);
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
  });

  test("blog comments retain the GitHub Discussions fallback", async ({ page }) => {
    await page.goto("/__fixture__/comments/");
    const comments = page.getByRole("region", { name: "Comments" });
    await expect(comments).toBeVisible();
    await expect(comments.locator("script[data-website-comments-client]")).toHaveCount(0);
    await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
  });

  test("non-default context features have a mobile server-rendered fallback", async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "mobile-chromium", "mobile fallback assertion");
    for (const theme of ["blog", "docs", "digital-garden"] as const) {
      await page.goto(`/__fixture__/features/${theme}/relations/`);
      await expect(page.locator("[data-context-panel]")).toBeVisible();
      await expect(page.getByRole("heading", { name: "Backlinks" })).toBeVisible();
    }
  });
});
