import { expect, test, type Page } from "@playwright/test";
import { archiveReady } from "./archive-helpers";

test('header reserves archive actions only on sites with archive pages', async ({ page }) => {
  for (const route of ['/__site__/minimal/', '/__site__/minimal/docs/Getting%20Started/', '/__site__/docs/']) {
    await page.goto(route);
    await expect(page.locator('[data-page-header-actions]')).toHaveCount(0);
  }
  for (const route of ['/__site__/minimal-archive/', '/__site__/minimal-archive/plain/']) {
    await page.goto(route);
    await expect(page.locator('[data-page-header-actions]')).toHaveCount(1);
  }
});

async function tab(page: Page, href: string, mobile: boolean) {
  if (mobile) await page.locator('[data-dialog-open="browse"]').click();
  const navigation = mobile ? page.locator('dialog[data-dialog="browse"]') : page.locator(".site-header");
  const link = navigation.locator(`[data-navigation-id] a[href="${href}"]`);
  if (!mobile && !await link.isVisible()) await navigation.locator('[data-priority-navigation-more] summary').click();
  await link.click();
  await expect(page).toHaveURL(href);
}

async function headerGeometry(page: Page) {
  return page.locator('.site-header').evaluate(header =>
    [...header.querySelectorAll<HTMLElement>('.site-mark, [data-navigation-label], [data-search-open], [data-language-switcher], [data-color-scheme-toggle]')]
      .filter(node => node.getBoundingClientRect().width > 0)
      .map(node => { const { x, y, width, height } = node.getBoundingClientRect(); return [x, y, width, height]; }));
}

for (const locale of ["en", "zh-CN"]) {
  const root = "/__site__/minimal-archive/" + (locale === "en" ? "" : locale + "/");
  test(`tab navigation preserves the header in ${locale}`, async ({ page, isMobile }) => {
    await page.goto(root);
    await archiveReady(page);
    await expect(page.locator('[data-priority-navigation]')).toHaveAttribute('data-page-navigation-ready', 'true');
    await page.locator(".site-header").evaluate(header => header.setAttribute("data-shell-instance", "original"));
    const geometry = await headerGeometry(page);
    const documents: string[] = [];
    page.on('request', request => { if (request.isNavigationRequest()) documents.push(request.url()); });
    for (const destination of ["news/", "tools/", "favorites/", "plain/", ""]) {
      const html = await (await page.request.get(root + destination)).text();
      const canonical = html.match(/<link rel="canonical" href="([^"]+)"/)![1];
      await tab(page, root + destination, isMobile);
      const archiveIndex = html.match(/data-archive-current-url="([^"]+)"/)?.[1];
      if (archiveIndex) await expect(page.locator('[data-paged-archive]')).toHaveAttribute('data-archive-current-url', archiveIndex);
      else await expect(page.locator('[data-paged-archive]')).toHaveCount(0);
      await expect(page.locator('[data-favorites-page]')).toHaveCount(destination === 'favorites/' ? 1 : 0);
      if (destination !== 'plain/') await archiveReady(page);
      await expect(page.locator(".site-header")).toHaveAttribute("data-shell-instance", "original");
      await expect(page.locator(".site-navigation a[aria-current=page]")).toHaveAttribute("href", root + destination);
      await expect(page.locator('main')).toBeFocused();
      expect(await headerGeometry(page)).toEqual(geometry);
      await expect(page.locator('[data-archive-export-open]')).toHaveCount(['favorites/', 'plain/'].includes(destination) ? 0 : 1);
      expect(await page.locator('link[rel=canonical]').getAttribute('href')).toBe(canonical);
    }
    await page.goBack();
    await expect(page).toHaveURL(root + 'plain/');
    await expect(page.locator('main .tab-collection')).toBeVisible();
    await page.goForward(); await expect(page).toHaveURL(root); await archiveReady(page);
    await expect(page.locator('.site-header')).toHaveAttribute('data-shell-instance', 'original');
    expect(documents).toEqual([]);
    await page.locator('.site-header [data-search-open]').click();
    await expect(page.locator('[data-search-input]')).toBeFocused();
    await page.keyboard.press('Escape');
    await page.locator('[data-archive-reading-toggle]').click();
    await expect(page.locator('[data-archive-reading-toggle]')).toHaveAttribute('aria-checked', 'true');
    await expect(page.locator('[data-reading-loaded]').first()).toBeVisible();
    await page.locator('[data-archive-export-open]').click();
    await expect(page.locator('dialog[data-dialog=export]')).toBeVisible();
  });
}

