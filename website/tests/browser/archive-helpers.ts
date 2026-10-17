import { expect, type Page } from "@playwright/test";

export async function expandArchiveDays(page: Page): Promise<void> {
  await expect(page.locator("[data-paged-archive]")).not.toHaveAttribute("aria-busy", "true");
  await expect(page.locator("[data-archive-page-status]")).not.toBeEmpty();
  const scroll = await page.evaluate(() => scrollY);
  for (const summary of await page.locator("details[data-ledger-day]:not([open]) > summary").all()) await summary.click();
  await page.evaluate(y => scrollTo(0, y), scroll);
}
