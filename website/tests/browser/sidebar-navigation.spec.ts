import { expect, test } from "@playwright/test";

for (const theme of ["minimal", "docs"]) {
  const root = `/__site__/${theme}-sidebar/`;
  test(`${theme} sidebar preserves global controls and updates document navigation`, async ({ page, isMobile }) => {
    await page.goto(root + 'docs/one/');
    await expect(page.locator('[data-site-navigation]')).toHaveAttribute('data-page-navigation-ready', 'true');
    await page.locator('[data-site-chrome]').evaluate(node => node.dataset.instance = 'original');
    await page.locator('.site-topbar').evaluate(node => node.dataset.instance = 'original');
    const shell = await page.locator('.minimal-shell, .docs-shell').elementHandle();
    const navigate = async (href: string) => {
      if (isMobile) await page.locator('.site-topbar [data-dialog-open=browse]').click();
      await page.locator(`.site-sidebar__panel a[href="${root}${href}"]`).click();
      await expect(page).toHaveURL(root + href);
      await expect(page.locator('main')).toBeFocused();
      await expect(page.locator('dialog[data-dialog=browse]')).not.toBeVisible();
    };
    const requests: string[] = [];
    page.on('request', request => { if (request.isNavigationRequest()) requests.push(request.url()); });
    await navigate('docs/two/');
    expect(await shell!.evaluate(node => node.isConnected)).toBe(true);
    await expect(page.locator('[data-docs-navigation] a[aria-current=page]')).toHaveAttribute('href', root + 'docs/two/');
    await navigate('projects/');
    await expect(page.locator('[data-site-navigation] a[aria-current=page]')).toHaveAttribute('href', root + 'projects/');
    await expect(page.locator('[data-sidebar-docs] nav')).toHaveCount(theme === 'minimal' ? 0 : 1);
    await page.goBack();
    await expect(page.locator('h1')).toHaveText('two');
    await expect(page.locator('[data-sidebar-docs] nav')).toHaveCount(1);
    await expect(page.locator('[data-site-chrome]')).toHaveAttribute('data-instance', 'original');
    await expect(page.locator('.site-topbar')).toHaveAttribute('data-instance', 'original');
    expect(requests).toEqual([]);
  });

  test(`${theme} sidebar fits narrow and wide viewports in both color schemes`, async ({ page, isMobile }) => {
    test.skip(isMobile, 'explicit viewport matrix');
    test.setTimeout(120_000);
    for (const scheme of ['light', 'dark'] as const) {
      await page.emulateMedia({ colorScheme: scheme });
      for (const width of [320, 390, 768, 1080, 1081, 1320, 1321, 1440]) {
        await page.setViewportSize({ width, height: 900 });
        await page.goto(root + 'docs/one/');
        await expect(page.locator('[data-site-navigation]')).toHaveAttribute('data-page-navigation-ready', 'true');
        await expect(page.locator('.docs-sidebar, .minimal-docs-sidebar')).toHaveCount(0);
        await expect(page.locator('.site-topbar [data-search-open]')).toBeVisible();
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
        const main = (await page.locator('main').boundingBox())!;
        if (width > 1080) {
          await expect(page.locator('.site-sidebar')).toBeVisible();
          expect((await page.locator('.site-sidebar').boundingBox())!.width).toBe(240);
          expect(main.x).toBeGreaterThanOrEqual(240);
        } else {
          const opener = page.locator('.site-topbar [data-dialog-open=browse]');
          await opener.click();
          const drawer = page.locator('dialog[data-dialog=browse]');
          await expect(drawer).toBeVisible();
          await expect(opener).toHaveAttribute('aria-expanded', 'true');
          expect((await drawer.boundingBox())!.x).toBe(0);
          expect((await drawer.boundingBox())!.width).toBe(Math.min(320, width - 48));
          await page.screenshot({ path: test.info().outputPath(`${theme}-${scheme}-${width}-drawer.png`) });
          await page.keyboard.press('Escape');
          await expect(opener).toBeFocused();
          await expect(opener).toHaveAttribute('aria-expanded', 'false');
        }
        const context = page.locator('.content-toolbar__context');
        if (width <= 1320) {
          await expect(context).toBeVisible();
          await context.click();
          await expect(page.locator('dialog[data-dialog=context] [data-context-panel]')).toBeVisible();
          await page.keyboard.press('Escape');
        } else {
          await expect(context).not.toBeVisible();
          await expect(page.locator('.content-toolbar')).toHaveCSS('display', 'none');
        }
        await page.screenshot({ path: test.info().outputPath(`${theme}-${scheme}-${width}.png`) });
      }
    }
  });

  test(`${theme} drawer moves one control set, closes for search and restores across resize`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(root);
    const opener = page.locator('.site-topbar [data-dialog-open=browse]');
    await expect(page.locator('[data-search-open]')).toHaveCount(1);
    await expect(page.locator('.site-sidebar [data-search-open]')).toHaveCount(0);
    await page.locator('.site-topbar [data-search-open]').click();
    await expect(page.locator('dialog[data-dialog=browse]')).not.toBeVisible();
    await expect(page.locator('[data-search-input]')).toBeFocused();
    await page.keyboard.press('Escape');
    await opener.click();
    await page.keyboard.press('Control+k');
    await expect(page.locator('dialog[data-dialog=browse]')).not.toBeVisible();
    await expect(page.locator('[data-search-input]')).toBeFocused();
    await page.keyboard.press('Escape');
    await opener.click();
    const scroller = page.locator('.site-sidebar__navigation');
    await scroller.evaluate(node => node.scrollTop = 90);
    await page.keyboard.press('Escape');
    await opener.click();
    await expect.poll(() => scroller.evaluate(node => node.scrollTop)).toBe(90);
    await page.keyboard.press('Shift+Tab');
    expect(await page.evaluate(() => Boolean(document.activeElement?.closest('dialog[data-dialog=browse]')))).toBe(true);
    await page.keyboard.press('Tab');
    await expect(page.locator('dialog[data-dialog=browse] [data-dialog-close]')).toBeFocused();
    await page.setViewportSize({ width: 1440, height: 900 });
    await expect(page.locator('dialog[data-dialog=browse]')).not.toBeVisible();
    await expect(page.locator('.site-topbar [data-search-open]')).toBeVisible();
    await expect(page.locator('html')).not.toHaveCSS('overflow', 'hidden');
    await page.setViewportSize({ width: 390, height: 844 });
    await opener.click();
    const drawerBounds = (await page.locator('dialog[data-dialog=browse]').boundingBox())!;
    const viewportWidth = await page.evaluate(() => document.documentElement.clientWidth);
    await page.mouse.click((drawerBounds.x + drawerBounds.width + viewportWidth) / 2, 400);
    await expect(page.locator('dialog[data-dialog=browse]')).not.toBeVisible();
    await expect(opener).toBeFocused();
    await opener.click();
    await page.locator(`[data-site-navigation] a[href="${root}"]`).click();
    await expect(page.locator('dialog[data-dialog=browse]')).not.toBeVisible();
  });

  test(`${theme} error page keeps the sidebar and topbar search`, async ({ page }) => {
    await page.goto(root + '404.html');
    await expect(page.locator('body')).toHaveAttribute('data-navigation-layout', 'sidebar');
    await expect(page.locator('.site-topbar [data-search-open]')).toBeVisible();
    await expect(page.locator('[data-site-navigation]')).toHaveCount(1);
    await expect(page.locator('main h1')).toContainText('not found');
  });

  test(`${theme} navigation remains usable without JavaScript`, async ({ browser }) => {
    const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 320, height: 800 } });
    const page = await context.newPage();
    await page.goto(root + 'docs/one/');
    await expect(page.locator('[data-site-navigation]')).toBeVisible();
    await expect(page.locator('[data-docs-navigation]')).toBeVisible();
    await expect(page.locator('.content-toolbar')).toHaveCSS('display', 'none');
    await page.locator(`[data-site-navigation] a[href="${root}projects/"]`).click();
    await expect(page.locator('h1')).toHaveText('Projects');
    await context.close();
  });

  test(`${theme} RTL sidebar keeps the drawer and language menu within the viewport`, async ({ page }) => {
    for (const width of [320, 390, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto(root + 'ar/docs/one/');
      await expect(page.locator('html')).toHaveAttribute('dir', 'rtl');
      if (width <= 1080) {
        await page.locator('.site-topbar [data-dialog-open=browse]').click();
        const bounds = (await page.locator('dialog[data-dialog=browse]').boundingBox())!;
        expect(bounds.x).toBeGreaterThan(0);
        expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
      }
      await page.locator('[data-language-switcher] summary').click();
      const panel = page.locator('.language-switcher__panel');
      await expect(panel).toBeVisible();
      const bounds = (await panel.boundingBox())!;
      expect(bounds.x).toBeGreaterThanOrEqual(0);
      expect(bounds.x + bounds.width).toBeLessThanOrEqual(width);
      await expect(panel.locator('a[lang=en]')).toHaveAttribute('href', root + 'docs/one/');
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    }
  });
}

test('Docs retains an unchanged sidebar tree and its scroll position across sections', async ({ page, isMobile }) => {
  const root = '/__site__/docs-sidebar/';
  await page.goto(root);
  await expect(page.locator('[data-site-navigation]')).toHaveAttribute('data-page-navigation-ready', 'true');
  if (isMobile) await page.locator('.site-topbar [data-dialog-open=browse]').click();
  const tree = await page.locator('[data-sidebar-docs] nav').elementHandle();
  const scroller = page.locator('.site-sidebar__navigation');
  await scroller.evaluate(node => node.scrollTop = 80);
  const scrollTop = await scroller.evaluate(node => node.scrollTop);
  await page.locator(`[data-site-navigation] a[href="${root}projects/"]`).click();
  await expect(page).toHaveURL(root + 'projects/');
  if (isMobile) await page.locator('.site-topbar [data-dialog-open=browse]').click();
  expect(await tree!.evaluate(node => node.isConnected)).toBe(true);
  await expect.poll(() => scroller.evaluate(node => node.scrollTop)).toBe(scrollTop);
});
