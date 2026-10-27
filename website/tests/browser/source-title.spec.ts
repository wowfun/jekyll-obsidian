import { test, expect, type Locator } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { archiveReady, expandArchiveDays } from "./archive-helpers";

const sourceTitle = "Source [A] <em>original</em>";

async function expectSourceTitle(link: Locator) {
  await expect(link).toHaveText(sourceTitle);
  await expect(link).toHaveAttribute("href", "https://example.com/a");
  await expect(link.locator("em")).toHaveCount(0);
}

for (const locale of ["en", "zh-CN"]) {
  const prefix = locale === "en" ? "" : "zh-CN/";
  const root = `/__site__/minimal-archive/${prefix}`;

  test(`source_title survives compilation, hydration, favorites and export in ${locale}`, async ({ page, browser, baseURL }) => {
    // Check the server-rendered archive before the client can replace its cards.
    const staticPage = await browser.newPage({ javaScriptEnabled: false });
    try {
      await staticPage.goto(new URL(root, baseURL).href);
      await expectSourceTitle(staticPage.locator('.archive-source-url[href="https://example.com/a"]'));
    } finally {
      await staticPage.close();
    }

    await page.goto(root);
    await archiveReady(page);
    await expectSourceTitle(page.locator('.archive-source-url[href="https://example.com/a"]'));
    // A filter change exercises the manifest-driven renderer, not just initial HTML.
    await page.locator('button[data-archive-facet="source"][data-archive-value="hn"]').click();
    await archiveReady(page);
    await expectSourceTitle(page.locator('.archive-source-url[href="https://example.com/a"]'));
    const save = page.locator('[data-favorite-id="items/a.md"]');
    await save.click();
    await expect(save).toHaveAttribute("aria-pressed", "true");

    await page.goto(`${root}items/a/`);
    await expectSourceTitle(page.locator(".note-source-url a"));
    await page.goto(`${root}items/b/`);
    await expect(page.locator(".note-source-url a")).toHaveText("https://example.com/b");

    await page.goto(`${root}favorites/`);
    await archiveReady(page);
    await expectSourceTitle(page.locator(".archive-source-url"));
    await page.reload();
    await archiveReady(page);
    await expectSourceTitle(page.locator(".archive-source-url"));

    await page.goto(`/__site__/minimal-export/${prefix}?day=2026-10-10`);
    await archiveReady(page);
    await expandArchiveDays(page);
    await expectSourceTitle(page.locator(".archive-source-url"));
    await page.locator("[data-archive-export-open]").click();
    const panel = page.locator('[data-dialog="export"]');
    await expect(panel.locator("[data-export-download]")).toBeEnabled();
    const downloading = page.waitForEvent("download");
    await panel.locator("[data-export-download]").click();
    const downloaded = await downloading;
    const markdown = await readFile((await downloaded.path())!, "utf8");
    expect(markdown).toContain(String.raw`[Source \[A\] \<em\>original\</em\>](<https://example.com/a>)`);
    expect(markdown).not.toContain("<em>original</em>");
  });
}
