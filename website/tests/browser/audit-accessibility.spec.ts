import { expect, test, type Locator } from "@playwright/test";
import { archiveReady } from './archive-helpers';

async function expectFocusIndicator(control: Locator) {
  const unfocusedBorder = await control.evaluate(element => {
    const field = element.closest('.search-box');
    if (!field) return null;
    (element as HTMLElement).blur();
    return getComputedStyle(field).borderColor;
  });
  await control.focus();
  await expect.poll(() => control.evaluate((element, unfocusedBorder) => {
    const visibleOutline = (target: Element) => {
      const style = getComputedStyle(target);
      return style.outlineStyle !== 'none' && parseFloat(style.outlineWidth) >= 2;
    };
    const field = element.closest('.search-box');
    const fieldStyle = field && getComputedStyle(field);
    const fieldFocus = fieldStyle && fieldStyle.borderColor !== unfocusedBorder;
    return visibleOutline(element) || Boolean(field && (visibleOutline(field) || fieldFocus));
  }, unfocusedBorder)).toBe(true);
}

for (const forcedColors of ['none', 'active'] as const) {
  for (const theme of ['minimal', 'docs']) {
    test(`${theme} keyboard focus remains visible with forced colors ${forcedColors}`, async ({ page }) => {
      await page.emulateMedia({ forcedColors });
      await page.goto(`/__site__/${theme}/`);
      await page.keyboard.press('Tab');
      for (const selector of ['.site-mark', '[data-search-open]', '[data-color-scheme-toggle]', '.note-content a']) {
        await expectFocusIndicator(page.locator(selector).first());
      }
      await page.locator('[data-search-open]').first().press('Enter');
      await expectFocusIndicator(page.locator('[data-search-input]'));
      await expectFocusIndicator(page.locator('dialog[data-dialog="search"] [data-dialog-close]'));
    });
  }
  test(`graph, menus and archive controls keep visible keyboard focus with forced colors ${forcedColors}`, async ({ page, isMobile }) => {
    await page.emulateMedia({ forcedColors, reducedMotion: 'reduce' });
    await page.goto('/__site__/minimal-i18n/');
    await page.keyboard.press('Tab');
    await expectFocusIndicator(page.locator('[data-language-switcher] summary'));
    await page.locator('[data-language-switcher] summary').press('Enter');
    await expectFocusIndicator(page.locator('[data-language-switcher] a').last());
    await page.keyboard.press('Escape');
    if (isMobile) await page.getByRole('button', { name: 'Context', exact: true }).click();
    const graph = page.locator('[data-local-graph-section]');
    await expect(graph.locator('[data-graph-view]')).toHaveAttribute('data-graph-ready', 'true');
    await page.keyboard.press('Tab');
    await expectFocusIndicator(graph.locator('[data-graph-open=local]'));
    await expectFocusIndicator(graph.locator('.graph-node[tabindex="0"]'));
    const first = await graph.locator('.graph-node[tabindex="0"]').getAttribute('href');
    await page.keyboard.press('ArrowRight');
    await expect(graph.locator('.graph-node[tabindex="0"]')).toBeFocused();
    expect(await graph.locator('.graph-node[tabindex="0"]').getAttribute('href')).not.toBe(first);
    await expectFocusIndicator(graph.locator('[data-graph-fallback] summary'));
    await page.goto('/__site__/minimal-archive/');
    await archiveReady(page);
    await page.keyboard.press('Tab');
    await expectFocusIndicator(page.locator('[data-archive-reading-toggle]'));
    await expectFocusIndicator(page.locator('[data-favorite-toggle]').first());
    await expectFocusIndicator(page.locator('[data-archive-export-open]'));
    await page.locator('[data-archive-export-open]').press('Enter');
    await expectFocusIndicator(page.locator('dialog[data-dialog=export] [data-dialog-close]'));
  });
}

test('oversized shared filter selections are bounded and explained', async ({ page }) => {
  const query = new URLSearchParams();
  for (let i = 0; i < 200; i++) query.append('topic', `unknown-${i}`);
  await page.goto('/__site__/minimal-archive/?' + query);
  await archiveReady(page);
  expect(new URL(page.url()).searchParams.getAll('topic')).toHaveLength(16);
  await expect(page.locator('[data-archive-status]')).toContainText('16 values per facet');
});

test('dense graphs reveal additional labels on focus without adding sequential Tab stops', async ({ page, isMobile }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/__site__/minimal/docs/Getting%20Started/');
  if (isMobile) await page.getByRole('button', { name: 'Context', exact: true }).click();
  await page.locator('[data-graph-open=global]').click();
  const graph = page.locator('dialog[data-dialog=graph-global] [data-graph-dialog-view]');
  await expect(graph).toHaveAttribute('data-graph-ready', 'true');
  await expect(graph).toHaveAttribute('data-graph-dense', 'true');
  await expect(graph.locator('.graph-node[tabindex="0"]')).toHaveCount(1);
  const visibleCount = await graph.locator('.graph-node text').evaluateAll(labels => labels.filter(label => getComputedStyle(label).opacity !== '0').length);
  expect(visibleCount).toBeLessThanOrEqual(7);
  const extra = graph.locator('.graph-node:not(.graph-node--labelled, .graph-node--current)').first();
  await expect(extra.locator('text')).toHaveCSS('opacity', '0');
  await extra.focus();
  await expect(extra.locator('text')).toHaveCSS('opacity', '1');
  await expect(extra).toHaveAttribute('href', /\/__site__\/minimal\//);
  await expect(graph.locator('.graph-node[tabindex="0"]')).toHaveCount(1);
});
