import { test, expect } from "@playwright/test";

for (const theme of ["minimal", "docs"]) for (const locale of ["en", "zh-CN"]) {
  test(`${theme} media and icon actions in ${locale}`, async ({ page }, testInfo) => {
    const errors: string[] = []; page.on("pageerror", error => errors.push(error.message));
    await page.route("https://**/*", route => {
      const url = route.request().url();
      if (url.endsWith("figure.svg")) return route.fulfill({ contentType: "image/svg+xml", body: '<svg xmlns="http://www.w3.org/2000/svg" width="480" height="200"><rect width="480" height="200" fill="#356c70"/><text x="30" y="110" fill="white" font-size="28">Research figure</text></svg>' });
      if (route.request().isNavigationRequest()) return route.fulfill({ contentType: "text/html", body: "<p>Offline player fixture</p>" });
      return route.fulfill({ status: 204 });
    });
    await page.goto(`/__site__/${theme}-media/${locale === "en" ? "" : "zh-CN/"}`);
    const actions = page.locator(".site-actions"), search = actions.locator("[data-search-open]"), scheme = actions.locator("[data-color-scheme-toggle]");
    await expect(search.locator("svg")).toHaveCount(1);
    await expect(search).toHaveAttribute("title", locale === "en" ? "Search" : "搜索");
    await expect(search.locator("kbd")).toHaveCount(0);
    await expect(actions.locator(".language-switcher summary svg")).toHaveCount(1);
    for (const control of await actions.locator("button, summary, a.site-action").all()) {
      await expect(control).toHaveAttribute("aria-label", /.+/);
      await expect(control).toHaveAttribute("title", /.+/);
    }
    const before = await scheme.getAttribute("aria-label"); await scheme.press("Enter");
    await expect(scheme).not.toHaveAttribute("aria-label", before!);
    await expect(scheme).toHaveAttribute("title", (await scheme.getAttribute("aria-label"))!);
    await actions.locator(".language-switcher summary").press("Enter");
    await expect(actions.locator(".language-switcher__panel")).toBeVisible();
    await expect(actions.locator(".language-switcher__panel a")).toHaveText(["English", "简体中文"]);
    await actions.locator(".language-switcher summary").press("Enter");
    await search.click(); await expect(page.locator('[data-dialog="search"]')).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.locator("audio.website-external-audio")).toBeVisible();
    await expect(page.locator("video.website-external-video")).toBeVisible();
    await expect(page.locator("iframe[data-website-external-pdf]")).toHaveAttribute("src", "https://papers.example/paper.pdf#page=3");
    await expect(page.locator("iframe[data-website-external-pdf]")).toHaveAttribute("height", "560");
    await expect(page.locator(".website-external-pdf__fallback")).toHaveAttribute("href", "https://papers.example/paper.pdf#page=3");
    await expect(page.locator("iframe[data-website-external-player]")).toHaveAttribute("src", "https://www.youtube-nocookie.com/embed/NnTvZWp5Q7o");
    if (testInfo.project.name.startsWith("mobile")) await page.setViewportSize({ width: 320, height: 780 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
    expect(await actions.evaluate(node => node.getBoundingClientRect().right <= innerWidth)).toBe(true);
    expect(errors).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath(`${theme}-${locale}.png`), fullPage: true });
  });
}
