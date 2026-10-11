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
