import { expect, test, type Page } from "@playwright/test";
import { readFile } from "node:fs/promises";

const fixture = JSON.parse(await readFile(new URL("./fixtures/archive-governance.json", import.meta.url), "utf8")) as { pageSize: number; posts: unknown[] };
const totalItems = fixture.posts.length, totalPages = Math.ceil(totalItems / fixture.pageSize);
const facetOptions = (page: Page) => page.locator('[data-paged-archive] .archive-facet [data-archive-facet]').evaluateAll(options => options.map(option => ({
  facet: (option as HTMLElement).dataset.archiveFacet, value: (option as HTMLElement).dataset.archiveValue,
  hidden: (option.closest("li") as HTMLElement).hidden, count: option.querySelector("span")!.textContent,
})));

for (const locale of ["en", "zh-CN"]) {
  const root = "/__site__/minimal-governance/" + (locale === "en" ? "" : locale + "/");
  const source = '[data-paged-archive] [data-archive-visibility=include_tabs]';
  const topics = '[data-paged-archive] .archive-facet:has([data-archive-facet=topic]) [data-archive-visibility=show_hidden]';
  const hidden = '[data-paged-archive] button[data-archive-facet=topic][data-archive-value=agents]';
  const status = '[data-archive-page-status]';

  test(`default scope, keyboard, hidden selection and history in ${locale}`, async ({ page }) => {
    await page.goto(root);
    await expect(page.locator(status)).toHaveText(/3.*1.*2/);
    await expect(page.locator(hidden)).toBeHidden();
    await expect(page.locator(source)).toHaveText(locale === "en" ? "Include tab sources" : "显示独立栏目");
    await expect(page.locator('[data-paged-archive] button[data-archive-facet=source][data-archive-value=arxiv]')).toBeHidden();
    await page.locator(topics).focus(); await page.keyboard.press("Enter");
    await expect(page.locator(hidden)).toBeVisible();
    await expect(page).toHaveURL(/show_hidden=topic/);
    await page.locator(hidden).click();
    await page.locator(topics).click();
    await expect(page.locator(hidden)).toHaveAttribute("aria-pressed", "true");
    await page.locator(hidden).click();
    await expect(page.locator(hidden)).toBeHidden();
    await page.locator(source).click();
    await expect(page.locator(status)).toHaveText(new RegExp(`${totalItems}.*1.*${totalPages}`));
    await page.locator('[data-archive-page=next]').click();
    await page.locator(topics).click();
    await expect(page).toHaveURL(/page=2/);
    await page.locator(source).click();
    await expect(page.locator(status)).toHaveText(/3.*1.*2/);
    await page.goBack();
    await expect(page.locator(status)).toHaveText(new RegExp(`${totalItems}.*2.*${totalPages}`));
    await page.reload();
    await expect(page.locator(source)).toHaveAttribute("aria-expanded", "true");
    await expect(page.locator(topics)).toHaveAttribute("aria-expanded", "true");
    await page.emulateMedia({ colorScheme: "dark" });
    await expect(page.locator(source)).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });

  test(`old source links, independent export and retained article labels in ${locale}`, async ({ page }) => {
    await page.goto(root + "?source=arxiv");
    await expect(page.locator(status)).toHaveText(/1.*1.*1/);
    await expect(page).toHaveURL(/include_tabs=1/);
    await page.locator(source).click();
    await expect(page.locator(status)).toHaveText(/3.*1.*2/);
    await expect(page).not.toHaveURL(/source=|include_tabs=/);
    await page.locator("[data-archive-export-open]").click();
    const dialog = page.locator('[data-dialog="export"]');
    await expect(dialog.locator("[data-export-status]")).toContainText("3");
    await expect(dialog.locator('input[data-export-facet=topic][value=agents]')).toHaveCount(0);
    await dialog.locator('[data-archive-visibility=include_tabs]').click();
    await expect(dialog.locator("[data-export-status]")).toContainText("4");
    await dialog.locator('[data-export-facet-group=topic] [data-archive-visibility=show_hidden]').click();
    const topicChoice = dialog.locator('input[data-export-facet=topic][value=agents]');
    await expect(topicChoice).toBeVisible();
    await topicChoice.check();
    await dialog.locator('[data-export-facet-group=topic] [data-archive-visibility=show_hidden]').click();
    await expect(topicChoice).toBeVisible();
    await topicChoice.uncheck();
    await expect(topicChoice).toBeHidden();
    const event = page.waitForEvent("download"); await dialog.locator("[data-export-download]").click();
    const download = await event, body = await readFile((await download.path())!, "utf8");
    expect(body).toContain("Article body paper."); expect(body).toContain("regular-3");
    expect(new URL(page.url()).search).toBe("");
    await page.keyboard.press("Escape");
    await expect(page.locator(status)).toHaveText(/3.*1.*2/);
    await page.goto(root + "arxiv/");
    await expect(page.locator(status)).toHaveText(/1.*1.*1/);
    await expect(page.locator(source)).toHaveCount(0);
    await expect(page.locator(hidden)).toBeHidden();
    await page.goto(root + "items/paper/");
    await expect(page.locator('a[href*="topic=agents"]').first()).toBeVisible();
  });

  test(`SSR excludes tabs and agrees with hydration in ${locale}`, async ({ browser, page: hydrated, isMobile }) => {
    const context = await browser.newContext({ javaScriptEnabled: false });
    const page = await context.newPage(); await page.goto(root);
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["regular-3", "regular-2"]);
    await expect(page.locator(hidden)).toBeHidden();
    await expect(page.locator(source)).toHaveCount(0);
    await expect(page.locator('button[data-archive-facet=source][data-archive-value=""] span')).toHaveText("3");
    await expect(page.locator('button[data-archive-facet=source][data-archive-value=regular]')).toBeHidden();
    await expect(page.locator('button[data-archive-facet=source][data-archive-value=regular] span')).toHaveText("3");
    await hydrated.goto(root);
    await expect(hydrated.locator(source)).toBeVisible();
    expect(await facetOptions(hydrated)).toEqual(await facetOptions(page));
    await expect(hydrated.locator('.archive-facet').first()).toHaveCSS("display", "flex");
    const rootFontSize = await hydrated.evaluate(() => parseFloat(getComputedStyle(document.documentElement).fontSize));
    await expect(hydrated.locator('.archive-facet-heading').first()).toHaveCSS("flex-basis", isMobile ? "100%" : `${7.5 * rootFontSize}px`);
    await page.goto(root + "arxiv/");
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["paper"]);
    await context.close();
  });

  test(`favorites include tab sources and keep hidden labels even offline in ${locale}`, async ({ page }) => {
    await page.goto(root + "arxiv/");
    await expect(page.locator(status)).toHaveText(/1.*1.*1/);
    await page.locator("[data-filter-item] [data-favorite-toggle]").click();
    await page.goto(root + "favorites/");
    await expect(page.locator(status)).toHaveText(/1.*1.*1/);
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["paper"]);
    await expect(page.locator(hidden)).toBeHidden();
    await expect(page.locator(source)).toHaveCount(0);
    await expect(page.locator('[data-filter-item] a[href*="topic=agents"]')).toBeVisible();
    await page.locator(topics).click();
    await expect(page.locator(hidden)).toBeVisible();
    await page.locator("[data-language-switcher] summary").click();
    await page.locator(`[data-language-switcher] a[lang="${locale === "en" ? "zh-CN" : "en"}"]`).click();
    await expect(page.locator(hidden)).toBeVisible();
    await expect(page).toHaveURL(/show_hidden=topic/);
    await page.route("**/manifest.json", route => route.abort());
    await page.goto(root + "favorites/");
    await expect(page.locator(".blog-ledger__main strong")).toHaveText(["paper"]);
    await expect(page.locator(hidden)).toBeHidden();
    await page.locator(topics).click();
    await expect(page.locator(hidden)).toBeVisible();
  });

  test(`hidden source tags have a separate accessible disclosure in ${locale}`, async ({ page }) => {
    await page.goto(root);
    const sources = page.locator('.archive-facet:has([data-archive-facet=source])');
    const hiddenToggle = sources.locator('[data-archive-visibility=show_hidden]');
    const regular = sources.locator('[data-archive-value=regular]');
    await expect(hiddenToggle).toHaveText(locale === "en" ? "Show hidden tags" : "显示隐藏标签");
    await expect(regular).toBeHidden();
    await expect(hiddenToggle).toHaveAttribute("aria-controls", "archive-options-source");
    await hiddenToggle.focus(); await page.keyboard.press("Enter");
    await expect(regular).toBeVisible();
    await expect(page.locator(hidden)).toBeHidden();
    await expect(page.locator(topics)).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator(source)).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator(status)).toHaveText(/3.*1.*2/);
    await page.locator("[data-archive-export-open]").click();
    const dialog = page.locator('[data-dialog="export"]');
    const sourceGroup = dialog.locator('[data-export-facet-group=source]');
    const topicGroup = dialog.locator('[data-export-facet-group=topic]');
    await expect(sourceGroup.locator('[data-archive-visibility]')).toHaveCount(2);
    await expect(topicGroup.locator('input[value=agents]')).toHaveCount(0);
    await topicGroup.locator('[data-archive-visibility=show_hidden]').click();
    await expect(topicGroup.locator('input[value=agents]')).toBeVisible();
    await sourceGroup.locator('[data-archive-visibility=show_hidden]').click();
    await expect(sourceGroup.locator('[data-archive-visibility=show_hidden]')).toBeFocused();
    await expect(sourceGroup.locator('input[value=regular]')).toHaveCount(0);
    await expect(topicGroup.locator('input[value=agents]')).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(regular).toBeVisible();
    await expect(page.locator(hidden)).toBeHidden();
    await page.locator(topics).click();
    await hiddenToggle.click();
    await expect(regular).toBeHidden();
    await expect(page.locator(hidden)).toBeVisible();
    await page.goBack();
    await expect(regular).toBeVisible();
    await expect(page.locator(hidden)).toBeVisible();
    await page.goForward();
    await page.reload();
    await expect(hiddenToggle).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator(topics)).toHaveAttribute("aria-expanded", "true");
  });

  test(`deselecting a hidden source focuses its disclosure in ${locale}`, async ({ page }) => {
    await page.goto(root + "?source=regular");
    await page.locator("[data-archive-export-open]").click();
    const group = page.locator('[data-dialog="export"] [data-export-facet-group=source]');
    const choice = group.locator('input[value=regular]');
    await expect(group.locator('[data-archive-visibility]')).toHaveCount(2);
    await expect(choice).toBeChecked();
    await choice.focus();
    await page.keyboard.press("Space");
    await expect(choice).toBeHidden();
    await expect(group.locator('[data-archive-visibility=show_hidden]')).toBeFocused();
  });
}
