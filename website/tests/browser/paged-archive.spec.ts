import { expect, test } from "@playwright/test";

for (const locale of ["en", "zh-CN"]) {
  const root = "/__site__/minimal-archive/" + (locale === "en" ? "" : locale + "/");

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
    await expect(page.locator('[data-reading-loaded]')).toHaveCount(2);
    await page.locator('button[data-archive-facet=source][data-archive-value=hn]').click();
    await expect(bodies.last()).toContainText('First paragraph of Oldest.');
    await page.reload();
    await expect(toggle).toHaveAttribute('aria-checked', 'true');
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
