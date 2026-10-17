import { archiveReady, expandArchiveDays } from "./archive-helpers";
import { expect, test } from "@playwright/test";

for (const locale of ["en", "zh-CN"]) {
  const root = "/__site__/minimal-archive/" + (locale === "en" ? "" : locale + "/");

  test(`archive remains navigable after deployment discovery fails in ${locale}`, async ({ page }) => {
    await page.goto(root);
    const archive = page.locator('[data-paged-archive]'), titles = archive.locator('.blog-ledger__main strong');
    await expect(archive).not.toHaveAttribute('aria-busy');
    await page.route('**/archive/current.json', route => route.abort());
    await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true })));
    await expect(archive).not.toHaveAttribute('aria-busy');
    await expect(page.locator('[data-archive-status]')).toContainText(locale === 'en' ? 'Previously loaded' : '已加载');
    await expect(page.locator('[data-archive-page=next]')).toBeEnabled();
    await page.locator('[data-archive-page=next]').click();
    await expect(titles).toHaveText(['Oldest']);
    await page.locator('button[data-archive-facet=source][data-archive-value=hn]').click();
    await expect(titles).toHaveText(['Newest', 'Oldest']);
    await page.goBack();
    await expect(titles).toHaveText(['Oldest']);
    await page.unroute('**/archive/current.json');
    await page.locator('[data-archive-retry]').click();
    await expect(page.locator('[data-archive-status]')).toBeEmpty();
    await expect(page.locator('[data-archive-retry]')).toBeHidden();
  });

  test(`reading waits for offscreen rows and loads them after scrolling in ${locale}`, async ({ page }) => {
    await page.goto(root);
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/3.*1.*2/);
    await expandArchiveDays(page);
    // Model the height of long articles without depending on font metrics.
    await page.addStyleTag({ content: '[data-filter-item] { min-height: 200vh; }' });
    const requests: string[] = [];
    page.on('request', request => { if (/\/items\/[ab]\/$/.test(request.url())) requests.push(request.url()); });
    await page.locator('[data-archive-reading-toggle]').click();
    const readingSwitch = page.locator('[data-archive-reading-toggle]');
    await expect(readingSwitch).toHaveAttribute('title', locale === 'en' ? 'Read in full: on' : '平铺阅读：已开启');
    await expect(readingSwitch.locator('.site-action__reading-check')).toBeVisible();
    const rows = page.locator('[data-filter-item]');
    await expect(rows.first()).toHaveAttribute('data-reading-loaded', 'true');
    await expect(rows.last()).not.toHaveAttribute('data-reading-loaded');
    expect(requests).toEqual([new URL(root + 'items/a/', page.url()).href]);
    await rows.last().scrollIntoViewIfNeeded();
    await expect(rows.last()).toHaveAttribute('data-reading-loaded', 'true');
    expect(requests).toHaveLength(2);
  });

  test(`reading switch exposes both states without relying on color in ${locale}`, async ({ page }) => {
    await page.goto(root);
    const toggle = page.locator('[data-archive-reading-toggle]');
    await expect(toggle).toBeVisible();
    await expect(toggle).toHaveAttribute('title', locale === 'en' ? 'Read in full: off' : '平铺阅读：已关闭');
    await expect(toggle.locator('.site-action__reading-check')).toBeHidden();
    await archiveReady(page);
    await toggle.press('Space');
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    await expect(toggle.locator('.site-action__reading-check')).toBeVisible();
    await toggle.press('Space');
    await expect(toggle).toHaveAttribute('aria-checked', 'false');
    await expect(toggle.locator('.site-action__reading-check')).toBeHidden();
  });

  test(`saved reading starts once on the selected page and reuses bodies in ${locale}`, async ({ page }) => {
    await page.goto(root);
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/3.*1.*2/);
    await expandArchiveDays(page);
    await page.locator('[data-archive-reading-toggle]').click();
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    const articles: string[] = [], manifests: string[] = [];
    page.on('request', request => {
      if (/\/items\/[abc]\/$/.test(request.url())) articles.push(request.url());
      if (request.url().endsWith('/manifest.json')) manifests.push(request.url());
    });
    await page.goto(root + '?page=2');
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(1);
    expect(manifests).toHaveLength(1);
    expect(articles.map(url => new URL(url).pathname)).toEqual([root + 'items/c/']);
    await page.locator('[data-archive-page=prev]').click();
    await expandArchiveDays(page);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    await page.locator('[data-archive-page=next]').click();
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(1);
    expect(articles).toHaveLength(3);
  });

  test(`daily timeline resets pagination and combines with reading and facets in ${locale}`, async ({ page }, testInfo) => {
    await page.goto(root + '?page=2');
    const titles = page.locator('.blog-ledger__main strong');
    await expect(titles).toHaveText(['Oldest']);
    const mobile = testInfo.project.name === 'mobile-chromium';
    const openTimeline = async () => { if (mobile) await page.locator('[data-dialog-open="context"]:visible').click(); };
    const closeTimeline = async () => { if (mobile) await page.locator('[data-dialog="context"] [data-dialog-close]').click(); };
    await openTimeline();
    const days = page.locator('[data-day-filter-option]');
    await expect(days.locator('span:first-child')).toHaveText(['10-10', '10-09', '12-31']);
    await expect(days.locator('.archive-timeline__count')).toHaveText(['1', '1', '1']);
    await expect(page.locator('[data-month-filter-option]')).toHaveCount(0);
    const selected = page.locator('[data-day-filter-option][data-filter-day="2026-10-09"]');
    await selected.click();
    await expect(page).toHaveURL(root + '?day=2026-10-09');
    await expect(selected).toHaveAttribute('aria-current', 'page');
    await closeTimeline();
    await expect(titles).toHaveText(['Middle']);
    await expect(page.locator('[data-archive-page=next]')).toBeDisabled();
    await expandArchiveDays(page);
    await page.locator('[data-archive-reading-toggle]').click();
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(1);
    await expect(page.locator('.archive-reading__body')).toContainText('First paragraph of Middle.');
    await page.reload();
    await expect(titles).toHaveText(['Middle']);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(1);
    await page.locator('button[data-archive-facet=source][data-archive-value=hn]').click();
    await expect(page.locator('[data-archive-empty]')).toBeVisible();
    await expect(titles).toHaveCount(0);
    await page.goBack();
    await expect(titles).toHaveText(['Middle']);
    await openTimeline();
    await expect(selected).toHaveAttribute('aria-current', 'page');
    await page.locator('[data-year-filter-option][data-filter-year="2026"]').click();
    await expect(page).toHaveURL(root + '?year=2026');
    await expect(selected).not.toHaveAttribute('aria-current', 'page');
    await selected.click();
    await expect(page).toHaveURL(root + '?day=2026-10-09');
    await selected.click();
    await expect(page).toHaveURL(root);
    await closeTimeline();
    await expect(titles).toHaveText(['Newest', 'Middle']);
    await expandArchiveDays(page);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    await page.goto(root + '?day=2026-02-30');
    await expect(page.locator('[data-archive-empty]')).toBeVisible();
  });

  test(`paged archive filters, pagination, and history in ${locale}`, async ({ page }) => {
    await page.goto(root);
    const archive = page.locator("[data-paged-archive]");
    const titles = archive.locator("[data-filter-list] .blog-ledger__main strong");
    const status = archive.locator("[data-archive-page-status]");
    await expect(status).toHaveText(/3.*1.*2/);
    await expect(titles).toHaveText(["Newest", "Middle"]);
    await expect(archive.locator('.blog-ledger__description')).toHaveText(['Description of Newest', 'Description of Middle']);
    await expect(archive.locator("[data-archive-page=next]")).toBeEnabled();
    await archive.locator("[data-archive-page=next]").click();
    await expect(status).toHaveText(/3.*2.*2/);
    await expect(titles).toHaveText(["Oldest"]);
    await expect(page).toHaveURL(root + "?page=2");

    await page.goBack();
    await expect(status).toHaveText(/3.*1.*2/);
    await expect(titles).toHaveText(["Newest", "Middle"]);

    await archive.locator("button[data-archive-facet=source][data-archive-value=hn]").click();
    await expect(titles).toHaveText(["Newest", "Oldest"]);
    await expect(page).toHaveURL(root + "?source=hn");
    await archive.locator("button[data-archive-facet=topic][data-archive-value=tools]").click();
    await expect(archive.locator("[data-archive-empty]")).toBeVisible();
    await expect(titles).toHaveCount(0);
    await archive.locator("[data-archive-clear]").click();
    await expect(titles).toHaveText(["Newest", "Middle"]);

    await page.goto(root + "?topic=unknown");
    await expect(archive.locator("[data-archive-empty]")).toBeVisible();
    await expect(titles).toHaveCount(0);
  });

  test(`reading expands only the current page and follows filters in ${locale}`, async ({ page }) => {
    await page.goto(root);
    const toggle = page.getByRole('switch', { name: locale === 'en' ? 'Read in full' : '平铺阅读' });
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/3.*1.*2/);
    await expect(toggle).toHaveAttribute('aria-checked', 'false');
    await expandArchiveDays(page);
    await toggle.press('Space');
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    const bodies = page.locator('.archive-reading__body');
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    await expect(bodies.first()).toContainText('First paragraph of Newest.');
    await expect(bodies.first().getByRole('link', { name: 'link', exact: true })).toHaveAttribute('href', 'https://example.com/a');
    await page.locator('[data-archive-page=next]').click();
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(1);
    await expect(bodies).toContainText('First paragraph of Oldest.');
    await page.goBack();
    await expandArchiveDays(page);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    await page.locator('button[data-archive-facet=source][data-archive-value=hn]').click();
    await expandArchiveDays(page);
    await expect(bodies.last()).toContainText('First paragraph of Oldest.');
    await page.reload();
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
    await expandArchiveDays(page);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    await toggle.click();
    await expect(bodies.first()).toBeHidden();
    await expect(page.locator('.blog-ledger__description').first()).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  });

  test(`reading retries an article without losing the current ledger in ${locale}`, async ({ page }) => {
    await page.route('**/items/a/', route => route.abort());
    await page.goto(root);
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/3.*1.*2/);
    await expandArchiveDays(page);
    await page.locator('[data-archive-reading-toggle]').click();
    await expect(page.locator('[data-reading-retry]')).toBeVisible();
    await expect(page.locator('.blog-ledger__main strong')).toHaveText(['Newest', 'Middle']);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(1);
    await page.unroute('**/items/a/');
    await page.locator('[data-reading-retry]').click();
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
  });

  test(`paged archive preserves its first page on load failure and retries in ${locale}`, async ({ page }) => {
    await page.route("**/facet-*.json", route => route.abort());
    await page.goto(root + "?source=hn");
    const archive = page.locator("[data-paged-archive]");
    const titles = archive.locator("[data-filter-list] .blog-ledger__main strong");
    const retry = archive.locator("[data-archive-retry]");
    await expect(retry).toBeVisible();
    await expect(titles).toHaveText(["Newest", "Middle"]);
    await page.unroute("**/facet-*.json");
    await retry.click();
    await expect(titles).toHaveText(["Newest", "Oldest"]);
    await expect(retry).toBeHidden();
  });
}
