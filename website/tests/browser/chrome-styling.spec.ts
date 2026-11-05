import { expect, test } from '@playwright/test';

for (const theme of ['minimal', 'docs']) {
  for (const colorScheme of ['light', 'dark'] as const) {
    test(`${theme} ${colorScheme} chrome stays quiet with visible keyboard focus`, async ({ page, isMobile }) => {
      await page.emulateMedia({ colorScheme });
      await page.goto(`/__site__/${theme}-sidebar/`);
      const background = await page.locator('body').evaluate(node => getComputedStyle(node).backgroundColor);
      await expect(page.locator('.site-topbar')).toHaveCSS('background-color', background);
      const search = page.locator('.site-topbar [data-search-open]');
      await expect(search).toHaveCSS('border-width', '0px');
      if (!isMobile) {
        await search.hover();
        await expect(search).toHaveCSS('border-width', '0px');
        const hoverContrast = await search.evaluate(node => {
          const canvas = document.createElement('canvas');
          canvas.width = canvas.height = 1;
          const context = canvas.getContext('2d')!;
          const luminance = (color: string) => {
            context.fillStyle = color;
            context.fillRect(0, 0, 1, 1);
            const [red = 0, green = 0, blue = 0] = [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).map(value => {
              const channel = value / 255;
              return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
            });
            return red * 0.2126 + green * 0.7152 + blue * 0.0722;
          };
          const resting = luminance(getComputedStyle(document.body).backgroundColor);
          // Painting over the page color also composites translucent hover backgrounds.
          const hovered = luminance(getComputedStyle(node).backgroundColor);
          return (Math.max(resting, hovered) + 0.05) / (Math.min(resting, hovered) + 0.05);
        });
        // Product feedback floor, not a WCAG contrast requirement for hover.
        expect(hoverContrast).toBeGreaterThan(1.15);
      }

      if (isMobile) await page.locator('.site-topbar [data-dialog-open=browse]').click();
      const current = page.locator('[data-site-navigation] a[aria-current=page]');
      await expect(current).toHaveCSS('box-shadow', 'none');
      const ink = await page.locator('body').evaluate(node => getComputedStyle(node).color);
      await expect(current).toHaveCSS('color', ink);
      const inactive = page.locator('[data-site-navigation] a:not([aria-current])').first();
      const inactiveStyle = await inactive.evaluate(node => {
        const style = getComputedStyle(node);
        return { background: style.backgroundColor, weight: Number(style.fontWeight) };
      });
      await expect(current).not.toHaveCSS('background-color', inactiveStyle.background);
      expect(await current.evaluate(node => Number(getComputedStyle(node).fontWeight))).toBeGreaterThan(inactiveStyle.weight);

      const toggle = page.locator('[data-color-scheme-toggle]');
      await toggle.click();
      await expect(toggle).toBeFocused();
      await expect(toggle).toHaveCSS('outline-style', 'none');
      await expect(toggle).toHaveCSS('box-shadow', 'none');
      await page.keyboard.press('Tab');
      await page.keyboard.press('Shift+Tab');
      await expect(toggle).toBeFocused();
      await expect(toggle).toHaveCSS('outline-width', '2px');
      await expect(toggle).toHaveCSS('box-shadow', 'none');
      if (isMobile) await page.keyboard.press('Escape');

      await search.click();
      const input = page.locator('[data-search-input]');
      await expect(input).toBeFocused();
      await expect(input).toHaveCSS('outline-style', 'none');
      await expect(input).toHaveCSS('box-shadow', 'none');
      const field = page.locator('.search-box');
      await expect(field).toHaveCSS('outline-style', 'none');
      const focusedBorder = await field.evaluate(node => getComputedStyle(node).borderColor);
      await page.keyboard.press('Tab');
      await expect(input).not.toBeFocused();
      await expect(field).not.toHaveCSS('border-color', focusedBorder);
    });

    test(`${theme} ${colorScheme} top header shares the page background`, async ({ page }) => {
      await page.emulateMedia({ colorScheme });
      await page.goto(`/__site__/${theme}/`);
      const background = await page.locator('body').evaluate(node => getComputedStyle(node).backgroundColor);
      await expect(page.locator('.site-header')).toHaveCSS('background-color', background);
    });
  }
}
