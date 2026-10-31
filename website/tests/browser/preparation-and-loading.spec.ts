import { expect, test, type Page } from "@playwright/test";

async function documentMenu(page: Page, mobile: boolean) {
  await expect(page.locator("[data-docs-navigation]").first()).toHaveAttribute("data-docs-navigation-ready", "true");
  if (mobile) {
    await page.getByRole("button", { name: "Browse", exact: true }).click();
    return page.locator('dialog[data-dialog="browse"] .docs-tree--dialog');
  }
  return page.locator(".docs-sidebar, .minimal-docs-sidebar");
}

for (const theme of ["minimal", "docs"]) {
  const root = `/__site__/${theme}-navigation`;
  for (const stage of ["module", "loading", "ready"]) test(`${theme} document navigation cleans up search during ${stage}`, async ({ page, isMobile }) => {
    await page.addInitScript(() => {
      const workers = { created: 0, terminated: 0 };
      (window as unknown as { searchWorkers: typeof workers }).searchWorkers = workers;
      const NativeWorker = window.Worker;
      window.Worker = class extends NativeWorker {
        constructor(url: string | URL, options?: WorkerOptions) { super(url, options); workers.created++; }
        override terminate() { workers.terminated++; super.terminate(); }
      };
    });
    let release!: () => void;
    const delayed = new Promise<void>(resolve => { release = resolve; });
    if (stage === "loading") await page.route('**/search.v1.json', async route => { await delayed; await route.continue().catch(() => {}); });
    if (stage === "module") await page.route('**/search-*.js', async route => { await delayed; await route.continue().catch(() => {}); });
    await page.goto(`${root}/docs/one/`);
    await page.locator('.site-header [data-search-open]').click();
    await expect(page.locator('[data-search-input]')).toBeFocused();
    if (stage === "ready") await expect(page.locator('dialog[data-dialog="search"]')).toHaveAttribute('data-search-ready', 'true');
    if (stage !== "module") await expect.poll(() => page.evaluate(() => (window as unknown as { searchWorkers: { created: number } }).searchWorkers.created)).toBe(1);
    await page.keyboard.press('Escape');
    const menu = await documentMenu(page, isMobile);
    await menu.getByRole('link', { name: 'two', exact: true }).click();
    await expect(page.locator('main')).toBeFocused();
    await expect.poll(() => page.evaluate(() => (window as unknown as { searchWorkers: { terminated: number } }).searchWorkers.terminated)).toBe(stage === "module" ? 0 : 1);
    release();
    await page.locator('.site-header [data-search-open]').click();
    await expect(page.locator('dialog[data-dialog="search"]')).toHaveAttribute('data-search-ready', 'true');
    expect(await page.evaluate(() => (window as unknown as { searchWorkers: { created: number, terminated: number } }).searchWorkers)).toEqual(stage === "module" ? { created: 1, terminated: 0 } : { created: 2, terminated: 1 });
  });
  test(`${theme} compiled custom tabs survive folding and mobile Browse`, async ({ page, isMobile }) => {
    await page.goto(`${root}/projects/`);
    const custom = ["about", "projects", "team", "contact", "examples", "community"];
    if (isMobile) {
      await page.getByRole("button", { name: "Browse", exact: true }).click();
      const menu = page.locator('dialog[data-dialog="browse"] [data-navigation-id]');
      for (const id of custom) await expect(menu.filter({ has: page.locator(`[href="${root}/${id}/"]`) })).toBeVisible();
      await expect(page.locator('dialog[data-dialog="browse"] a[aria-current="page"]')).toHaveText("Projects");
    } else {
      const navigation = page.locator(".site-header [data-priority-navigation]");
      await expect(navigation).toHaveAttribute("data-priority-navigation-ready", "true");
      await navigation.evaluate((element) => { (element as HTMLElement).style.cssText = "flex: 0 0 180px; max-inline-size: 180px;"; });
      const more = navigation.locator("[data-priority-navigation-more]");
      await expect(more).toBeVisible();
      await expect(more).toHaveAttribute("data-has-current", "true");
      await more.locator("summary").click();
      await expect(more.getByRole("link", { name: "Projects", exact: true })).toHaveAttribute("aria-current", "page");
      const ids = await navigation.locator("li[data-navigation-id]").evaluateAll((items) => items.map((item) => item.getAttribute("data-navigation-id")));
      expect(ids.filter((id) => custom.includes(id!))).toEqual(custom);
    }
  });

  test(`${theme} successful document replacement focuses main and preserves anchors and history`, async ({ page, isMobile }) => {
    await page.goto(`${root}/docs/one/`);
    await page.locator(".site-header").evaluate((header) => header.setAttribute("data-shell-instance", "same"));
    const menu = await documentMenu(page, isMobile);
    const link = menu.getByRole("link", { name: "two", exact: true });
    await link.evaluate((node) => { (node as HTMLAnchorElement).hash = "details"; });
    await link.click();
    await expect(page).toHaveURL(`${root}/docs/two/#details`);
    await expect(page.locator("main")).toBeFocused();
    await expect(page.locator("#details")).toBeInViewport();
    await expect(page.locator(".site-header")).toHaveAttribute("data-shell-instance", "same");
    await page.goBack();
    await expect(page).toHaveURL(`${root}/docs/one/`);
    await expect(page.locator("main")).toBeFocused();
    await expect(page.locator("main h1")).toHaveText("one");
    await expect(page.locator("main h1")).toBeInViewport();
  });

  test(`${theme} a stale document request cannot replace or focus the next page`, async ({ page, isMobile }) => {
    await page.goto(`${root}/docs/one/`);
    let release!: () => void;
    const delayed = new Promise<void>((resolve) => { release = resolve; });
    await page.route(`**${root}/docs/two/`, async (route) => { await delayed; await route.continue().catch(() => undefined); });
    const menu = await documentMenu(page, isMobile);
    await menu.locator(`a[href="${root}/docs/two/"]`).click();
    await menu.locator(`a[href="${root}/docs/three/"]`).click();
    await expect(page).toHaveURL(`${root}/docs/three/`);
    await expect(page.locator("main")).toBeFocused();
    release();
    await expect(page.locator("main h1")).toHaveText("three");
    await expect(page.locator("main")).toBeFocused();
  });

  test(`${theme} pages without archive or favorites markers do not request their modules`, async ({ page }) => {
    const requested: string[] = [];
    page.on("request", (request) => requested.push(request.url()));
    await page.goto(`${root}/docs/one/`);
    await expect(page.locator("[data-graph-view]").first()).toHaveAttribute("data-graph-ready", "true");
    expect(requested.filter((url) => /\/(archive-filters|favorite-controls)-/.test(url))).toEqual([]);
  });

  test(`${theme} search focuses before a slow worker and does not reclaim focus after closing`, async ({ page }) => {
    let release!: () => void;
    const delayed = new Promise<void>((resolve) => { release = resolve; });
    await page.route("**/search-worker-*.js", async (route) => { await delayed; await route.continue(); });
    await page.goto(`${root}/docs/one/`);
    await page.locator(".site-header [data-search-open]").click();
    const dialog = page.locator('dialog[data-dialog="search"]');
    await expect(dialog.locator("input")).toBeFocused();
    await expect(dialog.locator("kbd")).toHaveText("Ctrl/⌘ K");
    await page.keyboard.press("Escape");
    await page.locator("main").focus();
    release();
    await expect(dialog).toHaveAttribute("data-search-ready", "true");
    await expect(page.locator("main")).toBeFocused();
  });

  test(`${theme} a failed search import retries on the next open`, async ({ page }) => {
    let requests = 0;
    await page.route('**/search-*.js', async route => {
      if (/\/search-worker-/.test(route.request().url())) return route.continue();
      if (++requests === 1) await route.fulfill({ status: 503, body: '' });
      else await route.continue();
    });
    await page.goto(`${root}/docs/one/`);
    const opener = page.locator('.site-header [data-search-open]');
    const dialog = page.locator('dialog[data-dialog="search"]');
    await opener.click();
    await expect(dialog.locator('[data-search-status]')).toContainText('Reload');
    await page.keyboard.press('Escape');
    await opener.click();
    await expect(dialog).toHaveAttribute('data-search-ready', 'true');
    expect(requests).toBe(2);
    await expect(dialog.locator('input')).toBeFocused();
  });

  test(`${theme} a failed graph import retries after document navigation`, async ({ page, isMobile }) => {
    let requests = 0;
    await page.route('**/graph-*.js', async route => {
      if (++requests === 1) await route.fulfill({ status: 503, body: '' });
      else await route.continue();
    });
    await page.goto(`${root}/docs/one/`);
    await expect(page.locator('html')).toHaveAttribute('data-graph-error', 'true');
    const navigation = await documentMenu(page, isMobile);
    await navigation.locator(`a[href="${root}/docs/two/"]`).click();
    await expect(page.locator('[data-context-panel] [data-graph-view]')).toHaveAttribute('data-graph-ready', 'true');
    await expect(page.locator('html')).not.toHaveAttribute('data-graph-error', 'true');
    expect(requests).toBe(2);
  });

  test(`${theme} editing a query retries a failed search worker in the open dialog`, async ({ page }) => {
    let requests = 0;
    await page.route('**/search.v1.json', async route => {
      if (++requests === 1) await route.fulfill({ status: 503, body: '' });
      else await route.continue();
    });
    await page.goto(`${root}/docs/one/`);
    await page.locator('.site-header [data-search-open]').click();
    const dialog = page.locator('dialog[data-dialog="search"]');
    const input = dialog.locator('input');
    await expect(dialog.locator('[data-search-status]')).toContainText('Edit your query');
    await input.fill('two');
    await expect(dialog).toHaveAttribute('data-search-ready', 'true');
    await expect(dialog.locator('[data-search-results] a strong').first()).toHaveText('two');
    await expect(dialog.locator('[data-search-results] a .search-result__excerpt').first()).not.toBeEmpty();
    await expect(input).toBeFocused();
    expect(requests).toBe(2);
  });

  test(`${theme} mobile compact graphs allow native scrolling`, async ({ page, isMobile, context }) => {
    test.skip(!isMobile, 'Native touch gestures are checked in the mobile context.');
    await page.setViewportSize({ width: 393, height: 560 });
    await page.goto(`/__site__/${theme}/docs/Getting%20Started/`);
    await page.getByRole('button', { name: 'Context', exact: true }).tap();
    const panel = page.locator('dialog[data-dialog="context"]');
    const body = panel.locator('.website-dialog__body');
    const view = panel.locator('[data-graph-view]');
    await expect(view).toHaveAttribute('data-graph-ready', 'true');
    expect(await body.evaluate(node => node.scrollHeight - node.clientHeight)).toBeGreaterThan(100);
    const bounds = (await view.locator('svg').boundingBox())!;
    const client = await context.newCDPSession(page);
    const point = { x: bounds.x + 25, y: bounds.y + bounds.height - 25 };
    try {
      await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [point] });
      for (let step = 1; step <= 5; step++) {
        await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: point.x, y: point.y - step * 22 }] });
      }
      await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await expect.poll(() => body.evaluate(node => node.scrollTop)).toBeGreaterThan(30);
      await expect(view).toHaveAttribute('data-graph-scale', '1');
    } finally { await client.detach(); }
  });

  test(`${theme} mobile expanded graphs retain native pinch zoom`, async ({ page, isMobile, context }) => {
    test.skip(!isMobile, 'Native touch gestures are checked in the mobile context.');
    await page.goto(`${root}/docs/one/`);
    await page.getByRole('button', { name: 'Context', exact: true }).tap();
    const panel = page.locator('dialog[data-dialog="context"]');
    await expect(panel.locator('[data-graph-view]')).toHaveAttribute('data-graph-ready', 'true');
    await panel.locator('[data-graph-open="local"]').tap();
    const expanded = page.locator('[data-graph-dialog-view="local"]');
    await expect(expanded).toHaveAttribute('data-graph-ready', 'true');
    const client = await context.newCDPSession(page);
    try {
      const box = (await expanded.locator('svg').boundingBox())!;
      const center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
      const fingers = (distance: number) => [
        { id: 1, x: center.x - distance, y: center.y },
        { id: 2, x: center.x + distance, y: center.y }
      ];
      await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: fingers(30) });
      for (const distance of [40, 50, 60]) {
        await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: fingers(distance) });
      }
      await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await expect.poll(async () => Number(await expanded.getAttribute('data-graph-scale'))).toBeGreaterThan(1.2);
    } finally { await client.detach(); }
  });

  test(`${theme} graph wheel hints appear only when a fine pointer is available`, async ({ page, isMobile }) => {
    await page.goto(`${root}/docs/one/`);
    const context = page.locator("[data-context-panel]");
    if (await context.isHidden()) await page.getByRole("button", { name: "Context", exact: true }).click();
    await expect(context).toBeVisible();
    await expect(context.locator('[data-graph-view]')).toHaveAttribute('data-graph-ready', 'true');
    expect(await page.evaluate(() => matchMedia("(any-pointer: fine)").matches)).toBe(!isMobile);
    const hint = context.locator(".local-graph__hint");
    if (isMobile) await expect(hint).toBeHidden();
    else await expect(hint).toBeVisible();
    // A failed or unavailable viewer cannot act on the shortcut.
    await context.locator('[data-graph-view]').evaluate(node => { (node as HTMLElement).dataset.graphError = 'true'; });
    await expect(hint).toBeHidden();
  });

  test(`${theme} unavailable graph modules keep the shortcut hint hidden`, async ({ page }) => {
    await page.route('**/graph-*.js', route => route.abort());
    await page.goto(`${root}/docs/one/`);
    await expect(page.locator('html')).toHaveAttribute('data-graph-error', 'true');
    const context = page.locator('[data-context-panel]');
    if (await context.isHidden()) await page.getByRole('button', { name: 'Context', exact: true }).click();
    await expect(context.locator('.local-graph__hint')).toBeHidden();
    await expect(context.locator('[data-graph-fallback]')).toBeVisible();
  });

  test(`${theme} compact graphs require a modifier while expanded graphs zoom directly`, async ({ page, isMobile }) => {
    test.skip(isMobile, "Wheel input is checked on desktop; mobile graph dialogs remain covered separately.");
    await page.goto(`${root}/docs/one/`);
    const view = page.locator("[data-context-panel] [data-graph-view]");
    await expect(view).toHaveAttribute("data-graph-ready", "true");
    const svg = view.locator("svg");
    await svg.hover();
    await page.mouse.wheel(0, 200);
    await expect(view).toHaveAttribute("data-graph-scale", "1");
    await expect.poll(() => page.evaluate(() => scrollY)).toBeGreaterThan(0);
    await page.evaluate(() => scrollTo(0, 0));
    await svg.hover();
    await page.keyboard.down("Control");
    await page.mouse.wheel(0, -120);
    await page.keyboard.up("Control");
    await expect.poll(async () => Number(await view.getAttribute("data-graph-scale"))).toBeGreaterThan(1);
    await page.locator('[data-context-panel] [data-graph-open="local"]').click();
    const expanded = page.locator('[data-graph-dialog-view="local"]');
    await expanded.locator("svg").hover();
    await page.mouse.wheel(0, -120);
    await expect.poll(async () => Number(await expanded.getAttribute("data-graph-scale"))).toBeGreaterThan(1);
  });
}

