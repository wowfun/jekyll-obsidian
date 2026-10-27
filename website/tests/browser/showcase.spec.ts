import { test, expect } from "@playwright/test";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";

const cases = [
  { slug: "sinputer", title: "Sinputer's Site", site: "https://sinputer.top/", repo: "https://github.com/wowfun/wowfun.github.io" },
  { slug: "feedgarden", title: "Feedgarden", site: "https://sinputer.top/feedgarden/", repo: "https://github.com/wowfun/feedgarden" }
] as const;

for (const locale of ["en", "zh-CN"] as const) {
  for (const scheme of ["light", "dark"] as const) {
    test(`Showcase ${locale} ${scheme} has two translated, accessible cases`, async ({ page }, testInfo) => {
      const prefix = locale === "en" ? "" : "/zh-CN";
      const label = locale === "en" ? "Showcase" : "案例集";
      const root = "/__site__/minimal-i18n";
      await page.setViewportSize({ width: testInfo.project.name === "mobile-chromium" ? 390 : 1440, height: 900 });
      await page.emulateMedia({ colorScheme: scheme, reducedMotion: "reduce" });
      await page.goto(`${root}${prefix}/portfolio/`);
      await expect(page.getByRole("heading", { level: 1, name: label, exact: true })).toBeVisible();
      await expect(page.locator(".site-header [data-navigation-id='portfolio'] a")).toHaveText(label);
      await expect(page.locator(".site-header [data-navigation-id='portfolio'] a")).toHaveAttribute("aria-current", "page");
      const cards = page.locator(".minimal-portfolio-card");
      await expect(cards).toHaveCount(2);
      await expect(cards.locator("h2")).toHaveText(cases.map(item => item.title));
      await page.evaluate(() => document.fonts.ready);
      for (const [index, item] of cases.entries()) {
        const card = cards.nth(index);
        const screenshot = card.locator("img");
        await screenshot.scrollIntoViewIfNeeded();
        await expect(screenshot).toHaveAttribute("src", new RegExp(`/assets/vault/assets/showcase/${item.slug}\\.png$`));
        await expect.poll(() => screenshot.evaluate(image => ({
          width: (image as HTMLImageElement).naturalWidth,
          height: (image as HTMLImageElement).naturalHeight
        }))).toEqual({ width: 1440, height: 900 });
        await expect(card.locator(".minimal-portfolio-card__main")).toHaveAttribute("href", `${root}${prefix}/portfolio/${item.slug}/`);
      }
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
      await page.evaluate(() => scrollTo(0, 0));
      await expect(page).toHaveScreenshot(`showcase-${locale}-${scheme}.png`, { fullPage: true, animations: "disabled", maxDiffPixelRatio: 0.01 });

      for (const item of cases) {
        const link = cards.getByRole("link", { name: item.title, exact: true });
        await link.focus();
        await expect(link).toBeFocused();
        expect(await link.evaluate(element => getComputedStyle(element.closest("article")!).boxShadow)).not.toBe("none");
        await page.keyboard.press("Enter");
        await expect(page).toHaveURL(`${root}${prefix}/portfolio/${item.slug}/`);
        await expect(page.getByRole("heading", { level: 1, name: item.title, exact: true })).toBeVisible();
        await expect(page.locator("html")).toHaveAttribute("lang", locale);
        await expect(page.locator(".translation-fallback")).toHaveCount(0);
        const content = page.locator(".note-content");
        await expect(content.getByRole("link", { name: locale === "en" ? `Visit ${item.title}` : `访问 ${item.title}`, exact: true }))
          .toHaveAttribute("href", `${item.site}${locale === "en" ? "" : "zh-CN/"}`);
        await expect(content.getByRole("link", { name: locale === "en" ? "Source on GitHub" : "GitHub 源码", exact: true }))
          .toHaveAttribute("href", item.repo);
        const markdownUrl = await page.locator("[data-markdown-url]").first().getAttribute("data-markdown-url");
        const markdown = await page.request.get(markdownUrl!);
        expect(markdown.ok()).toBe(true);
        expect(await markdown.text()).toContain(item.repo);
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true);
        await page.screenshot({ path: testInfo.outputPath(`${item.slug}-${locale}-${scheme}.png`), fullPage: true });

        const switcher = page.locator("[data-language-switcher]");
        await switcher.locator("summary").click();
        await switcher.getByRole("link", { name: locale === "en" ? "简体中文" : "English", exact: true }).click();
        await expect(page).toHaveURL(`${root}${locale === "en" ? "/zh-CN" : ""}/portfolio/${item.slug}/`);
        await expect(page.locator("html")).toHaveAttribute("lang", locale === "en" ? "zh-CN" : "en");
        await expect(page.locator(".translation-fallback")).toHaveCount(0);
        await page.goto(`${root}${prefix}/portfolio/`);
      }
    });
  }
}

test("Showcase production resources preserve cross-site URLs and remove the old public case", async ({}, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "generated files are independent of viewport");
  const root = path.resolve("../.jekyll-obsidian-cache/site-browser-showcase");
  const sitemap = await readFile(path.join(root, "sitemap.xml"), "utf8");
  for (const locale of ["en", "zh-CN"]) {
    const prefix = locale === "en" ? "" : "zh-CN/";
    const searchPath = locale === "en" ? "assets/website/search.v1.json" : "assets/website/i18n/zh-CN/search.v1.json";
    const search = JSON.parse(await readFile(path.join(root, searchPath), "utf8")) as { documents: { id: string; title: string; url: string }[] };
    expect(search.documents.filter(doc => doc.id.startsWith("portfolio/")).map(doc => doc.id).sort())
      .toEqual(["portfolio/feedgarden.md", "portfolio/sinputer.md"]);
    for (const item of cases) {
      const route = `${prefix}portfolio/${item.slug}`;
      const html = await readFile(path.join(root, route, "index.html"), "utf8");
      const markdown = await readFile(path.join(root, `${route}.md`), "utf8");
      const target = `${item.site}${locale === "en" ? "" : "zh-CN/"}`;
      expect(html).toContain(`href="${target}"`);
      expect(html).toContain(`href="${item.repo}"`);
      expect(markdown).toContain(`](${target})`);
      expect(markdown).toContain(item.repo);
      expect(sitemap).toContain(`https://sinputer.top/jekyll-obsidian/${route}/`);
      expect(search.documents.find(doc => doc.id === `portfolio/${item.slug}.md`))
        .toMatchObject({ title: item.title, url: `/jekyll-obsidian/${route}/` });
      expect(html).not.toContain('class="translation-fallback"');
    }
  }
  const files = await readdir(root, { recursive: true, withFileTypes: true });
  for (const file of files.filter(entry => entry.isFile() && /\.(html|md|json|xml)$/.test(entry.name))) {
    const filePath = path.join(file.parentPath, file.name);
    const body = await readFile(filePath, "utf8");
    expect(body, path.relative(root, filePath)).not.toMatch(/portfolio\/jekyll-obsidian(?:\/|\.md)/);
    expect(path.relative(root, filePath)).not.toMatch(/portfolio[\\/]jekyll-obsidian/);
  }
});