test('archive hydration keeps the initial header geometry', async ({ page }) => {
  let release!: () => void;
  const delayed = new Promise<void>(resolve => { release = resolve; });
  await page.route('**/archive-filters-*.js', async route => { await delayed; await route.continue(); });
  await page.goto('/__site__/minimal-archive/');
  await expect(page.locator('[data-priority-navigation]')).toHaveAttribute('data-page-navigation-ready', 'true');
  const geometry = await headerGeometry(page);
  release(); await archiveReady(page);
  expect(await headerGeometry(page)).toEqual(geometry);
});

test('tab history leaves archive query history to the active archive', async ({ page, isMobile }) => {
  const root = '/__site__/minimal-archive/';
  await page.goto(root); await archiveReady(page);
  await page.locator('main').evaluate(main => main.dataset.originalArchive = 'true');
  await page.locator('[data-archive-page=next]').click(); await archiveReady(page);
  await tab(page, root + 'news/', isMobile); await archiveReady(page);
  await page.goBack(); await expect(page).toHaveURL(root + '?page=2'); await archiveReady(page);
  await expect(page.locator('.blog-ledger__main strong')).toHaveText(['Oldest']);
  await page.locator('main').evaluate(main => main.dataset.originalArchive = 'returned');
  await page.goBack(); await archiveReady(page);
  await expect(page.locator('main')).toHaveAttribute('data-original-archive', 'returned');
  await expect(page.locator('.blog-ledger__main strong')).toHaveText(['Newest', 'Middle']);
});

test('a slower tab cannot replace the latest selection', async ({ page, isMobile }) => {
  const root = '/__site__/minimal-archive/';
  await page.goto(root); await archiveReady(page);
  let release!: () => void;
  const delayed = new Promise<void>(resolve => { release = resolve; });
  await page.route('**/minimal-archive/news/', async route => { await delayed; await route.continue().catch(() => {}); });
  if (isMobile) await page.locator('[data-dialog-open=browse]').click();
  const navigation = isMobile ? page.locator('dialog[data-dialog=browse]') : page.locator('.site-header');
  await navigation.locator(`a[href="${root}news/"]`).click();
  await navigation.locator(`a[href="${root}tools/"]`).click();
  await expect(page).toHaveURL(root + 'tools/'); await archiveReady(page);
  release();
  await expect(page.locator('.blog-ledger__main strong')).toHaveText(['Middle']);
});

for (const theme of ['minimal', 'docs']) test(`${theme} custom tabs retain header and document navigation`, async ({ page, isMobile }) => {
  const root = `/__site__/${theme}-navigation/`;
  await page.goto(root + 'docs/one/');
  await expect(page.locator('[data-priority-navigation]')).toHaveAttribute('data-page-navigation-ready', 'true');
  await page.locator('.site-header').evaluate(node => node.dataset.instance = 'original');
  await tab(page, root + 'projects/', isMobile);
  await expect(page.locator('main h1')).toHaveText('Projects');
  await tab(page, root + 'about/', isMobile);
  await expect(page.locator('main h1')).toHaveText('About');
  await page.goBack(); await expect(page.locator('main h1')).toHaveText('Projects');
  await page.goBack(); await expect(page.locator('main h1')).toHaveText('one');
  await expect(page.locator('.site-header')).toHaveAttribute('data-instance', 'original');
  if (isMobile) await page.locator('[data-dialog-open=browse]').click();
  const menu = page.locator(isMobile ? '.docs-tree--dialog' : '.docs-sidebar, .minimal-docs-sidebar');
  await menu.getByRole('link', { name: 'two', exact: true }).click();
  await expect(page.locator('main h1')).toHaveText('two');
  await expect(page.locator('.site-header')).toHaveAttribute('data-instance', 'original');
});

test('folded tabs keep More and shared controls in place', async ({ page, isMobile }) => {
  test.skip(isMobile, 'desktop overflow menu');
  await page.setViewportSize({ width: 960, height: 900 });
  const root = '/__site__/minimal-archive/';
  await page.goto(root); await archiveReady(page);
  await expect(page.locator('[data-priority-navigation-more]')).toBeVisible();
  const geometry = await headerGeometry(page);
  await tab(page, root + 'tools/', false); await archiveReady(page);
  expect(await headerGeometry(page)).toEqual(geometry);
  await expect(page.locator('[data-priority-navigation-more]')).toHaveAttribute('data-has-current', 'true');
  await tab(page, root, false); await archiveReady(page);
  expect(await headerGeometry(page)).toEqual(geometry);
  await expect(page.locator('[data-priority-navigation-more]')).not.toHaveAttribute('data-has-current');
});
