import { test, expect, type Locator } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

async function visibleBox(element: Locator) {
  await expect(element).toBeVisible();
  const box = await element.boundingBox();
  expect(box).not.toBeNull();
  return box!;
}

for (const theme of ['minimal', 'docs']) {
  test(`${theme} footer stays usable in light and dark at responsive widths`, async ({ page, isMobile }, testInfo) => {
    if (isMobile) await page.setViewportSize({ width: 390, height: 844 });
    for (const colorScheme of ['light', 'dark'] as const) {
      await page.emulateMedia({ colorScheme, reducedMotion: 'reduce' });
      await page.goto(`/__site__/${theme}/`);
      await page.evaluate(() => document.fonts.ready);
      const footer = page.locator('.site-footer');
      await footer.scrollIntoViewIfNeeded();
      await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
      const toolbar = page.locator('.mobile-toolbar');
      if (await toolbar.isVisible()) {
        const top = (await visibleBox(toolbar)).y;
        for (const link of await footer.locator('a').all()) {
          const box = await visibleBox(link);
          expect(box.y + box.height).toBeLessThanOrEqual(top);
        }
      }
      const backToTop = page.locator('[data-back-to-top]');
      if (await backToTop.isVisible()) {
        const button = await visibleBox(backToTop);
        for (const item of await footer.locator('.site-footer__credit > *').all()) {
          const box = await visibleBox(item);
          const overlaps = box.x < button.x + button.width && box.x + box.width > button.x &&
            box.y < button.y + button.height && box.y + box.height > button.y;
          expect(overlaps, `${theme} ${colorScheme}: ${await item.textContent()}`).toBe(false);
        }
      }
      await footer.screenshot({ path: testInfo.outputPath(`footer-${colorScheme}.png`) });
    }
  });

  test(`${theme} footer shares navigation and contacts across pages`, async ({ page }) => {
    for (const route of ['/', '/docs/Customization/']) {
      await page.goto(`/__site__/${theme}${route}`);
      const footer = page.locator('.site-footer');
      await expect(page.locator('a[rel="me"]')).toHaveCount(2);
      await expect(footer.locator('a[rel="me"]')).toHaveCount(2);
      await expect(page.locator('main .site-contact')).toHaveCount(0);
      const sites = footer.getByRole('navigation', { name: 'Sites' });
      await expect(sites.getByRole('link', { name: 'Example Garden' })).toHaveAttribute('href', 'https://example.test/garden/');
      await expect(sites.locator('a[target]')).toHaveCount(0);
      await footer.scrollIntoViewIfNeeded();
      for (const link of await footer.locator('.site-footer__main a').all()) {
        expect((await visibleBox(link)).height).toBeGreaterThanOrEqual(44);
      }
      await sites.locator('a').focus();
      await page.keyboard.press('Tab');
      await expect(footer.locator('a:focus-visible')).toHaveCSS('outline-width', '2px');
      expect((await new AxeBuilder({ page }).include('.site-footer').analyze()).violations).toEqual([]);
    }
  });
}
