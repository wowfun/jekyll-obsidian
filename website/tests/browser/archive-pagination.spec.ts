import { test, expect } from "@playwright/test";

for (const locale of ["en", "zh-CN"]) {
  const root = `/__site__/minimal-export/${locale === "en" ? "" : "zh-CN/"}`;
  test(`nearby pages and numeric jumps keep filters and history in ${locale}`, async ({ page }) => {
    await page.goto(root + "?source=hn&topic=agents&year=2026&page=12");
    const pager = page.locator("[data-archive-pagination]"), links = pager.locator("[data-archive-page-numbers] a"), input = pager.locator("input");
    await expect(links).toHaveText(["10", "11", "12", "13", "14"]);
    await expect(pager.locator('a[aria-current="page"]')).toHaveText("12");
    await links.getByText("14", { exact: true }).click();
    await expect(page).toHaveURL(root + "?source=hn&topic=agents&year=2026&page=14");
    await expect(input).toHaveValue("14");
    await input.fill("1"); await input.press("Enter");
    await expect(page).toHaveURL(root + "?source=hn&topic=agents&year=2026");
    await expect(links).toHaveText(["1", "2", "3", "4", "5"]);
    const last = await input.getAttribute("max"); await input.fill(last!); await input.press("Enter");
    await expect(input).toHaveValue(last!);
    await expect(links.last()).toHaveAttribute("aria-current", "page");
    await page.goBack(); await expect(input).toHaveValue("1");
    for (const value of ["0", "1.5", "99999", "1e1"]) {
      await input.fill(value); await input.press("Enter");
      expect(await input.evaluate(node => (node as HTMLInputElement).checkValidity())).toBe(false);
      expect(await input.evaluate(node => (node as HTMLInputElement).validationMessage)).toContain(locale === "en" ? "Enter a whole number" : "请输入");
      await expect(page).toHaveURL(root + "?source=hn&topic=agents&year=2026");
    }
    await input.fill("2"); await input.press("Enter"); await expect(input).toHaveValue("2");
    await page.locator('button[data-archive-facet="topic"][data-archive-value="agents"]').click();
    await expect(input).toHaveValue("1");
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
  });
}

test("favorites use their own fifty-entry pages for numeric navigation", async ({ page }) => {
  const root = "/__site__/minimal-export/";
  await page.goto(root);
  const manifestUrl = await page.locator("[data-paged-archive]").getAttribute("data-archive-url");
  const manifest = await (await page.request.get(manifestUrl!)).json();
  const cards = [];
  for (const file of manifest.chunks) {
    const chunkUrl = new URL(file, new URL(manifestUrl!, page.url())).href;
    const chunk = await (await page.request.get(chunkUrl)).json(); cards.push(...chunk.cards);
  }
  await page.addInitScript(({ cards }) => {
    localStorage.setItem("website:favorites:v1:/__site__/minimal-export", JSON.stringify({ version: 1, entries: cards.map((card: { id: string }) => ({ id: card.id, saved_at: "2026-10-13T00:00:00Z", snapshots: { en: card } })) }));
  }, { cards });
  await page.goto(root + "favorites/?source=hn&topic=agents&year=2026");
  const pager = page.locator("[data-archive-pagination]"), input = pager.locator("input");
  await expect(pager.locator("[data-archive-page-numbers] a")).toHaveText(["1", "2"]);
  await expect(input).toHaveAttribute("max", "2");
  await expect(page.locator("[data-filter-item]")).toHaveCount(50);
  await input.fill("2"); await input.press("Enter");
  await expect(page).toHaveURL(root + "favorites/?source=hn&topic=agents&year=2026&page=2");
  await expect(page.locator("[data-filter-item]")).toHaveCount(8);
  await page.goBack(); await expect(page.locator("[data-filter-item]")).toHaveCount(50);
});
