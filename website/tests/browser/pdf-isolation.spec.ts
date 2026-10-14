import { test, expect } from "@playwright/test";
import { readFile } from "node:fs/promises";

test.use({ channel: "chromium" });
const pdf = () => readFile(new URL("./fixtures/sample.pdf", import.meta.url));
const site = "/__site__/minimal-media/";

test("PDF previews start compact, render in Chromium, close and retain the page anchor", async ({ page }, testInfo) => {
  let requests = 0;
  await page.route("https://**/*", async route => {
    if (route.request().url().includes("paper.pdf")) { requests++; return route.fulfill({ contentType: "application/pdf", headers: { "access-control-allow-origin": "*" }, body: await pdf() }); }
    return route.fulfill({ contentType: "text/html", body: "<p>Offline media</p>" });
  });
  await page.goto(site);
  const card = page.locator("[data-website-pdf-source]"), button = card.locator("[data-pdf-preview]");
  await expect(card.locator("iframe")).toHaveCount(0); expect(requests).toBe(0);
  expect((await card.boundingBox())!.height).toBeLessThan(180);
  await button.click(); await expect(card.locator("iframe")).toHaveAttribute("src", /^blob:.*#page=3$/);
  await expect.poll(() => page.frames().some(frame => frame.url().startsWith("chrome-extension://mhjfbmdgcfjbbpaeojofohoefgiehjai/"))).toBe(true);
  expect(requests).toBe(1);
  await card.screenshot({ path: testInfo.outputPath("pdf-preview.png") });
  await button.click(); await expect(card.locator("iframe")).toHaveCount(0);
  await expect(button).toHaveAttribute("aria-expanded", "false");
});

test("HTML, including a forged PDF MIME type, cannot enter a viewer or modify the parent", async ({ page }) => {
  for (const contentType of ["text/html", "application/pdf"]) {
    await page.route("https://**/*", route => route.fulfill({ contentType, headers: { "access-control-allow-origin": "*" }, body: '<script>parent.document.body.dataset.escaped="yes"</script>' }));
    await page.goto(site); const card = page.locator("[data-website-pdf-source]");
    await card.locator("[data-pdf-preview]").click();
    await expect(card.locator("[data-pdf-status]")).toContainText("Preview unavailable");
    await expect(card.locator("iframe")).toHaveCount(0); await expect(page.locator("body")).not.toHaveAttribute("data-escaped", "yes");
    expect((await card.boundingBox())!.height).toBeLessThan(180); await page.unroute("https://**/*");
  }
});

test("CORS failure keeps a usable localized link and preview can be retried", async ({ page }) => {
  let allow = false;
  await page.route("https://**/*", async route => route.fulfill({ contentType: "application/pdf", headers: { "access-control-allow-origin": allow ? "*" : "https://blocked.test" }, body: await pdf() }));
  await page.goto(site + "zh-CN/"); const card = page.locator("[data-website-pdf-source]");
  await card.locator("[data-pdf-preview]").click(); await expect(card.locator("[data-pdf-status]")).toContainText("无法预览");
  await expect(card.locator("a")).toHaveAttribute("href", "https://papers.example/paper.pdf#page=3");
  allow = true; await card.locator("[data-pdf-preview]").click(); await expect(card.locator("iframe")).toHaveCount(1);
});
