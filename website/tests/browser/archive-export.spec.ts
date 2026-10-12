import { readFile } from "node:fs/promises";
import { expect, test, type Page } from "@playwright/test";

const panel = (page: Page) => page.locator('[data-dialog="export"]');
async function open(page: Page, count: number) {
  await page.locator('[data-archive-export-open]').click();
  await expect(panel(page).locator('[data-export-status]')).toHaveText(new RegExp(`\\b${count}\\b`));
  await expect(panel(page).locator('[data-export-download]')).toBeEnabled();
}
async function download(page: Page, retry = false) {
  const event = page.waitForEvent('download');
  await panel(page).locator(retry ? '[data-export-retry]' : '[data-export-download]').click();
  const file = await event;
  return { name: file.suggestedFilename(), body: await readFile((await file.path())!, 'utf8') };
}

for (const locale of ['en', 'zh-CN']) {
  const root = '/__site__/minimal-export/' + (locale === 'en' ? '' : locale + '/');

  test(`export rejects an oversized selection before loading bodies in ${locale}`, async ({ page }) => {
    await page.route('**/manifest.json', async route => {
      const response = await route.fetch(), data = await response.json();
      data.total = 5001;
      data.chunks = Array(Math.ceil(data.total / data.page_size)).fill(data.chunks[0]);
      data.days = { '2026-10-09': [0, data.total] };
      data.months = { '2026-10': [0, data.total] }; data.years = { '2026': [0, data.total] };
      await route.fulfill({ response, json: data });
    });
    const bodies: string[] = [];
    page.on('request', request => { if (request.url().endsWith('.md')) bodies.push(request.url()); });
    await page.goto(root);
    await page.locator('[data-archive-export-open]').click();
    await expect(panel(page).locator('[data-export-status]')).toHaveText(/5001.*5000/);
    await expect(panel(page).locator('[data-export-download]')).toBeDisabled();
    expect(bodies).toEqual([]);
  });

  test(`export snapshots independent filters and validates calendar ranges in ${locale}`, async ({ page }) => {
    await page.goto(root + '?source=hn&topic=agents&page=2');
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/59.*2.*30/);
    await expect(page.locator('.site-action--github')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    const originalUrl = page.url(), originalTitles = await page.locator('.blog-ledger__main strong').allTextContents();
    await open(page, 58);
    const dialog = panel(page), start = dialog.locator('[data-export-start]'), end = dialog.locator('[data-export-end]');
    const button = dialog.locator('[data-export-download]'), status = dialog.locator('[data-export-status]');
    const downloadBox = (await button.boundingBox())!;
    expect(downloadBox.y + downloadBox.height).toBeLessThanOrEqual(page.viewportSize()!.height);
    expect(await dialog.evaluate(el => el.scrollHeight <= el.clientHeight + 2)).toBe(true);
    await expect(start).toHaveValue('2026-10-04');
    await expect(end).toHaveValue('2026-10-10');
    await expect(dialog.locator('input[data-export-facet=source][value=hn]')).toBeChecked();
    await expect(dialog.locator('input[data-export-facet=topic][value=agents]')).toBeChecked();
    await dialog.locator('[data-export-all=source]').click();
    await dialog.locator('[data-export-all=topic]').click();
    await expect(status).toHaveText(/59/);
    await start.fill('2026-10-03');
    await expect(button).toBeDisabled();
    await expect(status).toHaveText(/7/);
    await start.fill('2026-10-11');
    await expect(status).toHaveText(locale === 'en' ? 'The end date must be on or after the start date.' : '结束日期不能早于开始日期。');
    await start.fill('');
    await expect(status).toHaveText(locale === 'en' ? 'Choose a start and end date.' : '请选择开始和结束日期。');
    await start.fill('2026-10-01'); await end.fill('2026-10-02');
    await expect(status).toHaveText(locale === 'en' ? 'No matching entries. Adjust the dates or filters.' : '没有符合条件的条目，请调整日期或筛选。');
    await expect(button).toBeDisabled();
    await start.fill('2025-12-29'); await end.fill('2026-01-04');
    await expect(status).toHaveText(/\b1\b/);
    await expect(button).toBeEnabled();
    await end.fill('2026-01-05'); await expect(button).toBeDisabled();
    expect(page.url()).toBe(originalUrl);
    expect(await page.locator('.blog-ledger__main strong').allTextContents()).toEqual(originalTitles);
    expect(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth + 1)).toBe(true);
    await page.keyboard.press('Escape');
    await expect(dialog).not.toBeVisible();
    await expect(page.locator('[data-archive-export-open]')).toBeFocused();
    await open(page, 58);
    await expect(start).toHaveValue('2026-10-04');
    await expect(dialog.locator('input[data-export-facet=source][value=hn]')).toBeChecked();
    await dialog.locator('[data-dialog-close]').click();
    await page.goto(root + '?day=2026-10-09');
    await open(page, 58);
    await expect(start).toHaveValue('2026-10-09'); await expect(end).toHaveValue('2026-10-09');
  });

  test(`export downloads every full article beyond pagination in ${locale}`, async ({ page }) => {
    await page.goto(root + '?page=2');
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/60.*2.*30/);
    await page.locator('[data-archive-reading-toggle]').click();
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    const titles = await page.locator('.blog-ledger__main strong').allTextContents();
    await open(page, 59);
    const file = await download(page);
    expect(file.name).toBe(`archive-fixture-${locale}-2026-10-04_2026-10-10.md`);
    expect(file.body).toContain('# Archive fixture');
    expect(file.body).toContain('First paragraph of Newest.');
    expect(file.body).toContain('First paragraph of Middle.');
    expect(file.body).not.toContain('First paragraph of Oldest.');
    for (let i = 0; i < 57; i++) {
      const id = `bulk-${String(i).padStart(2, '0')}`;
      expect(file.body.split(`Complete body of ${id}.`)).toHaveLength(2);
      expect(file.body).toContain(`Discussion of ${id}.`);
      if (locale === 'zh-CN') expect(file.body).toContain(`中文完整正文 ${id}。`);
    }
    expect(file.body).toContain('```md\n# Code heading\n---\n```');
    expect(file.body).toContain('> Source quote');
    expect(file.body).toContain('- A list item');
    expect(file.body).toContain('![Image](https://example.com/image.png)');
    expect(file.body).toContain('https://news.ycombinator.com/item?id=123');
    expect(file.body).toContain(`http://127.0.0.1:4173${root}items/bulk-00/`);
    expect(file.body).not.toMatch(/Short description|publish: true|content_type: post/);
    // Timestamp descending, ties follow the compiler's descending stable IDs.
    const ids = Array.from({ length: 57 }, (_, i) => i).sort((a, b) => b % 16 - a % 16 || b - a);
    const positions = ids.map(i => file.body.indexOf(`Complete body of bulk-${String(i).padStart(2, '0')}.`));
    expect(positions).toEqual([...positions].sort((a, b) => a - b));
    await panel(page).locator('[data-dialog-close]').click();
    await expect(page).toHaveURL(root + '?page=2');
    await expect(page.locator('.blog-ledger__main strong')).toHaveText(titles);
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    await page.locator('[data-archive-page=next]').click();
    await expect(page.locator('[data-archive-page-status]')).toHaveText(/60.*3.*30/);
  });

  test(`export retries only failed bodies and never downloads partial content in ${locale}`, async ({ page }) => {
    const requests = new Map<string, number>();
    let fail = true, downloads = 0;
    page.on('download', () => downloads++);
    await page.route('**/items/*.md', async route => {
      const url = route.request().url(); requests.set(url, (requests.get(url) || 0) + 1);
      if (fail && url.endsWith('/bulk-00.md')) await route.fulfill({ status: 503, body: 'Unavailable' });
      else await route.continue();
    });
    await page.goto(root);
    await open(page, 59);
    await panel(page).locator('[data-export-download]').click();
    await expect(panel(page).locator('[data-export-retry]')).toBeVisible();
    await expect(panel(page).locator('[data-export-status]')).toHaveText(/1 .*complete file|1 条正文载入失败/);
    expect(downloads).toBe(0);
    await expect(panel(page).locator('[data-export-download]')).toBeDisabled();
    fail = false;
    const file = await download(page, true);
    expect(file.body).toContain('Complete body of bulk-00.');
    expect(requests.size).toBe(59);
    for (const [url, count] of requests) expect(count).toBe(url.endsWith('/bulk-00.md') ? 2 : 1);
    expect(downloads).toBe(1);
  });

  test(`export cancel and close abort a four-request batch without a late download in ${locale}`, async ({ page }) => {
    let downloads = 0;
    page.on('download', () => downloads++);
    await page.goto(root);
    let release!: () => void, held: Promise<void>, requested = 0, pending = 0;
    await page.route('**/items/*.md', async route => {
      requested++; pending++;
      await held;
      await route.fulfill({ contentType: 'text/markdown', body: '# Delayed article' }).catch(() => undefined);
      pending--;
    });
    for (const close of [false, true]) {
      held = new Promise<void>(resolve => { release = resolve; });
      requested = 0;
      await open(page, 59);
      await panel(page).locator('[data-export-download]').click();
      await expect.poll(() => requested).toBe(4);
      await expect(panel(page).locator('[data-export-start]')).toBeDisabled();
      if (close) {
        await page.keyboard.press('Escape');
        await expect(panel(page)).not.toBeVisible();
        await expect(page.locator('[data-archive-export-open]')).toBeFocused();
      } else {
        await panel(page).locator('[data-export-cancel]').click();
        await expect(panel(page).locator('[data-export-status]')).toHaveText(locale === 'en' ? 'Export cancelled.' : '已取消导出。');
        await expect(panel(page).locator('[data-export-start]')).toBeEnabled();
        await panel(page).locator('[data-dialog-close]').click();
      }
      release();
      await expect.poll(() => pending).toBe(0);
      expect(requested).toBe(4);
      expect(downloads).toBe(0);
    }
    await page.unroute('**/items/*.md');
    await open(page, 59);
    const file = await download(page);
    expect(file.body).toContain('Complete body of bulk-00.');
    expect(file.body).not.toContain('Delayed article');
    expect(downloads).toBe(1);
  });
}