for (const locale of ["en", "zh-CN"]) {
  const root = `/__site__/minimal-archive/${locale === "en" ? "" : "zh-CN/"}`;
  test(`archive without JavaScript keeps first-page links and explains the limit in ${locale}`, async ({ browser, viewport, isMobile }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, viewport, isMobile });
    const page = await context.newPage();
    try {
      await page.goto(`http://127.0.0.1:4173${root}`);
      await expect(page.locator("[data-archive-pagination]")).toBeHidden();
      await expect(page.locator(".archive-facet").first()).toBeHidden();
      await expect(page.locator("[data-timeline-nav]")).toBeHidden();
      await expect(page.getByRole('complementary', { name: 'Chronology' })).toHaveCount(0);
      await expect(page.locator('.archive-context')).toBeHidden();
      const layout = await page.locator('.minimal-shell').evaluate(node => {
        const style = getComputedStyle(node);
        return { display: style.display, columns: style.gridTemplateColumns };
      });
      if (layout.display === 'grid') expect(layout.columns.trim().split(/\s+/)).toHaveLength(1);
      else expect(layout.display).toBe('block');
      const facetLinks = page.locator('.blog-ledger__topics a[data-archive-facet], .blog-ledger__topics a[data-topic-filter-option]');
      for (const link of await facetLinks.all()) await expect(link).toBeHidden();
      await expect(page.locator(".blog-ledger__main").first()).toBeVisible();
      await expect(page.locator("noscript p")).toContainText(locale === "en" ? "first page" : "第一页");
      await expect(page.locator("noscript p")).toBeVisible();
    } finally { await context.close(); }
  });
}

test("delayed and failed archive imports leave static content and other controls usable", async ({ page }) => {
  let release!: () => void;
  const delayed = new Promise<void>((resolve) => { release = resolve; });
  await page.route("**/archive-filters-*.js", async (route) => { await delayed; await route.abort(); });
  await page.goto("/__site__/minimal-archive/", { waitUntil: "domcontentloaded" });
  await expect(page.locator('[data-archive-page="next"]')).toBeDisabled();
  await expect(page.locator(".blog-ledger__main").first()).toBeVisible();
  release();
  await expect(page.locator("[data-archive-status]")).toContainText("Reload");
  await page.locator(".site-header [data-search-open]").click();
  await expect(page.locator("[data-search-input]")).toBeFocused();
});

test("a failed favorites module reports the failure without losing the article", async ({ page }) => {
  await page.route("**/favorite-controls-*.js", (route) => route.abort());
  await page.goto("/__site__/minimal-archive/items/a/");
  await expect(page.locator("[data-favorite-status]")).toContainText("Reload");
  await expect(page.locator("main")).toContainText("First paragraph of Newest.");
  await page.locator(".site-header [data-search-open]").click();
  await expect(page.locator("[data-search-input]")).toBeFocused();
});
