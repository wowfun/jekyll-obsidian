import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

type Theme = "minimal" | "docs";

const themes = ["minimal", "docs"] as const satisfies readonly Theme[];
const site = (theme: Theme, route = "/") => `/__site__/${theme}${route}`;
const localizedDocs = (route = "/") => `/__site__/docs-i18n${route}`;
const localizedMinimal = (route = "/") => `/__site__/minimal-i18n${route}`;

for (const theme of themes) {
  test(`${theme} exposes an accessible presentation`, async ({ page }) => {
    const route = theme === "minimal" ? "/blog/One%20vault%2C%20three%20readings/" : "/";
    await page.goto(site(theme, route));
    await expect(page.locator("body")).toHaveClass(new RegExp(`theme-${theme}`));
    await expect(page.locator("main")).toBeVisible();
    await expect(page.locator(".site-footer__github"))
      .toHaveAttribute("href", "https://github.com/wowfun/jekyll-obsidian");
    const results = await new AxeBuilder({ page }).analyze();
    expect(results.violations).toEqual([]);
  });
}

for (const theme of themes) {
  test(`${theme} copies the exact generated Markdown resource`, async ({ page }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          async writeText(value: string) {
            (window as typeof window & { __copiedMarkdown?: string }).__copiedMarkdown = value;
          }
        }
      });
    });
    const route = theme === "minimal"
      ? "/blog/One%20vault%2C%20three%20readings/"
      : "/docs/Getting%20Started/";
    await page.goto(site(theme, route));

    const actions = page.locator("[data-page-actions]");
    await expect(actions.locator(".page-actions__primary")).toBeVisible();
    const view = actions.locator("a.page-actions__item[href]");
    const markdownUrl = await view.getAttribute("href");
    expect(markdownUrl).toBeTruthy();
    const markdownResponse = await page.request.get(markdownUrl!);
    expect(markdownResponse.ok()).toBe(true);
    expect(markdownResponse.headers()["content-type"]).toContain("text/markdown");
    const markdown = await markdownResponse.text();
    expect(markdown).not.toMatch(/^---\s*(?:\r?\n)/);
    expect(markdown.endsWith("\n")).toBe(true);
    expect(markdown.endsWith("\n\n")).toBe(false);

    await actions.locator(".page-actions__primary").click();
    await expect(actions.locator("[role='status']")).toHaveText("Copied");
    await expect(actions.locator(".page-actions__primary")).toBeFocused();
    expect(await page.evaluate(() =>
      (window as typeof window & { __copiedMarkdown?: string }).__copiedMarkdown
    )).toBe(markdown);

    await actions.locator("summary").click();
    await expect(view).toBeVisible();
    await expect(actions.getByRole("link", { name: /View as Markdown/ })).toBeVisible();
    await expect(view).toHaveAttribute("target", "_blank");
    await expect(view).toHaveAttribute("rel", "noopener");
  });
}

for (const theme of themes) {
  test(`${theme} adds one shared source-copy action to code, Mermaid, and MathJax`, async ({ page }, testInfo) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: {
          async writeText(value: string) {
            (window as typeof window & { __copiedCode?: string }).__copiedCode = value;
          }
        }
      });
    });
    await page.goto(site(theme, "/docs/Syntax/"));
    await expect(page.locator("[data-mermaid-rendered]")).toBeVisible();

    const blocks = page.locator(".note-content [data-code-block-copy]");
    const renderedCode = page.locator(".note-content pre");
    await expect(blocks).toHaveCount(await renderedCode.count());
    expect(await blocks.count()).toBeGreaterThan(0);
    await expect(blocks.locator(":scope > pre")).toHaveCount(await blocks.count());
    await expect(page.locator(".note-content pre button")).toHaveCount(0);
    const diagram = page.locator("[data-mermaid-rendered]").first();
    const diagramButton = diagram.locator("button[data-copy-source]");
    await expect(diagramButton).toHaveCount(1);
    await expect(diagramButton).toHaveAccessibleName("Copy diagram source");
    const formulas = page.locator("[data-math-rendered]");
    expect(await formulas.count()).toBeGreaterThan(1);
    await expect(formulas.locator("button[data-copy-source]")).toHaveCount(await formulas.count());
    await expect(formulas.first().locator("button[data-copy-source]")).toHaveAccessibleName("Copy formula source");

    const first = blocks.first();
    const source = await first.locator(":scope > pre").textContent();
    const button = first.locator("button[data-copy-code]");
    await expect(button).toHaveAccessibleName("Copy code");
    const primaryInk = await page.locator("body").evaluate((element) => getComputedStyle(element).color);
    await expect(button).toHaveCSS("color", primaryInk);
    await expect(button).toHaveCSS("border-top-width", "0px");
    await expect(button.locator("svg")).toBeVisible();
    await expect(button.locator(".code-block-copy__label")).toHaveCount(0);
    await expect(button).toHaveText("");
    const actionBox = (await button.boundingBox())!;
    expect(actionBox.width).toBeGreaterThanOrEqual(32);
    expect(actionBox.height).toBeGreaterThanOrEqual(32);
    expect(Math.abs(actionBox.width - actionBox.height)).toBeLessThanOrEqual(1);
    const placement = await first.evaluate((element) => {
      const wrapper = element.getBoundingClientRect();
      const action = element.querySelector("button")!.getBoundingClientRect();
      return {
        top: action.top - wrapper.top,
        end: wrapper.right - action.right
      };
    });
    expect(placement.top).toBeGreaterThanOrEqual(0);
    expect(placement.top).toBeLessThanOrEqual(16);
    expect(placement.end).toBeGreaterThanOrEqual(0);
    expect(placement.end).toBeLessThanOrEqual(16);
    const idleShadow = await button.evaluate((element) => getComputedStyle(element).boxShadow);
    await button.focus();
    await expect.poll(() => button.evaluate((element) => getComputedStyle(element).boxShadow))
      .not.toBe(idleShadow);
    await page.keyboard.press("Enter");
    await expect(button).toHaveAccessibleName("Copied");
    await expect(button.locator("[data-copy-icon='success']")).toBeVisible();
    await expect(first.getByRole("status")).toHaveText("Copied");
    await expect(button).toBeFocused();
    expect(await page.evaluate(() =>
      (window as typeof window & { __copiedCode?: string }).__copiedCode
    )).toBe(source);

    const diagramSource = await diagram.locator("template[data-website-copy-source]").evaluate((template) =>
      (template as HTMLTemplateElement).content.textContent
    );
    await diagramButton.click();
    await expect(diagramButton).toHaveAccessibleName("Copied");
    await expect(diagramButton.locator("[data-copy-icon='success']")).toBeVisible();
    expect(await page.evaluate(() =>
      (window as typeof window & { __copiedCode?: string }).__copiedCode
    )).toBe(diagramSource);

    const formula = formulas.first();
    const formulaButton = formula.locator("button[data-copy-source]");
    const formulaActionBox = (await formulaButton.boundingBox())!;
    expect(formulaActionBox.width).toBeGreaterThanOrEqual(24);
    expect(formulaActionBox.height).toBeGreaterThanOrEqual(24);
    const formulaSource = await formula.locator("template[data-website-copy-source]").evaluate((template) =>
      (template as HTMLTemplateElement).content.textContent
    );
    await formulaButton.click();
    await expect(formulaButton).toHaveAccessibleName("Copied");
    await expect(formulaButton.locator("[data-copy-icon='success']")).toBeVisible();
    expect(await page.evaluate(() =>
      (window as typeof window & { __copiedCode?: string }).__copiedCode
    )).toBe(formulaSource);

    const sourceHosts = page.locator(".note-content [data-source-copy]");
    const fitsViewport = await sourceHosts.evaluateAll((elements) => elements.every((element) => {
      const box = element.getBoundingClientRect();
      return box.left >= 0 && box.right <= document.documentElement.clientWidth;
    }));
    expect(fitsViewport).toBe(true);
    const accessibility = await new AxeBuilder({ page }).include("button[data-copy-source]").analyze();
    expect(accessibility.violations).toEqual([]);

    await page.emulateMedia({ forcedColors: "active" });
    await button.focus();
    await page.keyboard.press("Tab");
    await page.keyboard.press("Shift+Tab");
    await expect(button).toBeFocused();
    const forcedColorFocus = await button.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        visible: element.matches(":focus-visible"),
        outlineStyle: style.outlineStyle,
        outlineWidth: Number.parseFloat(style.outlineWidth)
      };
    });
    expect(forcedColorFocus.visible).toBe(true);
    expect(forcedColorFocus.outlineStyle).not.toBe("none");
    expect(forcedColorFocus.outlineWidth).toBeGreaterThanOrEqual(2);
    await page.emulateMedia({ forcedColors: "none" });

    await page.emulateMedia({ media: "print" });
    await expect(diagramButton).toBeHidden();
    const printSourceLayout = await page.evaluate(() => {
      const paddings = (element: Element) => {
        const style = getComputedStyle(element);
        return {
          start: Number.parseFloat(style.paddingInlineStart),
          end: Number.parseFloat(style.paddingInlineEnd)
        };
      };
      const diagram = document.querySelector<HTMLElement>("[data-mermaid-rendered]")!;
      const displayFormula = document.querySelector<HTMLElement>(
        ":is([data-math-style='display'], [data-math='display'], .math-display)[data-source-copy]"
      )!;
      const inlineFormula = document.querySelector<HTMLElement>(
        ":is([data-math-style='inline'], [data-math='inline'], .math-inline)[data-source-copy]"
      )!;
      return {
        diagram: paddings(diagram),
        displayFormula: paddings(displayFormula),
        inlineDisplay: getComputedStyle(inlineFormula).display
      };
    });
    expect(printSourceLayout.diagram.end).toBeCloseTo(printSourceLayout.diagram.start, 5);
    expect(printSourceLayout.displayFormula.end)
      .toBeCloseTo(printSourceLayout.displayFormula.start, 5);
    expect(printSourceLayout.inlineDisplay).toBe("inline");
    await page.emulateMedia({ media: "screen" });

    if (theme === "docs" && testInfo.project.name === "desktop-chromium") {
      await page.getByRole("navigation", { name: "Documentation", exact: true })
        .getByRole("link", { name: "Integration" }).click();
      await expect(page).toHaveURL(site("docs", "/docs/Integration/"));
      const navigatedBlock = page.locator(".note-content [data-code-block-copy]").first();
      const navigatedButton = navigatedBlock.locator("button[data-copy-code]");
      await expect(navigatedButton).toBeVisible();
      await expect(navigatedButton).toHaveAccessibleName("Copy code");
      const navigatedSource = await navigatedBlock.locator(":scope > pre").textContent();
      await navigatedButton.click();
      await expect(navigatedButton).toHaveAccessibleName("Copied");
      expect(await page.evaluate(() =>
        (window as typeof window & { __copiedCode?: string }).__copiedCode
      )).toBe(navigatedSource);

      await page.getByRole("navigation", { name: "Documentation", exact: true })
        .getByRole("link", { name: "Syntax", exact: true }).click();
      await expect(page).toHaveURL(site("docs", "/docs/Syntax/"));
      const returnedDiagram = page.locator("[data-mermaid-rendered]");
      await expect(returnedDiagram).toHaveCount(1);
      await expect(returnedDiagram.locator("button[data-copy-source]")).toHaveCount(1);
      const returnedMath = page.locator("[data-math-rendered]");
      await expect.poll(() => returnedMath.count()).toBeGreaterThan(0);
      await expect(returnedMath.locator("button[data-copy-source]"))
        .toHaveCount(await returnedMath.count());
    }
  });
}

test("localized code block actions announce their state in the page language", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one localized interaction is sufficient");
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: async () => { throw new Error("denied"); } }
    });
  });
  await page.goto(localizedDocs("/zh-CN/docs/Syntax/"));

  const first = page.locator("[data-code-block-copy]").first();
  const button = first.locator("button[data-copy-code]");
  await expect(button).toHaveAccessibleName("复制代码");
  await button.click();
  await expect(button).toHaveAccessibleName("已复制");
  await expect(first.getByRole("status")).toHaveText("已复制");
  const localizedDiagramAction = page.locator("[data-mermaid-rendered] button[data-copy-source]");
  await expect(localizedDiagramAction).toHaveAccessibleName("复制图表源码");
  await expect(localizedDiagramAction).toHaveAttribute("lang", "zh-CN");
  const localizedFormulaAction = page.locator("[data-math-rendered] button[data-copy-source]").first();
  await expect(localizedFormulaAction).toHaveAccessibleName("复制公式源码");
  await expect(localizedFormulaAction).toHaveAttribute("lang", "zh-CN");

  await page.goto(localizedDocs("/zh-CN/docs/development/"));
  const fallbackContent = page.locator(".note-content");
  await expect(fallbackContent).toHaveAttribute("lang", "en");
  const fallbackBlock = fallbackContent.locator("[data-code-block-copy]").first();
  const fallbackButton = fallbackBlock.locator("button[data-copy-code]");
  const fallbackStatus = fallbackBlock.getByRole("status");
  await expect(fallbackButton).toHaveAttribute("lang", "zh-CN");
  await expect(fallbackButton).toHaveAttribute("dir", "ltr");
  await expect(fallbackStatus).toHaveAttribute("lang", "zh-CN");
  await expect(fallbackStatus).toHaveAttribute("dir", "ltr");
  const selectedText = await fallbackContent.locator("p").first().evaluate((paragraph) => {
    const range = document.createRange();
    range.selectNodeContents(paragraph);
    const selection = document.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(range);
    return selection.toString();
  });
  expect(selectedText).not.toBe("");
  await fallbackButton.focus();
  await page.keyboard.press("Enter");
  await expect(fallbackButton).toHaveAccessibleName("已复制");
  await expect(fallbackStatus).toHaveText("已复制");
  await expect(fallbackButton).toBeFocused();
  expect(await page.evaluate(() => document.getSelection()?.toString())).toBe(selectedText);
});

test("View as Markdown remains reachable without JavaScript", async ({ browser }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one no-JS browser contract is sufficient");
  const context = await browser.newContext({ javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));

  const actions = page.locator("[data-page-actions]");
  await expect(actions.locator(".page-actions__primary")).toBeHidden();
  await actions.locator("summary").click();
  await expect(actions.getByRole("button", { name: "Copy page" })).toHaveCount(0);
  const view = actions.getByRole("link", { name: /View as Markdown/ });
  await expect(view).toBeVisible();
  await expect(view).toHaveAttribute("href", /\.md$/);
  await context.close();
});

test("Copy failure opens a visible Markdown fallback", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one visible failure contract is sufficient");
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  await page.route(/\.md$/, (route) => route.fulfill({ status: 503, body: "Unavailable" }));

  const actions = page.locator("[data-page-actions]");
  await actions.locator(".page-actions__primary").click();

  await expect(actions.locator("[data-copy-page-error]")).toBeVisible();
  await expect(actions.locator("[data-copy-page-error]")).toContainText("View as Markdown");
  await expect(actions.getByRole("link", { name: /View as Markdown/ })).toBeVisible();
});

test("Mobile Copy page keeps a dynamic accessible name while showing only its icon", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "one mobile rendering contract is sufficient");
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { async writeText() {} }
    });
  });

  await page.setViewportSize({ width: 520, height: 900 });
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  const actions = page.locator("[data-page-actions]");
  const primary = actions.locator(".page-actions__primary");
  const primaryLabel = primary.locator("[data-copy-page-label]");
  await expect(primary).toHaveAccessibleName("Copy page");
  await expect(primary.locator("svg")).toBeVisible();
  const mobileBox = await primary.boundingBox();
  const rootFontSize = await page.locator("html").evaluate((element) =>
    Number.parseFloat(getComputedStyle(element).fontSize)
  );
  expect(mobileBox?.width).toBeCloseTo(2.55 * rootFontSize, 0);
  expect(mobileBox?.height).toBeGreaterThanOrEqual(40);
  expect(await primaryLabel.evaluate((element) => {
    const box = element.getBoundingClientRect();
    return box.width <= 1 && box.height <= 1 && getComputedStyle(element).clipPath === "inset(50%)";
  })).toBe(true);

  await actions.locator("summary").click();
  await expect(actions.locator(".page-actions__item [data-copy-page-label]")).toBeVisible();
  await expect(actions.locator(".page-actions__item [data-copy-page-label]")).toHaveText("Copy page");
  await actions.locator("summary").click();
  await primary.click();
  await expect(primary).toHaveAccessibleName("Copied");

  await page.setViewportSize({ width: 521, height: 900 });
  await expect(primaryLabel).toBeVisible();
  expect((await primaryLabel.boundingBox())?.width).toBeGreaterThan(1);
});

test("Minimal Home combines authored content with at most six recent posts", async ({ page }, testInfo) => {
  await page.goto(site("minimal"));

  const article = page.locator(".minimal-entry");
  await expect(article).toHaveClass(/website-home/);
  await expect(article.getByRole("heading", { level: 1, name: "One Markdown folder, two ways to publish" })).toBeVisible();
  await expect(article).toContainText("A complete blog or documentation site from a Markdown folder.");
  await expect(article).toContainText("with nothing to install or run locally");
  await expect(article).toContainText("the included workflow builds the selected theme and publishes it to Pages");
  const sourceActions = article.locator(".source-actions");
  const edit = sourceActions.getByRole("link", { name: "Edit", exact: true });
  await expect(edit).toBeVisible();
  await expect(sourceActions.getByRole("link")).toHaveCount(1);
  await expect(edit.locator(".source-actions__icon[aria-hidden='true']")).toBeVisible();
  expect(await edit.evaluate((element) => getComputedStyle(element).borderTopWidth)).toBe("0px");
  expect((await sourceActions.boundingBox())!.height).toBeLessThanOrEqual(40);

  const recent = page.locator(".minimal-recent");
  await expect(recent.getByRole("heading", { level: 2, name: "Recent posts" })).toBeVisible();
  const cards = recent.locator(".minimal-post-card");
  await expect(cards).toHaveCount(2);
  expect(await cards.count()).toBeLessThanOrEqual(6);
  await expect(cards.first().getByRole("link", { name: "One vault, two site models" })).toBeVisible();
  await expect(cards.first().locator(".minimal-post-card__excerpt"))
    .toHaveText("Why Minimal and Docs share one compiler but not one layout.");
  await expect(cards.first().locator("time")).toHaveAttribute("datetime", "2026-08-01T00:00:00Z");
  await expect(cards.first().locator(".minimal-post-card__media img"))
    .toHaveAttribute("src", /\/__site__\/minimal\/assets\/vault\/assets\/research-folio\.svg$/);
  await expect(cards.nth(1).locator(".minimal-post-card__media")).toHaveCount(0);
  await expect(recent.getByRole("link", { name: /View all/ }))
    .toHaveAttribute("href", site("minimal", "/blog/"));
  await expect(cards.locator(":not(.minimal-post-card--with-image) .minimal-post-card__media"))
    .toHaveCount(0);
  await expect(page.locator(".blog-post-feed, .blog-pager, link[rel='next']")).toHaveCount(0);

  const contacts = page.getByRole("navigation", { name: "Contact" });
  await expect(contacts.locator(".minimal-contact--icon")).toHaveCount(2);
  const github = contacts.getByRole("link", { name: "GitHub" });
  const x = contacts.getByRole("link", { name: "X", exact: true });
  await expect(github).toHaveAttribute("href", "https://github.com/wowfun");
  await expect(x).toHaveAttribute("href", "https://x.com/wowfuna");
  await expect(github.locator("svg")).toHaveClass(/minimal-contact__icon--brand/);
  await expect(x.locator("svg")).toHaveClass(/minimal-contact__icon--brand/);
  await expect(x.locator("svg")).toHaveCSS("stroke", "none");
  for (const link of [github, x]) {
    await expect(link).toHaveCSS("border-top-width", "0px");
    await expect(link.locator("svg[aria-hidden='true']")).toBeVisible();
    expect((await link.locator("svg").boundingBox())!.width).toBeGreaterThanOrEqual(21);
    const box = await link.boundingBox();
    expect(Math.abs(box!.width - box!.height)).toBeLessThanOrEqual(1);
  }
  expect((await new AxeBuilder({ page }).include(".minimal-contacts").analyze()).violations).toEqual([]);

  if (testInfo.project.name === "desktop-chromium") {
    const firstTitle = cards.getByRole("heading", { level: 3 }).first();
    expect(Number.parseFloat(await firstTitle.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeLessThanOrEqual(29);
  }
});

test("Minimal recent post cards expose one article link across the whole card", async ({ page }) => {
  await page.goto(site("minimal"));
  const generatedCard = page.locator(".minimal-post-card").first();
  const generatedTitle = generatedCard.getByRole("link", { name: "One vault, two site models" });
  const generatedHref = await generatedTitle.getAttribute("href");
  expect(generatedHref).toBeTruthy();
  await expect(generatedCard.locator(`a[href="${generatedHref}"]`)).toHaveCount(1);
  await expect(generatedCard.locator(".minimal-post-card__media")).not.toHaveAttribute("href", /.+/);
  await expect(generatedCard.locator(".minimal-post-card__media img")).toHaveAttribute("alt", "");

  await page.goto("/__fixture__/post-card/");
  const card = page.locator(".minimal-post-card");
  const title = card.getByRole("link", { name: "A complete card target" });
  await title.focus();
  await expect(title).toBeFocused();
  expect(await card.evaluate((element) => getComputedStyle(element).boxShadow)).not.toBe("none");
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/__fixture__\/post-target\/$/);

  await page.goBack();
  const mediaBox = await page.locator(".minimal-post-card__media").boundingBox();
  expect(mediaBox).toBeTruthy();
  await page.mouse.click(mediaBox!.x + mediaBox!.width / 2, mediaBox!.y + mediaBox!.height / 2);
  await expect(page).toHaveURL(/\/__fixture__\/post-target\/$/);

  await page.goBack();
  const excerptBox = await page.locator(".minimal-post-card__excerpt").boundingBox();
  expect(excerptBox).toBeTruthy();
  await page.mouse.click(excerptBox!.x + excerptBox!.width / 2, excerptBox!.y + excerptBox!.height / 2);
  await expect(page).toHaveURL(/\/__fixture__\/post-target\/$/);

  await page.goBack();
  await page.getByRole("link", { name: "Ada" }).click();
  await expect(page).toHaveURL(/\/__fixture__\/author-target\/$/);
});

test("Minimal Portfolio filters one-column projects and keeps repository links independent", async ({ page }) => {
  await page.goto(site("minimal", "/portfolio/"));

  await expect(page.getByRole("heading", { level: 1, name: "Portfolio" })).toHaveCount(0);
  const projectsHeading = page.getByRole("heading", { level: 1, name: "Projects" });
  await expect(projectsHeading).toBeVisible();
  await expect(page.locator(".site-header [data-navigation-id='portfolio'] a"))
    .toHaveAttribute("aria-current", "page");

  const portfolio = page.locator(".minimal-portfolio");
  const grid = page.locator(".minimal-portfolio__grid");
  const card = grid.locator("article.minimal-portfolio-card");
  await expect(card).toHaveCount(1);
  await expect(card.locator("div.minimal-portfolio-card__body")).toHaveCount(1);
  await expect(card.getByRole("heading", { level: 2, name: "Jekyll Obsidian" })).toBeVisible();
  await expect(card.locator(".minimal-portfolio-card__summary"))
    .toHaveText("Publish any Markdown folder as a complete site. Nothing to install or build locally.");
  const projectLink = card.getByRole("link", { name: "Jekyll Obsidian", exact: true });
  await expect(projectLink).toHaveAttribute("href", site("minimal", "/portfolio/jekyll-obsidian/"));
  const repositoryLink = card.getByRole("link", { name: "Open Jekyll Obsidian on GitHub" });
  await expect(repositoryLink).toHaveAttribute("href", "https://github.com/wowfun/jekyll-obsidian");
  await expect(repositoryLink.locator("svg[aria-hidden='true']")).toBeVisible();
  await expect(card.locator("a a")).toHaveCount(0);
  await expect(card.getByRole("link")).toHaveCount(2);
  const cardTopics = card.locator(".minimal-portfolio-card__topics");
  await expect(cardTopics).toContainText("Ruby");
  await expect(cardTopics).toContainText("TypeScript");
  await expect(cardTopics).toContainText("Static Site Generator");
  const cardTopicChips = cardTopics.locator(".tag-chip");
  await expect(cardTopicChips).toHaveCount(6);
  const cardTopicHeights = await cardTopicChips.evaluateAll((chips) =>
    chips.map((chip) => chip.getBoundingClientRect().height)
  );
  expect(Math.max(...cardTopicHeights) - Math.min(...cardTopicHeights)).toBeLessThanOrEqual(1);
  expect(await cardTopics.locator("li").evaluateAll((items) => items.every((item) => {
    const capsule = item.querySelector(".tag-chip")!.getBoundingClientRect();
    const box = item.getBoundingClientRect();
    return Math.abs(box.width - capsule.width) <= 1 && Math.abs(box.height - capsule.height) <= 1;
  }))).toBe(true);

  const filter = page.getByRole("navigation", { name: "Filter by topic" });
  await expect(filter.getByRole("link", { name: /^All\b/ })).toHaveAttribute("aria-current", "page");
  await expect(filter.getByRole("link", { name: /TypeScript/ })).toContainText("1");
  await filter.getByRole("link", { name: /TypeScript/ }).click();
  await expect(page).toHaveURL(/\/portfolio\/\?topic=typescript$/);
  await expect(filter.getByRole("link", { name: /TypeScript/ })).toHaveAttribute("aria-current", "page");
  await expect(grid.locator("[data-filter-item]:visible")).toHaveCount(1);
  await filter.getByRole("link", { name: /^All\b/ }).click();
  await expect(page).toHaveURL(site("minimal", "/portfolio/"));

  const image = card.locator(".minimal-portfolio-card__media img");
  await expect(image).toHaveAttribute("src", /\/__site__\/minimal\/assets\/vault\/assets\/research-folio\.svg$/);
  await expect(image).toHaveAttribute("alt", "");
  await expect(image).toHaveAttribute("loading", "lazy");
  await expect(image).toHaveAttribute("decoding", "async");

  const entryBox = (await page.locator(".minimal-entry").boundingBox())!;
  const portfolioBox = (await portfolio.boundingBox())!;
  const headingBox = (await projectsHeading.boundingBox())!;
  const gridBox = (await grid.boundingBox())!;
  expect(portfolioBox.x).toBeCloseTo(entryBox.x, 0);
  expect(portfolioBox.y).toBeCloseTo(entryBox.y, 0);
  expect(headingBox.x).toBeCloseTo(gridBox.x, 0);

  const columns = await grid.evaluate((element) =>
    getComputedStyle(element).gridTemplateColumns.split(" ").filter(Boolean).length
  );
  expect(columns).toBe(1);
  const media = await card.locator(".minimal-portfolio-card__media").boundingBox();
  expect(media).toBeTruthy();
  expect(media!.width / media!.height).toBeCloseTo(1.6, 1);

  const repositoryBox = (await repositoryLink.boundingBox())!;
  const cardBox = (await card.boundingBox())!;
  expect(repositoryBox.width).toBeGreaterThanOrEqual(44);
  expect(repositoryBox.height).toBeGreaterThanOrEqual(44);
  expect(repositoryBox.x + repositoryBox.width).toBeLessThanOrEqual(cardBox.x + cardBox.width + 1);

  await projectLink.focus();
  await page.keyboard.press("Tab");
  await expect(repositoryLink).toBeFocused();
  expect(await repositoryLink.evaluate((element) => getComputedStyle(element).boxShadow)).not.toBe("none");
  await page.keyboard.press("Shift+Tab");
  await expect(projectLink).toBeFocused();
  expect(await card.evaluate((element) => getComputedStyle(element).boxShadow)).not.toBe("none");
  const summaryBox = (await card.locator(".minimal-portfolio-card__summary").boundingBox())!;
  await page.mouse.click(summaryBox.x + summaryBox.width / 2, summaryBox.y + summaryBox.height / 2);
  await expect(page).toHaveURL(site("minimal", "/portfolio/jekyll-obsidian/"));
  await page.goBack();
  await expect(page).toHaveURL(site("minimal", "/portfolio/"));
  await projectLink.focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(site("minimal", "/portfolio/jekyll-obsidian/"));
  await expect(page.getByRole("heading", { level: 1, name: "Imported Jekyll Obsidian" })).toBeVisible();
  const detailDescription = page.locator(".note-header .note-description");
  const detailTopics = page.locator(".note-header .minimal-portfolio-card__topics");
  await expect(detailTopics.locator("li")).toHaveText([
    "Jekyll",
    "Obsidian",
    "jekyll-obsidian",
    "Ruby",
    "TypeScript",
    "Static Site Generator"
  ]);
  const detailTopicLinks = detailTopics.getByRole("link");
  await expect(detailTopicLinks).toHaveCount(6);
  await expect(detailTopicLinks.getByText("Ruby", { exact: true }))
    .toHaveAttribute("href", site("minimal", "/portfolio/?topic=ruby"));
  const detailTopicHeights = await detailTopicLinks.evaluateAll((links) =>
    links.map((link) => link.getBoundingClientRect().height)
  );
  expect(Math.max(...detailTopicHeights) - Math.min(...detailTopicHeights)).toBeLessThanOrEqual(1);
  expect(await detailTopics.locator("li").evaluateAll((items) => items.every((item) => {
    const capsule = item.querySelector(".tag-chip")!.getBoundingClientRect();
    const box = item.getBoundingClientRect();
    return Math.abs(box.width - capsule.width) <= 1 && Math.abs(box.height - capsule.height) <= 1;
  }))).toBe(true);
  expect(await detailDescription.evaluate((description) =>
    description.nextElementSibling?.classList.contains("minimal-portfolio-card__topics")
  )).toBe(true);
  const sourceActions = page.getByRole("navigation", { name: "Contribute to this page" });
  const editLink = sourceActions.getByRole("link", { name: "Edit", exact: true });
  const detailRepositoryLink = sourceActions.getByRole("link", { name: "Open Jekyll Obsidian on GitHub" });
  await expect(editLink).toBeVisible();
  await expect(detailRepositoryLink)
    .toHaveAttribute("href", "https://github.com/wowfun/jekyll-obsidian");
  const sourceActionsBox = (await sourceActions.boundingBox())!;
  const editBox = (await editLink.boundingBox())!;
  const detailRepositoryBox = (await detailRepositoryLink.boundingBox())!;
  expect(detailRepositoryBox.x).toBeGreaterThan(editBox.x + editBox.width);
  expect(detailRepositoryBox.x + detailRepositoryBox.width)
    .toBeCloseTo(sourceActionsBox.x + sourceActionsBox.width, 0);
  await expect(page.getByRole("link", { name: "View imported Markdown" })).toHaveAttribute(
    "href",
    "https://github.com/wowfun/jekyll-obsidian/blob/0123456789abcdef0123456789abcdef01234567/README.md"
  );
  await detailTopicLinks.getByText("Ruby", { exact: true }).focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(site("minimal", "/portfolio/?topic=ruby"));
  await expect(page.getByRole("navigation", { name: "Filter by topic" })
    .getByRole("link", { name: /Ruby/ })).toHaveAttribute("aria-current", "page");
});

test("Mermaid HTML labels render and stay inside each theme reading column", async ({ page }, testInfo) => {
  if (testInfo.project.name === "mobile-chromium") {
    await page.setViewportSize({ width: 390, height: 900 });
  }

  for (const theme of themes) {
    await page.goto(site(theme, "/portfolio/jekyll-obsidian/"));
    const content = page.locator(".note-content");
    const figure = content.locator(":scope > .mermaid-diagram");
    await expect(figure).toBeVisible();
    await expect(content.locator("pre[data-mermaid-error]")).toHaveCount(0);
    await expect(figure.locator("foreignObject br")).toHaveCount(1);
    expect(await figure.locator("template[data-mermaid-source]").evaluate((template) =>
      (template as HTMLTemplateElement).content.textContent
    )).toContain("<br/>");
    await expect(figure.locator("button[data-copy-source]")).toHaveCount(1);
    await expect(figure.locator("button[data-copy-source]")).toHaveAccessibleName("Copy diagram source");

    const geometry = await figure.locator(":scope > svg").evaluate((svg) => {
      const viewBox = (svg as SVGSVGElement).viewBox.baseVal;
      const content = (svg as SVGSVGElement).getBBox();
      return {
        content: { width: content.width, height: content.height },
        viewBox: { width: viewBox.width, height: viewBox.height }
      };
    });
    expect(geometry.viewBox.width / geometry.content.width, `${theme} Mermaid horizontal fill`)
      .toBeLessThan(2);
    expect(geometry.viewBox.height / geometry.content.height, `${theme} Mermaid vertical fill`)
      .toBeLessThan(2);

    const prose = (await content.locator(":scope > p").first().boundingBox())!;
    const diagram = (await figure.boundingBox())!;
    expect(diagram.x, `${theme} Mermaid left`).toBeCloseTo(prose.x, 0);
    expect(diagram.x + diagram.width, `${theme} Mermaid right`).toBeCloseTo(prose.x + prose.width, 0);
    expect(await page.evaluate(() => document.documentElement.scrollWidth), `${theme} page width`)
      .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));

    await figure.locator(":scope > svg").evaluate((svg) => { svg.dataset.renderCycle = "initial"; });
    await page.locator("[data-color-scheme-toggle]").click();
    await expect(content.locator(".mermaid-diagram > svg[data-render-cycle='initial']")).toHaveCount(0);
    const redrawn = content.locator(":scope > .mermaid-diagram");
    await expect(redrawn).toBeVisible();
    await expect(redrawn.locator("foreignObject br")).toHaveCount(1);
    await expect(redrawn.locator("button[data-copy-source]")).toHaveCount(1);
    await expect(redrawn.locator("button[data-copy-source]")).toHaveAccessibleName("Copy diagram source");
    await expect(content.locator("pre[data-mermaid-error]")).toHaveCount(0);
  }
});

test("simple Mermaid flowcharts do not reserve a mostly blank canvas", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });

  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Syntax/"));
    const svg = page.locator(".note-content > .mermaid-diagram > svg");
    await expect(svg).toBeVisible();
    await page.evaluate(() => new Promise<void>((resolve) =>
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()))
    ));

    const geometry = await svg.evaluate((element) => {
      const diagram = element as SVGSVGElement;
      const viewBox = diagram.viewBox.baseVal;
      const content = diagram.getBBox();
      return {
        content: { width: content.width, height: content.height },
        viewBox: { width: viewBox.width, height: viewBox.height }
      };
    });
    expect(geometry.viewBox.width / geometry.content.width, `${theme} Mermaid horizontal fill`)
      .toBeLessThan(2);
    expect(geometry.viewBox.height / geometry.content.height, `${theme} Mermaid vertical fill`)
      .toBeLessThan(2);
  }
});

test("Minimal recent posts use editorial rows without reserving an empty media column", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "responsive layout contract");
  await page.setViewportSize({ width: 1440, height: 1000 });
  await page.goto(site("minimal"));
  const cards = page.locator(".minimal-post-card");
  const firstCard = (await cards.first().boundingBox())!;
  const secondCard = (await cards.nth(1).boundingBox())!;
  expect(secondCard.y).toBeGreaterThanOrEqual(firstCard.y + firstCard.height - 1);

  const media = (await cards.first().locator(".minimal-post-card__media").boundingBox())!;
  const imagedBody = (await cards.first().locator(".minimal-post-card__body").boundingBox())!;
  expect(media.x + media.width).toBeLessThanOrEqual(imagedBody.x);
  expect(media.width / media.height).toBeCloseTo(16 / 9, 1);
  await expect(cards.nth(1).locator(".minimal-post-card__media")).toHaveCount(0);
  const textOnlyBody = (await cards.nth(1).locator(".minimal-post-card__body").boundingBox())!;
  expect(textOnlyBody.width).toBeCloseTo(secondCard.width, 0);

  await page.setViewportSize({ width: 720, height: 1000 });
  const stackedMedia = (await cards.first().locator(".minimal-post-card__media").boundingBox())!;
  const stackedBody = (await cards.first().locator(".minimal-post-card__body").boundingBox())!;
  expect(stackedBody.y).toBeGreaterThanOrEqual(stackedMedia.y + stackedMedia.height);
});

test("Minimal navigation discovers Portfolio and marks each built-in scope", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop primary navigation assertion");

  for (const [route, current] of [["/", "Home"], ["/blog/", "Blog"], ["/docs/Getting%20Started/", "Docs"], ["/portfolio/", "Portfolio"]] as const) {
    await page.goto(site("minimal", route));
    const navigation = page.getByRole("navigation", { name: "Primary navigation" });
    await expect(navigation.locator(":scope > ul > li > a")).toHaveText(["Home", "Blog", "Docs", "Portfolio"]);
    await expect(navigation.getByRole("link", { name: current, exact: true })).toHaveAttribute("aria-current", "page");
  }
});

test("Minimal Home owns counted Topics and article pages do not repeat them", async ({ page }, testInfo) => {
  if (testInfo.project.name === "desktop-chromium") {
    await page.goto(site("minimal"));
    const topics = page.locator("[data-context-panel]");
    await expect(topics).toHaveAttribute("aria-label", "Page context");
    await expect(topics.locator("[data-local-graph-section]")).toBeVisible();
    await expect(topics.getByRole("heading", { name: "On this page" })).toBeVisible();
    const capsule = topics.locator(".context-tag-list a", { hasText: "release-notes" });
    await expect(capsule.locator(".context-tag__count")).toHaveText("1");
    await expect(capsule).toHaveAttribute("href", /\/blog\/\?topic=/);
    await expect(capsule).not.toContainText("#");
    await expect(capsule).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");

    await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
    await expect(page.locator("[data-context-panel]").getByRole("heading", { name: "Topics" })).toHaveCount(0);
  } else {
    await page.goto(site("minimal"));
    await page.getByRole("button", { name: "Context" }).tap();
    const dialog = page.locator('dialog[data-dialog="context"]');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator(".context-tag-list a", { hasText: "release-notes" })
      .locator(".context-tag__count")).toHaveText("1");
  }
});

test("Blog filters by topic and exposes only populated chronology periods", async ({ page }, testInfo) => {
  await page.goto(site("minimal", "/blog/"));
  await expect(page.locator("h1:not(.visually-hidden)", { hasText: "Blog" })).toHaveCount(0);
  const semanticTitle = page.locator("h1.visually-hidden");
  await expect(semanticTitle).toHaveText("Blog");
  expect((await semanticTitle.boundingBox())!.width).toBeLessThanOrEqual(1);
  await expect(page.getByRole("heading", { name: "Archive" })).toHaveCount(0);

  const filter = page.getByRole("navigation", { name: "Filter by topic" });
  if (testInfo.project.name === "desktop-chromium") {
    const entry = (await page.locator(".minimal-entry").boundingBox())!;
    const filterBox = (await filter.boundingBox())!;
    expect(filterBox.x).toBeCloseTo(entry.x, 0);
    expect(filterBox.y).toBeCloseTo(entry.y, 0);
  }
  await expect(filter.getByRole("link", { name: /^All\b/ })).toHaveAttribute("aria-current", "page");
  await filter.getByRole("link", { name: /release-notes/ }).click();
  await expect(page).toHaveURL(/\/blog\/\?topic=release-notes$/);
  await expect(filter.getByRole("link", { name: /release-notes/ })).toHaveAttribute("aria-current", "page");
  await expect(filter.getByRole("link", { name: /release-notes/ })).not.toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
  const visibleReleaseCapsule = page.locator("[data-filter-item]:visible .blog-ledger__topics a", {
    hasText: "release-notes"
  });
  await expect(visibleReleaseCapsule).not.toHaveAttribute("aria-current", "page");
  await expect(visibleReleaseCapsule).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
  await expect(page.locator("[data-filter-item]:visible").getByRole("link", { name: "One vault, two site models" })).toBeVisible();
  await expect(page.locator("[data-filter-item]", { hasText: "从笔记到发布" })).toBeHidden();
  await filter.getByRole("link", { name: /^All\b/ }).click();
  await expect(page).toHaveURL(site("minimal", "/blog/"));
  const entries = page.locator("[data-filter-item]:visible");
  await expect(entries).toHaveCount(2);
  await expect(entries.nth(0).locator("time")).toHaveText("2026-08-01");
  await expect(entries.nth(1).locator("time")).toHaveText("2026-07-31");
  await expect(entries.nth(0).locator(".blog-ledger__description"))
    .toHaveText("Why Minimal and Docs share one compiler but not one layout.");
  await expect(entries.nth(1).locator(".blog-ledger__description"))
    .toHaveText("同一个 Obsidian vault 如何保持写作格式，同时生成不同的信息结构。");
  await expect(entries.locator(".blog-ledger__topics")).toHaveCount(2);
  await expect(entries.locator("a a")).toHaveCount(0);
  await expect(entries.nth(0).locator(".blog-ledger__meta").locator(".blog-ledger__topics"))
    .toHaveCount(0);
  const firstMainLink = entries.nth(0).locator("a.blog-ledger__main");
  await expect(firstMainLink).toHaveAttribute(
    "href",
    site("minimal", "/blog/One%20vault%2C%20three%20readings/")
  );
  await expect(firstMainLink.locator(".blog-ledger__description"))
    .toHaveText("Why Minimal and Docs share one compiler but not one layout.");
  const firstTopics = entries.nth(0).locator(".blog-ledger__topics a");
  await expect(firstTopics).toHaveText(["release-notes", "themes", "Architecture"]);
  expect(await firstTopics.evaluateAll((links) =>
    links.every((link) => link.hasAttribute("data-topic-filter-option"))
  )).toBe(true);
  await expect(firstTopics.nth(1)).toHaveAttribute(
    "href",
    site("minimal", "/blog/?topic=themes")
  );

  await firstTopics.nth(1).focus();
  await expect(firstTopics.nth(1)).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/blog\/\?topic=themes$/);
  await expect(filter.getByRole("link", { name: /themes/ })).toHaveAttribute("aria-current", "page");
  await expect(firstTopics.nth(1)).not.toHaveAttribute("aria-current", "page");
  await expect(firstTopics.nth(1)).toHaveCSS("background-color", "rgba(0, 0, 0, 0)");
  await expect(page.locator("[data-filter-item]:visible")).toHaveCount(1);
  await filter.getByRole("link", { name: /^All\b/ }).click();
  await expect(page).toHaveURL(site("minimal", "/blog/"));

  if (testInfo.project.name === "desktop-chromium") {
    const firstMeta = (await entries.nth(0).locator(".blog-ledger__meta").boundingBox())!;
    const firstContent = (await entries.nth(0).locator(".blog-ledger__content").boundingBox())!;
    const firstTitle = (await firstMainLink.locator("strong").boundingBox())!;
    const firstDate = entries.nth(0).locator("time");
    const firstDateBox = (await firstDate.boundingBox())!;
    const firstTopicListBox = (await entries.nth(0).locator(".blog-ledger__topics").boundingBox())!;
    expect(firstTitle.x - (firstMeta.x + firstMeta.width)).toBeLessThanOrEqual(13);
    expect(firstTopicListBox.x).toBeCloseTo(firstContent.x, 0);
    expect(firstTopicListBox.y).toBeGreaterThan(
      (await firstMainLink.locator(".blog-ledger__description").boundingBox())!.y
    );
    expect(Math.abs(
      firstDateBox.y + (firstDateBox.height / 2) - (firstContent.y + (firstContent.height / 2))
    )).toBeLessThanOrEqual(1);
    expect(Number.parseFloat(await firstDate.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeGreaterThanOrEqual(13);

    const chronology = page.getByRole("navigation", { name: "Chronology" });
    const chronologyHeading = (await chronology.getByRole("heading", { name: "Chronology" }).boundingBox())!;
    const archiveHeading = (await page.locator(".archive-ledger > section > h2").first().boundingBox())!;
    expect(chronologyHeading.y).toBeCloseTo(archiveHeading.y, 0);
    const filterBox = (await filter.boundingBox())!;
    const initialLedgerTop = archiveHeading.y;
    expect(initialLedgerTop - (filterBox.y + filterBox.height)).toBeLessThanOrEqual(42);
    await expect(chronology.locator('[data-filter-year="2026"] .archive-timeline__count')).toHaveText("2");
    await expect(chronology.locator('[data-filter-month="2026-08"] .archive-timeline__count')).toHaveText("1");
    await expect(chronology.locator('[data-filter-month="2026-07"] .archive-timeline__count')).toHaveText("1");
    await expect(chronology.locator('[data-filter-month="2026-06"]')).toHaveCount(0);
    await expect(chronology.locator("[data-month-filter-option] > span:first-child")).toHaveText(["07", "08"]);

    await chronology.locator('[data-filter-month="2026-07"]').click();
    await expect(page).toHaveURL(/\/blog\/\?month=2026-07$/);
    await expect(page.locator("[data-filter-item]:visible")).toHaveCount(1);
    await expect(chronology.locator('[data-filter-month="2026-07"]')).toHaveAttribute("aria-current", "page");
    expect((await page.locator(".archive-ledger > section > h2").first().boundingBox())!.y)
      .toBeCloseTo(initialLedgerTop, 0);
    expect((await chronology.getByRole("heading", { name: "Chronology" }).boundingBox())!.y)
      .toBeCloseTo(initialLedgerTop, 0);
    await chronology.locator('[data-filter-month="2026-07"]').click();
    await expect(page).toHaveURL(site("minimal", "/blog/"));
    await expect(chronology.locator('[data-filter-month="2026-07"]')).not.toHaveAttribute("aria-current", "page");
    await expect(page.locator("[data-filter-item]:visible")).toHaveCount(2);
    await chronology.locator('[data-filter-year="2026"]').click();
    await expect(page).toHaveURL(/\/blog\/\?year=2026$/);
    await expect(page.locator("[data-filter-item]:visible")).toHaveCount(2);
    await expect(chronology.locator('[data-filter-year="2026"]')).toHaveAttribute("aria-current", "page");
    await chronology.locator('[data-filter-year="2026"]').click();
    await expect(page).toHaveURL(site("minimal", "/blog/"));
    await expect(chronology.locator('[data-filter-year="2026"]')).not.toHaveAttribute("aria-current", "page");
    await expect(page.locator("[data-filter-item]:visible")).toHaveCount(2);

    const year = page.locator(".archive-ledger > section > h2", { hasText: "2026" });
    expect(Number.parseFloat(await year.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeGreaterThanOrEqual(24);
  } else {
    const firstRow = entries.nth(0);
    const rowBox = (await firstRow.boundingBox())!;
    const dateBox = (await firstRow.locator("time").boundingBox())!;
    const contentBox = (await firstRow.locator(".blog-ledger__content").boundingBox())!;
    expect(dateBox.y).toBeLessThan(contentBox.y);
    expect(contentBox.y + contentBox.height).toBeLessThanOrEqual(rowBox.y + rowBox.height + 1);
    expect(await firstRow.evaluate((row) => row.scrollWidth <= row.clientWidth)).toBe(true);
    for (const topic of await firstRow.locator(".blog-ledger__topics a").all()) {
      const box = (await topic.boundingBox())!;
      expect(box.x).toBeGreaterThanOrEqual(rowBox.x - 1);
      expect(box.x + box.width).toBeLessThanOrEqual(rowBox.x + rowBox.width + 1);
    }

    await page.getByRole("button", { name: "Chronology" }).tap();
    const dialog = page.locator('dialog[data-dialog="context"]');
    await expect(dialog).toBeVisible();
    await dialog.locator('[data-filter-month="2026-07"]').tap();
    await expect(page).toHaveURL(/\/blog\/\?month=2026-07$/);
    await expect(dialog.locator('[data-filter-month="2026-07"]')).toHaveAttribute("aria-current", "page");
    await expect(page.locator("[data-filter-item]:not([hidden])")).toHaveCount(1);
    await dialog.locator('[data-filter-month="2026-07"]').tap();
    await expect(page).toHaveURL(site("minimal", "/blog/"));
    await expect(dialog.locator('[data-filter-month="2026-07"]')).not.toHaveAttribute("aria-current", "page");
    await expect(page.locator("[data-filter-item]:not([hidden])")).toHaveCount(2);
  }
});

test("Minimal post metadata places distinct Blog topics beside the publication date", async ({ page }, testInfo) => {
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));

  const header = page.locator(".note-header");
  const description = header.locator(".note-description");
  const published = header.locator(".note-meta > time").first();
  const topics = header.locator(".note-meta__topics");
  const chips = topics.locator(".tag-chip");
  await expect(published).toHaveText("Published 2026-08-01");
  await expect(chips).toHaveText(["release-notes", "themes", "Architecture"]);
  const expectedTopicUrls = [
    site("minimal", "/blog/?topic=release-notes"),
    site("minimal", "/blog/?topic=themes"),
    site("minimal", "/blog/?topic=architecture")
  ];
  for (const [index, url] of expectedTopicUrls.entries()) {
    await expect(chips.nth(index)).toHaveAttribute("href", url);
  }

  const headerBox = (await header.boundingBox())!;
  const descriptionBox = (await description.boundingBox())!;
  expect(descriptionBox.x).toBeCloseTo(headerBox.x, 0);
  expect(descriptionBox.width).toBeCloseTo(headerBox.width, 0);
  expect(descriptionBox.x + descriptionBox.width).toBeLessThanOrEqual(headerBox.x + headerBox.width + 1);

  if (testInfo.project.name === "desktop-chromium") {
    const publishedBox = (await published.boundingBox())!;
    const topicsBox = (await topics.boundingBox())!;
    expect(topicsBox.x).toBeGreaterThan(publishedBox.x + publishedBox.width);
    expect(topicsBox.y).toBeCloseTo(publishedBox.y, 0);
  } else {
    for (const chip of await chips.all()) {
      const box = (await chip.boundingBox())!;
      expect(box.x).toBeGreaterThanOrEqual(headerBox.x - 1);
      expect(box.x + box.width).toBeLessThanOrEqual(headerBox.x + headerBox.width + 1);
    }
  }
});

test("localized fallback post topics separate UI and content languages", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one rendered language contract is sufficient");
  await page.goto(localizedMinimal("/zh-CN/blog/One%20vault%2C%20three%20readings/"));

  await expect(page.locator("html")).toHaveAttribute("lang", "zh-CN");
  const header = page.locator(".note-header");
  await expect(header).toHaveAttribute("lang", "en");
  await expect(header).toHaveAttribute("dir", "ltr");
  const topics = header.locator(".note-meta__topics");
  await expect(topics).toHaveAttribute("aria-label", "主题");
  await expect(topics).toHaveAttribute("lang", "zh-CN");
  await expect(topics).toHaveAttribute("dir", "ltr");
  const links = topics.locator("a");
  await expect(links).toHaveCount(3);
  expect(await links.evaluateAll((elements) => elements.map((element) => ({
    lang: element.getAttribute("lang"),
    dir: element.getAttribute("dir")
  })))).toEqual([
    { lang: "en", dir: "ltr" },
    { lang: "en", dir: "ltr" },
    { lang: "en", dir: "ltr" }
  ]);
});

test("Minimal chronology fits twelve monthly capsules under Linux fallback font metrics", async ({ page }, testInfo) => {
  await page.goto(site("minimal", "/blog/"));
  await page.addStyleTag({ content: ":root { --font-system: Arial, sans-serif; }" });

  let chronology = page.getByRole("navigation", { name: "Chronology" });
  if (testInfo.project.name === "mobile-chromium") {
    await page.getByRole("button", { name: "Chronology" }).tap();
    chronology = page.locator('dialog[data-dialog="context"]')
      .getByRole("navigation", { name: "Chronology" });
  }

  const months = chronology.locator(".archive-timeline__year").first().locator("ul");
  await months.evaluate((list) => {
    const example = list.querySelector("li");
    if (!example) throw new Error("Expected at least one compiled chronology month");

    const items = Array.from({ length: 12 }, (_, index) => {
      const item = example.cloneNode(true) as HTMLLIElement;
      const link = item.querySelector<HTMLAnchorElement>("a");
      const labels = item.querySelectorAll("span");
      const label = labels.item(0);
      const count = labels.item(1);
      const month = String(index + 1).padStart(2, "0");
      if (!link || !label || !count || labels.length !== 2) {
        throw new Error("Unexpected chronology month markup");
      }
      link.dataset.filterMonth = `2026-${month}`;
      link.href = `/__site__/minimal/blog/?month=2026-${month}`;
      label.textContent = month;
      count.textContent = String(index + 1);
      return item;
    });
    list.replaceChildren(...items);
  });

  const capsules = months.locator("a[data-month-filter-option]");
  await expect(capsules).toHaveCount(12);
  await expect(capsules.locator(".archive-timeline__count"))
    .toHaveText(Array.from({ length: 12 }, (_, index) => String(index + 1)));

  const boxes = await capsules.evaluateAll((links) => links.map((link) => {
    const box = link.getBoundingClientRect();
    return { x: box.x, y: box.y, width: box.width, height: box.height };
  }));
  const first = boxes.at(0);
  const sixth = boxes.at(5);
  const seventh = boxes.at(6);
  if (!first || !sixth || !seventh || boxes.length !== 12) {
    throw new Error("Expected twelve measured chronology capsules");
  }
  for (const box of boxes.slice(1, 6)) expect(box.y).toBeCloseTo(first.y, 0);
  for (const box of boxes.slice(7)) expect(box.y).toBeCloseTo(seventh.y, 0);
  expect(sixth.x).toBeGreaterThan(first.x);
  expect(seventh.x).toBeCloseTo(first.x, 0);
  expect(seventh.y).toBeGreaterThanOrEqual(first.y + first.height);

  const layout = await months.evaluate((list) => ({
    clientWidth: list.clientWidth,
    scrollWidth: list.scrollWidth,
    clientHeight: list.clientHeight,
    scrollHeight: list.scrollHeight
  }));
  expect(layout.scrollWidth).toBeLessThanOrEqual(layout.clientWidth);
  expect(layout.scrollHeight).toBeLessThanOrEqual(layout.clientHeight);

  const capsuleStyle = await capsules.first().evaluate((link) => {
    const style = getComputedStyle(link);
    return {
      borderWidth: style.borderTopWidth,
      radius: Number.parseFloat(style.borderTopLeftRadius),
      height: link.getBoundingClientRect().height
    };
  });
  expect(capsuleStyle.borderWidth).toBe("1px");
  expect(capsuleStyle.radius).toBeGreaterThanOrEqual(4);
  expect(capsuleStyle.radius).toBeLessThan(capsuleStyle.height / 2);
});

test("Minimal navigation and Blog filters keep primary labels legible in every color mode", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop computed-style contract");

  for (const colorScheme of ["light", "dark"] as const) {
    await page.emulateMedia({ colorScheme, forcedColors: "none" });
    await page.goto(site("minimal", "/blog/"));

    const result = await page.evaluate(() => {
      const parseRgb = (value: string): [number, number, number] => {
        const channels = value.match(/[\d.]+/g)?.slice(0, 3).map(Number);
        if (!channels || channels.length !== 3) throw new Error(`Expected an RGB color, got ${value}`);
        return channels as [number, number, number];
      };
      const luminance = (value: string): number => {
        const linear = (channel: number) => {
          const normalized = channel / 255;
          return normalized <= 0.04045
            ? normalized / 12.92
            : ((normalized + 0.055) / 1.055) ** 2.4;
        };
        const [red, green, blue] = parseRgb(value);
        return (0.2126 * linear(red)) + (0.7152 * linear(green)) + (0.0722 * linear(blue));
      };
      const contrast = (foreground: string, background: string): number => {
        const foregroundLuminance = luminance(foreground);
        const backgroundLuminance = luminance(background);
        const lighter = Math.max(foregroundLuminance, backgroundLuminance);
        const darker = Math.min(foregroundLuminance, backgroundLuminance);
        return (lighter + 0.05) / (darker + 0.05);
      };
      const color = (selector: string) => getComputedStyle(document.querySelector(selector)!).color;
      const surface = getComputedStyle(document.body).backgroundColor;
      const graphite = getComputedStyle(document.documentElement).getPropertyValue("--graphite").trim();
      const primary = {
        navigation: color(".site-navigation a:not([aria-current])"),
        topic: color(".tag-filter__list a:not([aria-current]) .context-tag__name"),
        month: color("[data-month-filter-option] > span:first-child"),
        ledgerTopic: color(".blog-ledger__topics a")
      };
      const fontSize = (selector: string) =>
        Number.parseFloat(getComputedStyle(document.querySelector(selector)!).fontSize);
      return {
        primary,
        sizes: {
          navigation: fontSize(".site-navigation a:not([aria-current])"),
          topic: fontSize(".tag-filter__list a:not([aria-current]) .context-tag__name"),
          month: fontSize("[data-month-filter-option] > span:first-child"),
          ledgerTopic: fontSize(".blog-ledger__topics a")
        },
        counts: {
          topic: color(".tag-filter__list .context-tag__count"),
          month: color("[data-month-filter-option] .archive-timeline__count")
        },
        ink: color("body"),
        graphite: (() => {
          const probe = document.createElement("span");
          probe.style.color = graphite;
          document.body.append(probe);
          const computed = getComputedStyle(probe).color;
          probe.remove();
          return computed;
        })(),
        contrasts: Object.fromEntries(Object.entries(primary).map(([key, value]) => [key, contrast(value, surface)]))
      };
    });

    expect(Object.values(result.primary)).toEqual(Array(4).fill(result.ink));
    expect(Object.values(result.counts)).toEqual(Array(2).fill(result.graphite));
    expect(result.sizes.navigation).toBeGreaterThanOrEqual(12.5);
    for (const size of [result.sizes.topic, result.sizes.month, result.sizes.ledgerTopic]) {
      expect(size).toBeGreaterThanOrEqual(12);
    }
    for (const ratio of Object.values(result.contrasts)) expect(ratio).toBeGreaterThanOrEqual(7);

    await page.goto(site("minimal"));
    const contextLabel = page.locator(".context-tag-list .context-tag__name").first();
    const contextCount = page.locator(".context-tag-list .context-tag__count").first();
    await expect(contextLabel).toHaveCSS("color", result.ink);
    await expect(contextCount).toHaveCSS("color", result.graphite);
    expect(Number.parseFloat(await contextLabel.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeGreaterThanOrEqual(12);
    expect(Number.parseFloat(await contextCount.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeLessThan(Number.parseFloat(await contextLabel.evaluate((element) => getComputedStyle(element).fontSize)));

    await page.goto(site("minimal", "/portfolio/"));
    const portfolioTopic = page.locator(".minimal-portfolio-card__topics li").first();
    const portfolioSummary = page.locator(".minimal-portfolio-card__summary").first();
    await expect(portfolioTopic).toHaveCSS("color", result.ink);
    await expect(portfolioSummary).toHaveCSS("color", result.ink);
    expect(Number.parseFloat(await portfolioTopic.evaluate((element) => getComputedStyle(element).fontSize)))
      .toBeGreaterThanOrEqual(12);

    await page.goto(site("docs", "/docs/Getting%20Started/"));
    const docsPrimarySelectors = [
      ".site-navigation a:not([aria-current])",
      ".docs-tree__item > a:not([aria-current])",
      ".docs-context .outline-list a",
      ".note-description",
      ".source-actions a",
      ".docs-context .relation-list a:visible"
    ];
    for (const selector of docsPrimarySelectors) {
      const element = page.locator(selector).first();
      await expect(element, selector).toBeVisible();
      await expect(element, selector).toHaveCSS("color", result.ink);
    }
  }

  await page.emulateMedia({ colorScheme: "light", forcedColors: "active" });
  await page.goto(site("minimal", "/blog/"));
  const forcedContrast = await page.evaluate(() => {
    const swatch = document.querySelector<HTMLElement>(".tag-filter__list .context-tag__name")!;
    const background = document.body;
    const toChannels = (value: string): [number, number, number] => {
      const channels = value.match(/[\d.]+/g)?.slice(0, 3).map(Number);
      if (!channels || channels.length !== 3) throw new Error(`Expected an RGB color, got ${value}`);
      return channels as [number, number, number];
    };
    const luminance = (value: string) => {
      const linear = (channel: number) => {
        const normalized = channel / 255;
        return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
      };
      const [red, green, blue] = toChannels(value);
      return (0.2126 * linear(red)) + (0.7152 * linear(green)) + (0.0722 * linear(blue));
    };
    const foreground = luminance(getComputedStyle(swatch).color);
    const surface = luminance(getComputedStyle(background).backgroundColor);
    return (Math.max(foreground, surface) + 0.05) / (Math.min(foreground, surface) + 0.05);
  });
  expect(forcedContrast).toBeGreaterThanOrEqual(7);
});

test("Minimal reveals page and chronology scrollbars only during interaction", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop scrollbar contract");
  await page.setViewportSize({ width: 1190, height: 260 });
  await page.goto(site("minimal", "/blog/"));

  const root = page.locator("html");
  await expect(root).not.toHaveAttribute("data-scrollbar-active", "true");
  const idleRootColor = await root.evaluate((element) => getComputedStyle(element).scrollbarColor);
  await page.evaluate(() => window.scrollTo(0, 120));
  await expect(root).toHaveAttribute("data-scrollbar-active", "true");
  expect(await root.evaluate((element) => getComputedStyle(element).scrollbarColor)).not.toBe(idleRootColor);
  await expect(root).not.toHaveAttribute("data-scrollbar-active", "true");

  const chronology = page.locator(".archive-context");
  await chronology.evaluate((element) => { element.style.maxBlockSize = "80px"; });
  await expect(chronology).not.toHaveAttribute("data-scrollbar-active", "true");
  expect(await chronology.evaluate((element) => element.scrollHeight > element.clientHeight)).toBe(true);
  const idleChronologyColor = await chronology.evaluate((element) => getComputedStyle(element).scrollbarColor);
  await chronology.hover();
  await expect(chronology).toHaveAttribute("data-scrollbar-active", "true");
  await expect(chronology).not.toHaveAttribute("data-scrollbar-active", "true");
  expect(await chronology.evaluate((element) => getComputedStyle(element).scrollbarColor))
    .toBe(idleChronologyColor);
  await chronology.locator("[data-year-filter-option]").first().focus();
  await expect(chronology).toHaveAttribute("data-scrollbar-active", "true");
  await expect(chronology).not.toHaveAttribute("data-scrollbar-active", "true");
  expect(await chronology.evaluate((element) => getComputedStyle(element).scrollbarColor))
    .toBe(idleChronologyColor);
  await chronology.evaluate((element) => { element.scrollTop = 80; });
  await expect(chronology).toHaveAttribute("data-scrollbar-active", "true");
  expect(await chronology.evaluate((element) => getComputedStyle(element).scrollbarColor))
    .not.toBe(idleChronologyColor);
  await expect(chronology).not.toHaveAttribute("data-scrollbar-active", "true");
});

test("legacy Archive, paginated Home, and Notes routes are absent", async ({ page }) => {
  for (const route of ["/archive/", "/page/2/", "/notes/"] as const) {
    const response = await page.goto(site("minimal", route));
    expect(response?.status(), route).toBe(404);
    await expect(page.locator("body")).toHaveText("Not found");
  }
});

test("short Blog pages keep the footer at the viewport edge", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop footer geometry assertion");
  await page.goto(site("minimal", "/blog/"));
  const geometry = await page.locator(".site-footer").evaluate((footer) => ({
    bottom: footer.getBoundingClientRect().bottom,
    viewport: window.innerHeight
  }));
  expect(Math.abs(geometry.bottom - geometry.viewport)).toBeLessThanOrEqual(1);
});

for (const theme of themes) {
  test(`${theme} documentation navigation preserves its shell`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop documentation navigation assertion");
    await page.goto(site(theme, "/docs/Getting%20Started/"));

    const header = page.locator(".site-header");
    const sidebar = page.locator(theme === "minimal" ? ".minimal-docs-sidebar" : ".docs-sidebar");
    await header.evaluate((element) => element.setAttribute("data-shell-instance", "header"));
    await sidebar.evaluate((element) => element.setAttribute("data-shell-instance", "sidebar"));

    const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
    await expect(navigation).toHaveAttribute("data-docs-navigation-ready", "true");
    await navigation.getByRole("link", { name: "Syntax" }).click();
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
    await expect(page.getByRole("heading", { level: 1, name: "Syntax" })).toBeVisible();
    await expect(header).toHaveAttribute("data-shell-instance", "header");
    await expect(sidebar).toHaveAttribute("data-shell-instance", "sidebar");
    await expect(page.locator("[data-context-panel] [data-graph-view]")).toHaveAttribute("data-graph-ready", "true");

    await page.goBack();
    await expect(page).toHaveURL(site(theme, "/docs/Getting%20Started/"));
    await expect(header).toHaveAttribute("data-shell-instance", "header");
    await expect(sidebar).toHaveAttribute("data-shell-instance", "sidebar");
  });

  test(`${theme} documentation fragments preserve the page shell through history`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop documentation fragment assertion");
    await page.goto(site(theme, "/docs/Getting%20Started/"));

    const header = page.locator(".site-header");
    const sidebar = page.locator(theme === "minimal" ? ".minimal-docs-sidebar" : ".docs-sidebar");
    await header.evaluate((element) => element.setAttribute("data-shell-instance", "header"));
    await sidebar.evaluate((element) => element.setAttribute("data-shell-instance", "sidebar"));

    await page.getByRole("navigation", { name: "Documentation", exact: true })
      .getByRole("link", { name: "Syntax" }).click();
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
    await expect(page.getByRole("heading", { level: 1, name: "Syntax" })).toBeVisible();
    const main = page.locator("[data-docs-main]");
    await main.evaluate((element) => element.setAttribute("data-page-instance", "syntax"));

    const fragment = page.locator("[data-page-context]")
      .getByRole("link", { name: "Tags and comments" });
    await fragment.click();
    await expect(page).toHaveURL(`${site(theme, "/docs/Syntax/")}#tags-and-comments`);
    await page.waitForLoadState("networkidle");
    await expect(page.locator("#tags-and-comments")).toBeInViewport();
    await expect(main).toHaveAttribute("data-page-instance", "syntax");

    await page.goBack();
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
    await page.waitForLoadState("networkidle");
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeLessThanOrEqual(1);
    await expect(main).toHaveAttribute("data-page-instance", "syntax");

    await page.goForward();
    await expect(page).toHaveURL(`${site(theme, "/docs/Syntax/")}#tags-and-comments`);
    await page.waitForLoadState("networkidle");
    await expect(page.locator("#tags-and-comments")).toBeInViewport();
    await expect(header).toHaveAttribute("data-shell-instance", "header");
    await expect(sidebar).toHaveAttribute("data-shell-instance", "sidebar");
  });
}

test("Minimal Docs keeps its three-column context and active top-level scope", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop Minimal Docs assertion");
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await expect(page.locator(".minimal-docs-sidebar")).toBeVisible();
  await expect(page.locator(".minimal-reading-column")).toBeVisible();
  await expect(page.locator(".minimal-context")).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Primary navigation" })
    .getByRole("link", { name: "Docs" })).toHaveAttribute("aria-current", "page");
  await expect(page.getByRole("navigation", { name: "Documentation sequence" })).toContainText("Syntax");
});

test("documentation sidebars expose the complete index by default", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop documentation index assertion");
  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
    const topLevel = navigation.locator(":scope > .docs-tree__list > .docs-tree__item");
    await expect(topLevel.first().locator(":scope > a")).toHaveText("Getting Started");
    await expect(navigation.getByText("Documentation", { exact: true })).toHaveCount(0);
    await expect(navigation.getByRole("link", { name: "Architecture" })).toBeVisible();
    await expect(page.getByRole("link", { name: "View full documentation index" })).toHaveCount(0);
  }
});

test("Minimal Docs puts primary and documentation navigation into the mobile Browse sheet", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile Browse assertion");
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await expect(page.locator(".minimal-docs-sidebar")).toBeHidden();
  await expect(page.locator(".minimal-context")).toBeHidden();
  await page.getByRole("button", { name: "Browse" }).tap();
  const dialog = page.locator('dialog[data-dialog="browse"]');
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("navigation", { name: "Primary navigation" }).getByRole("link"))
    .toHaveText(["Home", "Blog", "Docs", "Portfolio"]);
  await expect(dialog.getByRole("navigation", { name: "Documentation" })
    .getByRole("link", { name: "Syntax" })).toBeVisible();
});

test("Minimal mobile Browse documentation links preserve the shell", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile Browse navigation assertion");
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  const header = page.locator(".site-header");
  await header.evaluate((element) => element.setAttribute("data-shell-instance", "header"));

  await page.getByRole("button", { name: "Browse" }).tap();
  const dialog = page.locator('dialog[data-dialog="browse"]');
  await dialog.getByRole("navigation", { name: "Documentation" })
    .getByRole("link", { name: "Syntax" }).tap();

  await expect(page).toHaveURL(site("minimal", "/docs/Syntax/"));
  await expect(page.getByRole("heading", { level: 1, name: "Syntax" })).toBeVisible();
  await expect(header).toHaveAttribute("data-shell-instance", "header");
});

test("priority navigation folds custom tabs into an accessible More menu", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop priority navigation assertion");
  await page.goto("/__fixture__/features/minimal/navigation/");
  const navigation = page.getByRole("navigation", { name: "Primary navigation" });
  await expect(navigation).toHaveAttribute("data-priority-navigation-ready", "true");
  await navigation.evaluate((element) => {
    element.style.flex = "0 0 230px";
    element.style.inlineSize = "230px";
    element.style.maxInlineSize = "230px";
  });

  const more = navigation.locator("[data-priority-navigation-more]");
  await expect(more).toBeVisible();
  await expect(more).toHaveAttribute("data-has-current", "true");
  const primaryIds = await navigation.locator("[data-priority-navigation-list] > li")
    .evaluateAll((items) => items.map((item) => item.getAttribute("data-navigation-id")));
  const overflowIds = await navigation.locator("[data-priority-navigation-overflow] > li")
    .evaluateAll((items) => items.map((item) => item.getAttribute("data-navigation-id")));
  expect([...primaryIds, ...overflowIds]).toEqual([
    "home", "blog", "docs", "page:about.md", "portfolio", "page:projects.md", "folder:team", "page:contact.md"
  ]);

  const summary = more.locator("summary");
  await summary.focus();
  await page.keyboard.press("Enter");
  await expect(more).toHaveAttribute("open", "");
  await expect(more.getByRole("link", { name: "Projects" })).toHaveAttribute("aria-current", "page");
  await page.keyboard.press("Tab");
  await expect(more.locator("[data-priority-navigation-overflow] a").first()).toBeFocused();
  await page.getByRole("heading", { name: "Independent context" }).click();
  await expect(more).not.toHaveAttribute("open", "");

  await navigation.evaluate((element) => {
    element.style.flexBasis = "900px";
    element.style.inlineSize = "900px";
    element.style.maxInlineSize = "900px";
  });
  await expect(more).toBeHidden();
  await expect(navigation.locator("[data-priority-navigation-list] > li")).toHaveCount(8);
});

test("mobile Browse preserves all configured tabs and their active state", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile custom navigation assertion");
  await page.goto("/__fixture__/features/minimal/navigation/");
  await page.getByRole("button", { name: "Browse" }).tap();
  const navigation = page.locator('dialog[data-dialog="browse"]')
    .getByRole("navigation", { name: "Primary navigation" });
  await expect(navigation.getByRole("link")).toHaveText([
    "Home", "Blog", "Docs", "About", "Portfolio", "Projects", "Team", "Contact"
  ]);
  await expect(navigation.getByRole("link", { name: "Projects" })).toHaveAttribute("aria-current", "page");
});

test("search loads on demand and finds CJK content", async ({ page }) => {
  await page.goto(site("minimal"));
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await expect(dialog).toBeVisible();
  await expect(dialog).toHaveAttribute("data-search-ready", "true");
  const headerNavigation = page.locator(".site-header [data-priority-navigation-item]");
  const searchNavigation = dialog.locator("[data-search-navigation] [data-navigation-id]");
  await expect(searchNavigation).toHaveCount(await headerNavigation.count());
  await expect(searchNavigation.locator("a")).toHaveText(await headerNavigation.locator("a").allTextContents());
  await dialog.locator("input").fill("Docs");
  expect(await searchNavigation.filter({ hasNotText: "Docs" }).evaluateAll((items) =>
    items.every((item) => (item as HTMLElement).hidden)
  )).toBe(true);
  await expect(searchNavigation.filter({ hasText: "Docs" })).toBeVisible();
  await dialog.locator("input").fill("CJK");
  await expect(dialog.locator("[data-search-navigation]")).toBeHidden();
  await expect(dialog.getByRole("link", { name: "CJK Showcase" })).toBeVisible();
});

test("search input focus does not add a focus frame", async ({ page }) => {
  await page.goto(site("docs"));
  await page.keyboard.press("ControlOrMeta+k");
  const box = page.locator(".search-box");
  const input = box.locator("[data-search-input]");
  await input.evaluate((element) => element.blur());
  const quietBorder = await box.evaluate((element) => getComputedStyle(element).borderTopColor);
  await input.focus();
  await expect(box).toHaveCSS("border-top-color", quietBorder);
  await expect(box).toHaveCSS("box-shadow", "none");
  await expect(input).toHaveCSS("outline-style", "none");
  await expect(input).toHaveCSS("box-shadow", "none");
});

test("Minimal previews use catalog text without injecting active content", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop preview assertion");
  await page.goto(site("minimal"));
  await page.locator(".website-link[data-note-id='docs/中文示例.md']").focus();
  const preview = page.locator("[data-note-preview]");
  await expect(preview).toContainText("CJK Showcase");
  await expect(preview.locator(".note-preview__title-link")).toHaveAttribute("href", /\/docs\/%E4%B8%AD%E6%96%87%E7%A4%BA%E4%BE%8B\/$/);
  expect((await preview.locator(".note-preview__body").boundingBox())!.height).toBeLessThanOrEqual(240);
  await expect(preview.locator(".note-preview__body")).toHaveAttribute("data-preview-body-ready", "true");
  await expect(preview).toContainText("中文、日文和拉丁字母可以写在同一个知识库里");
  await expect(preview.locator("iframe, script")).toHaveCount(0);
});

test("every theme places the local graph first in documentation context", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph context assertion");
  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    const context = page.locator("[data-context-panel]");
    await expect(context).toBeVisible();
    await expect(context.locator(":scope > .local-graph")).toHaveCount(1);
    await expect(context.locator(":scope > section").first()).toHaveClass(/local-graph/);
    await expect(context.getByRole("button", { name: "Open full graph" })).toBeVisible();
    await expect(context.getByRole("button", { name: "Expand local graph" })).toBeVisible();
    await expect(context.locator("[data-graph-view]")).toHaveAttribute("data-graph-ready", "true");
  }
});

test("compact Portfolio graphs keep node labels clear of their live status", async ({ page }, testInfo) => {
  if (testInfo.project.name === "mobile-chromium") {
    await page.setViewportSize({ width: 320, height: 900 });
  }
  await page.goto(site("minimal", "/portfolio/jekyll-obsidian/"));

  let view = page.locator("[data-context-panel] [data-graph-view]");
  if (testInfo.project.name === "mobile-chromium") {
    await page.getByRole("button", { name: "Context" }).tap();
    view = page.locator('dialog[data-dialog="context"] [data-graph-view]');
  }
  await expect(view).toBeVisible();
  await expect(view).toHaveAttribute("data-graph-ready", "true");

  const assertLabelsClearStatus = async () => {
    await page.waitForTimeout(400);
    const geometry = await view.evaluate((container) => {
      const status = container.querySelector<HTMLElement>("[data-graph-status]");
      const labels = [...container.querySelectorAll<SVGTextElement>(".graph-node text")];
      const canvas = container.querySelector<HTMLElement>("[data-graph-canvas]");
      const svg = canvas?.querySelector<SVGSVGElement>("svg");
      if (!status || !canvas || !svg) {
        return { labelCount: labels.length, overlaps: ["missing graph surface"], surface: null };
      }
      const statusRect = status.getBoundingClientRect();
      const canvasRect = canvas.getBoundingClientRect();
      const overlaps = labels.filter((label) => {
        const labelRect = label.getBoundingClientRect();
        return labelRect.left < statusRect.right && labelRect.right > statusRect.left &&
          labelRect.top < statusRect.bottom && labelRect.bottom > statusRect.top;
      }).map((label) => label.textContent || "untitled node");
      const clipped = labels.filter((label) => {
        const labelRect = label.getBoundingClientRect();
        return labelRect.left < canvasRect.left || labelRect.right > canvasRect.right ||
          labelRect.top < canvasRect.top || labelRect.bottom > canvasRect.bottom;
      }).map((label) => label.textContent || "untitled node");
      return {
        labelCount: labels.length,
        overlaps,
        clipped,
        neighbourAnchors: labels.filter((label) =>
          !label.closest(".graph-node")?.classList.contains("graph-node--current")
        ).map((label) => label.getAttribute("text-anchor")),
        surface: {
          canvasWidth: canvas.clientWidth,
          canvasHeight: canvas.clientHeight,
          viewBoxWidth: svg.viewBox.baseVal.width,
          viewBoxHeight: svg.viewBox.baseVal.height
        }
      };
    });
    expect(geometry.labelCount).toBe(3);
    expect(geometry.overlaps).toEqual([]);
    expect(geometry.clipped).toEqual([]);
    expect(geometry.neighbourAnchors).toEqual(["middle", "middle"]);
    expect(geometry.surface).not.toBeNull();
    expect(geometry.surface!.viewBoxWidth).toBeCloseTo(geometry.surface!.canvasWidth, 0);
    expect(geometry.surface!.viewBoxHeight).toBeCloseTo(geometry.surface!.canvasHeight, 0);
  };

  await assertLabelsClearStatus();
  await page.locator("html").evaluate((root) => { root.setAttribute("dir", "rtl"); });
  await assertLabelsClearStatus();

  if (testInfo.project.name === "desktop-chromium") {
    await page.getByRole("button", { name: "Expand local graph" }).click();
    const expanded = page.locator('dialog[data-dialog="graph-local"] [data-graph-dialog-view="local"]');
    await expect(expanded).toHaveAttribute("data-graph-ready", "true");
    await expect(expanded.locator(".graph-node")).toHaveCount(3);
    expect((await expanded.boundingBox())!.height).toBeGreaterThanOrEqual(480);
  }
});

test("desktop compact graphs keep every visible label separate and inside the canvas", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop compact graph assertion");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await page.evaluate(() => document.fonts.ready);

  const view = page.locator("[data-context-panel] [data-graph-view]");
  await expect(view).toBeVisible();
  await expect(view).toHaveAttribute("data-graph-ready", "true");

  for (const direction of ["ltr", "rtl"] as const) {
    await page.locator("html").evaluate((root, value) => { root.setAttribute("dir", value); }, direction);
    const geometry = await view.evaluate((container) => {
      const canvas = container.querySelector<HTMLElement>("[data-graph-canvas]");
      const status = container.querySelector<HTMLElement>("[data-graph-status]");
      const labels = [...container.querySelectorAll<SVGTextElement>(".graph-node text")];
      if (!canvas || !status) {
        return { labelCount: labels.length, clipped: ["missing graph surface"], intersections: [], statusIntersections: [] };
      }

      const canvasRect = canvas.getBoundingClientRect();
      const statusRect = status.getBoundingClientRect();
      const rectangles = labels.map((label) => ({
        title: label.textContent || "untitled node",
        rect: label.getBoundingClientRect()
      }));
      const intersects = (left: DOMRect, right: DOMRect) =>
        left.left < right.right && left.right > right.left &&
        left.top < right.bottom && left.bottom > right.top;
      const intersections: string[] = [];
      for (let left = 0; left < rectangles.length; left += 1) {
        for (let right = left + 1; right < rectangles.length; right += 1) {
          const leftLabel = rectangles[left]!;
          const rightLabel = rectangles[right]!;
          if (intersects(leftLabel.rect, rightLabel.rect)) {
            intersections.push(`${leftLabel.title} / ${rightLabel.title}`);
          }
        }
      }

      return {
        labelCount: labels.length,
        clipped: rectangles.filter(({ rect }) =>
          rect.left < canvasRect.left || rect.right > canvasRect.right ||
          rect.top < canvasRect.top || rect.bottom > canvasRect.bottom
        ).map(({ title }) => title),
        intersections,
        statusIntersections: rectangles.filter(({ rect }) => intersects(rect, statusRect)).map(({ title }) => title)
      };
    });

    expect(geometry.labelCount).toBe(10);
    expect(geometry.clipped, direction).toEqual([]);
    expect(geometry.intersections, direction).toEqual([]);
    expect(geometry.statusIntersections, direction).toEqual([]);
  }
});

test("expanded and complete graphs keep dragged node labels inside the canvas", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph edge assertion");
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto(site("minimal", "/docs/Getting%20Started/"));

  const context = page.locator("[data-context-panel]");
  const cases = [
    {
      open: "Expand local graph",
      dialog: 'dialog[data-dialog="graph-local"]',
      view: '[data-graph-dialog-view="local"]',
      close: "Close local graph"
    },
    {
      open: "Open full graph",
      dialog: 'dialog[data-dialog="graph-global"]',
      view: '[data-graph-dialog-view="global"]',
      close: "Close full graph"
    }
  ] as const;

  for (const graphCase of cases) {
    await context.getByRole("button", { name: graphCase.open }).click();
    const dialog = page.locator(graphCase.dialog);
    const view = dialog.locator(graphCase.view);
    await expect(dialog).toBeVisible();
    await expect(view).toHaveAttribute("data-graph-ready", "true");

    const node = view.locator(".graph-node[role='link']").first();
    const circle = node.locator("circle");
    const canvas = view.locator("[data-graph-canvas]");
    const circleBox = (await circle.boundingBox())!;
    const canvasBox = (await canvas.boundingBox())!;
    await page.mouse.move(circleBox.x + circleBox.width / 2, circleBox.y + circleBox.height / 2);
    await page.mouse.down();
    await page.mouse.move(canvasBox.x + canvasBox.width - 20, circleBox.y + circleBox.height / 2, { steps: 5 });
    await page.mouse.up();

    const geometry = await node.evaluate((element) => {
      const label = element.querySelector<SVGTextElement>("text")!;
      const circle = element.querySelector<SVGCircleElement>("circle")!;
      const canvas = element.closest("[data-graph-canvas]")!;
      const labelRect = label.getBoundingClientRect();
      const circleRect = circle.getBoundingClientRect();
      const canvasRect = canvas.getBoundingClientRect();
      return {
        circleEndGap: canvasRect.right - circleRect.right,
        labelClipped: labelRect.left < canvasRect.left || labelRect.right > canvasRect.right ||
          labelRect.top < canvasRect.top || labelRect.bottom > canvasRect.bottom
      };
    });
    expect(geometry.circleEndGap, graphCase.open).toBeLessThan(32);
    expect(geometry.labelClipped, graphCase.open).toBe(false);

    await dialog.getByRole("button", { name: graphCase.close }).click();
  }
});

test("graph dialogs cache the complete graph and dispose expanded local graphs", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph dialog assertion");
  let graphRequests = 0;
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.endsWith("/assets/website/graph.v1.json")) graphRequests += 1;
  });
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  const context = page.locator("[data-context-panel]");
  await context.getByRole("button", { name: "Open full graph" }).click();
  const full = page.locator('dialog[data-dialog="graph-global"]');
  await expect(full.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  await full.getByRole("button", { name: "Close full graph" }).click();
  await context.getByRole("button", { name: "Open full graph" }).click();
  await expect(full.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-ready", "true");
  expect(graphRequests).toBe(1);
  await full.getByRole("button", { name: "Close full graph" }).click();

  await context.getByRole("button", { name: "Expand local graph" }).click();
  const local = page.locator('dialog[data-dialog="graph-local"]');
  await expect(local.locator(".graph-node")).not.toHaveCount(0);
  await local.getByRole("button", { name: "Close local graph" }).click();
  await expect(local.locator("[data-graph-dialog-view]")).toHaveAttribute("data-graph-disposed", "true");
});

test("graph nodes have no frame and darken only on interaction", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop graph interaction assertion");
  await page.goto(site("docs", "/docs/Syntax/"));
  const view = page.locator("[data-context-panel] [data-graph-view]");
  await expect(view).toHaveAttribute("data-graph-ready", "true");
  const currentCircle = view.locator(".graph-node--current circle");
  const target = view.locator(".graph-node[role='link']").first();
  const targetCircle = target.locator("circle");
  await expect(targetCircle).toHaveCSS("stroke", "none");
  const quiet = await targetCircle.evaluate((element) => getComputedStyle(element).fill);
  expect(await currentCircle.evaluate((element) => getComputedStyle(element).fill)).toBe(quiet);
  await target.hover();
  await expect.poll(() => targetCircle.evaluate((element) => getComputedStyle(element).fill)).not.toBe(quiet);
  await page.mouse.move(0, 0);
  await target.focus();
  await expect.poll(() => targetCircle.evaluate((element) => getComputedStyle(element).fill)).not.toBe(quiet);
});

test("Analytics initializes each provider once across Docs history events", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one browser lifecycle contract is sufficient");
  const requests = { cloudflare: 0, google: 0 };
  await page.route("https://static.cloudflareinsights.com/beacon.min.js", async (route) => {
    requests.cloudflare += 1;
    await route.fulfill({ contentType: "text/javascript", body: "" });
  });
  await page.route(/https:\/\/www\.googletagmanager\.com\/gtag\/js\?.*/, async (route) => {
    requests.google += 1;
    await route.fulfill({ contentType: "text/javascript", body: "" });
  });

  for (const provider of ["cloudflare", "google"] as const) {
    await page.goto(`/__fixture__/analytics/${provider}/`);
    const script = page.locator(`script[data-website-analytics="${provider}"]`);
    await expect(script).toHaveCount(1);
    await expect.poll(() => requests[provider]).toBe(1);

    await page.evaluate(() => {
      history.pushState({}, "", `${location.pathname}?view=next`);
      document.dispatchEvent(new CustomEvent("website:docs-page-change"));
      dispatchEvent(new PopStateEvent("popstate"));
      location.hash = "fragment-only";
    });

    await expect(script).toHaveCount(1);
    expect(requests[provider]).toBe(1);
  }
});

test("A blocked analytics client does not interrupt site interaction", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one blocked-client contract is sufficient");
  await page.route("https://static.cloudflareinsights.com/beacon.min.js", (route) => route.abort());
  await page.setViewportSize({ width: 390, height: 760 });
  await page.goto("/__fixture__/analytics/cloudflare/");

  await expect(page.locator('script[data-website-analytics="cloudflare"]')).toHaveCount(1);
  await page.locator('button[data-dialog-open="browse"]').click();
  await expect(page.locator('dialog[data-dialog="browse"]')).toBeVisible();
});

test("Comments use the managed Giscus client and remain narrow-layout safe", async ({ page }) => {
  let requestedClient = false;
  await page.addInitScript(() => localStorage.setItem("website:color-scheme", "dark"));
  await page.route("https://giscus.app/client.js", async (route) => {
    requestedClient = true;
    await route.fulfill({ contentType: "text/javascript", body: "" });
  });
  await page.setViewportSize({ width: 320, height: 760 });
  await page.goto("/__fixture__/comments/");
  const comments = page.getByRole("region", { name: "Comments" });
  await expect(comments).toBeVisible();
  await expect(comments.getByText("Discussion", { exact: true })).toHaveCount(0);
  const heading = comments.getByRole("heading", { name: "Comments" });
  expect((await heading.boundingBox())!.x).toBeCloseTo((await comments.boundingBox())!.x, 0);
  expect(await heading.evaluate((element) => Number.parseFloat(getComputedStyle(element).fontSize)))
    .toBeLessThanOrEqual(28);
  await expect.poll(() => requestedClient).toBe(true);
  const client = comments.locator("script[data-website-comments-client]");
  await expect(client).toHaveAttribute("data-mapping", "specific");
  await expect(client).toHaveAttribute("data-strict", "1");
  await expect(client).toHaveAttribute("data-theme", "dark");
  expect(await comments.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
  const results = await new AxeBuilder({ page }).include(".website-comments").analyze();
  expect(results.violations).toEqual([]);
});

test("Comments retain their GitHub fallback when Giscus is unavailable", async ({ page }) => {
  await page.route("https://giscus.app/client.js", (route) => route.abort());
  await page.goto("/__fixture__/comments/");
  const comments = page.getByRole("region", { name: "Comments" });
  await expect(comments).toHaveAttribute("data-website-comments-state", "unavailable");
  await expect(comments.getByText("Comments could not be loaded.")).toBeVisible();
  await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
});

test("Minimal articles use centered Previous and Next cards", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop sequence geometry assertion");
  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  const previous = page.locator(".sequence-navigation a[rel='prev']");
  await expect(previous.locator("span")).toHaveText("Previous");
  await expect(previous).toHaveCSS("text-align", "center");
  await expect(previous).toHaveCSS("border-top-width", "1px");
  await page.goto(site("minimal", "/blog/%E4%BB%8E%E7%AC%94%E8%AE%B0%E5%88%B0%E5%8F%91%E5%B8%83/"));
  const next = page.locator(".sequence-navigation a[rel='next']");
  await expect(next.locator("span")).toHaveText("Next");
  await expect(next).toHaveCSS("text-align", "center");
  await expect(next).toHaveCSS("grid-column-start", "2");
});

test("themes follow system dark mode and support explicit light override", async ({ page }) => {
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(() => localStorage.removeItem("website:color-scheme"));
  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "dark");
    await page.locator("[data-color-scheme-toggle]").click();
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
  }
});

test("saved light preference is applied before the deferred theme bundle", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "first-paint timing assertion");
  await page.emulateMedia({ colorScheme: "dark" });
  await page.addInitScript(() => localStorage.setItem("website:color-scheme", "light"));
  await page.route(/\/(?:minimal|docs)-[A-Z0-9]+\.js(?:\?.*)?$/, (route) => route.abort());
  for (const theme of themes) {
    await page.goto(site(theme), { waitUntil: "domcontentloaded" });
    await expect(page.locator("html")).toHaveAttribute("data-color-scheme", "light");
    expect(await page.locator("head").evaluate((head) => {
      const children = [...head.children];
      const bootstrap = children.findIndex((element) =>
        element instanceof HTMLScriptElement && element.src.includes("color-scheme-bootstrap-")
      );
      const stylesheet = children.findIndex((element) =>
        element instanceof HTMLLinkElement && element.rel === "stylesheet"
      );
      return bootstrap >= 0 && stylesheet >= 0 && bootstrap < stylesheet;
    })).toBe(true);
  }
});

test("themes use neutral dark surfaces, warm paper light, and one restrained type scale", async ({ page }) => {
  for (const theme of themes) {
    await page.emulateMedia({ colorScheme: "dark" });
    await page.addInitScript(() => localStorage.removeItem("website:color-scheme"));
    await page.goto(site(theme, "/docs/Getting%20Started/"));
    for (const selector of ["body", "pre"] as const) {
      const channels = await page.locator(selector).first().evaluate((element) =>
        getComputedStyle(element).backgroundColor.match(/\d+/g)?.slice(0, 3).map(Number) || []
      );
      expect(Math.max(...channels) - Math.min(...channels), `${theme} ${selector}`).toBeLessThanOrEqual(4);
    }

    await page.emulateMedia({ colorScheme: "light" });
    await page.evaluate(() => localStorage.setItem("website:color-scheme", "light"));
    await page.reload();
    const paper = await page.locator("body").evaluate((element) =>
      getComputedStyle(element).backgroundColor.match(/\d+/g)?.slice(0, 3).map(Number) || []
    );
    expect(paper[0]!, theme).toBeGreaterThan(paper[2]!);

    const title = page.getByRole("heading", { level: 1, name: "Getting Started" });
    const section = page.getByRole("heading", { level: 2, name: "Publish through GitHub Actions" });
    const paragraph = page.locator(".note-content > p").first();
    const typography = (locator: typeof title) => locator.evaluate((element) => {
      const style = getComputedStyle(element);
      return { family: style.fontFamily, size: Number.parseFloat(style.fontSize) };
    });
    const [titleType, sectionType, bodyType] = await Promise.all([
      typography(title), typography(section), typography(paragraph)
    ]);
    expect(titleType.family).toBe(bodyType.family);
    expect(sectionType.family).toBe(bodyType.family);
    expect(bodyType.family).toContain("Segoe UI");
    expect(titleType.size / bodyType.size).toBeLessThan(3);
    expect(sectionType.size / bodyType.size).toBeLessThan(2);
  }
});

test("Minimal omits decorative reading chrome", async ({ page }) => {
  await page.goto(site("minimal", "/docs/Getting%20Started/"));
  await expect(page.locator(".note-kicker, .breadcrumbs")).toHaveCount(0);
  await expect(page.locator(".note-header")).toHaveCSS("border-bottom-width", "0px");
  await expect(page.locator(".site-header")).toHaveCSS("border-top-width", "0px");
  const section = page.getByRole("heading", { level: 2, name: "Publish through GitHub Actions" });
  expect(await section.evaluate((element) => getComputedStyle(element, "::before").content)).toBe("none");
});

test("feed discovery stays out of primary navigation", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop navigation assertion");
  for (const theme of themes) {
    await page.goto(`/__fixture__/features/${theme}/navigation/`);
    const primary = page.getByRole("navigation", { name: "Primary navigation" });
    await expect(primary.locator('a[href="/tags/"], a[href="/feed.xml"], a[href="/graph/"]')).toHaveCount(0);
    await expect(page.locator('head link[rel="alternate"][type="application/atom+xml"]'))
      .toHaveAttribute("href", "/feed.xml");
  }

  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  const primary = page.getByRole("navigation", { name: "Primary navigation" });
  await expect(primary.getByRole("link", { name: /^(Feed|Topics|Tags)$/ })).toHaveCount(0);
  await expect(page.locator('head link[rel="alternate"][type="application/atom+xml"]'))
    .toHaveAttribute("href", /\/__site__\/minimal\/feed\.xml$/);
});

test("localized docs language navigation and fallback metadata remain correct", async ({ page }) => {
  await page.goto(localizedDocs());
  await expect(page.locator(".minimal-contacts, a[href='https://github.com/wowfun'], a[href='https://x.com/wowfuna']"))
    .toHaveCount(0);

  await page.goto(localizedDocs("/zh-CN/"));
  await expect(page.locator("main")).toContainText("把 Markdown 文件夹直接变成完整的博客或文档站。");
  await expect(page.locator("main")).toContainText("无需在本地运行构建命令");

  await page.goto(localizedDocs("/zh-CN/docs/Getting%20Started/"));
  await expect(page.locator(".site-mark__name")).toHaveText("Browser i18n fixture");
  await expect(page.locator("html")).toHaveAttribute("lang", "zh-CN");
  const switcher = page.locator("[data-language-switcher]");
  await switcher.locator("summary").click();
  await expect(switcher.getByRole("link", { name: "简体中文" })).toHaveAttribute("aria-current", "page");
  await expect(switcher.getByRole("link", { name: "English" }))
    .toHaveAttribute("href", localizedDocs("/docs/Getting%20Started/"));
  await switcher.getByRole("link", { name: "English" }).focus();
  await page.keyboard.press("Escape");
  await expect(switcher.locator("summary")).toBeFocused();

  await page.goto(localizedDocs("/zh-CN/docs/Customization/"));
  await expect(page.getByRole("heading", { level: 1, name: "自定义" })).toBeVisible();
  await expect(page.locator(".translation-fallback")).toHaveCount(0);
  const related = page.getByRole("navigation", { name: "相关文章" });
  await expect(related.locator("article.minimal-post-card")).toHaveCount(2);
  await expect(related.getByRole("link", { name: "语法", exact: true }))
    .toHaveAttribute("href", localizedDocs("/zh-CN/docs/Syntax/"));
  await expect(related.getByRole("link", { name: "本地化", exact: true }))
    .toHaveAttribute("href", localizedDocs("/zh-CN/docs/Localization/"));

  await page.goto(localizedDocs("/zh-CN/portfolio/jekyll-obsidian/"));
  await expect(page.getByRole("heading", { level: 1, name: "导入的 Jekyll Obsidian" })).toBeVisible();
  await expect(page.getByRole("link", { name: "查看导入的 Markdown" })).toHaveAttribute(
    "href",
    "https://github.com/wowfun/jekyll-obsidian/blob/0123456789abcdef0123456789abcdef01234567/README.zh-CN.md"
  );
  await expect(page.getByRole("link", { name: "在 GitHub 上打开 Jekyll Obsidian" }))
    .toHaveAttribute("href", "https://github.com/wowfun/jekyll-obsidian");

  await page.goto(localizedDocs("/zh-CN/docs/Architecture/"));
  await expect(page.locator(".translation-fallback")).toContainText("本页尚无译文");
  await expect(page.locator(".note-content")).toHaveAttribute("lang", "en");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex");
  await expect(page.locator('link[rel="alternate"][hreflang]')).toHaveCount(0);
});

test("authored related pages reuse accessible Recent-post cards at the page bottom", async ({ page }, testInfo) => {
  if (testInfo.project.name === "mobile-chromium") {
    await page.setViewportSize({ width: 320, height: 900 });
  }

  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Customization/"));
    const related = page.getByRole("navigation", { name: "Related articles" });
    const cards = related.locator("article.minimal-post-card");
    await expect(cards).toHaveCount(2);
    await expect(related.getByRole("heading", { level: 2, name: "Related articles" })).toBeVisible();
    await expect(related.getByRole("link", { name: "Syntax", exact: true }))
      .toHaveAttribute("href", site(theme, "/docs/Syntax/"));
    await expect(related.getByRole("link", { name: "Localization", exact: true }))
      .toHaveAttribute("href", site(theme, "/docs/Localization/"));
    await expect(cards.first().locator(".minimal-post-card__excerpt"))
      .toContainText("OFM v1 authoring surface");

    const sourceActions = page.getByRole("navigation", { name: "Contribute to this page" });
    expect(await sourceActions.evaluate((actions) => {
      const navigation = document.querySelector(".related-articles");
      return Boolean(navigation &&
        (actions.compareDocumentPosition(navigation) & Node.DOCUMENT_POSITION_FOLLOWING));
    })).toBe(true);
    const sourceActionsBox = (await sourceActions.boundingBox())!;
    const relatedBox = (await related.boundingBox())!;
    expect(relatedBox.x).toBeCloseTo(sourceActionsBox.x, 0);
    expect(relatedBox.width).toBeCloseTo(sourceActionsBox.width, 0);

    const gridColumns = await related.locator(".minimal-recent__grid").evaluate((element) =>
      getComputedStyle(element).gridTemplateColumns.split(" ").filter(Boolean).length
    );
    expect(gridColumns).toBe(1);
    expect(await related.evaluate((element) => element.scrollWidth <= element.clientWidth)).toBe(true);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth))
      .toBe(true);

    const firstCardBody = cards.first().locator(".minimal-post-card__body");
    await firstCardBody.evaluate((body) => {
      body.insertAdjacentHTML(
        "beforeend",
        '<footer>Posted by <a href="/__fixture__/author-target/">Ada</a></footer>'
      );
    });
    await firstCardBody.getByRole("link", { name: "Ada" }).click();
    await expect(page).toHaveURL(/\/__fixture__\/author-target\/$/);
    await page.goBack();

    const restoredRelated = page.getByRole("navigation", { name: "Related articles" });
    const syntax = restoredRelated.getByRole("link", { name: "Syntax", exact: true });
    await syntax.focus();
    await expect(syntax).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(site(theme, "/docs/Syntax/"));
  }
});

test("Blog details link their explicitly related project", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one keyboard rendering contract is sufficient");

  for (const route of [
    "/blog/One%20vault%2C%20three%20readings/",
    "/blog/%E4%BB%8E%E7%AC%94%E8%AE%B0%E5%88%B0%E5%8F%91%E5%B8%83/"
  ]) {
    await page.goto(site("minimal", route));
    const project = page
      .getByRole("navigation", { name: "Related articles" })
      .getByRole("link", { name: "Jekyll Obsidian", exact: true });
    await expect(project).toHaveAttribute("href", site("minimal", "/portfolio/jekyll-obsidian/"));

    await project.focus();
    await expect(project).toBeFocused();
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(site("minimal", "/portfolio/jekyll-obsidian/"));
  }
});

test("Mobile typography and wide content stay inside narrow viewports", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "one mobile rendering contract is sufficient");

  for (const width of [320, 390]) {
    await page.setViewportSize({ width, height: 900 });
    for (const route of [site("minimal"), site("docs"), localizedDocs("/docs/Getting%20Started/")]) {
      await page.goto(route);
      expect(await page.locator("html").evaluate((element) => Number.parseFloat(getComputedStyle(element).fontSize)),
        `${route} root font at ${width}px`).toBeCloseTo(17, 1);
      const title = page.locator(".site-mark__name");
      await expect(title).not.toHaveText("");
      const dimensions = await title.evaluate((element) => {
        const style = getComputedStyle(element);
        return {
          clientWidth: element.clientWidth,
          scrollWidth: element.scrollWidth,
          overflow: style.overflow,
          whiteSpace: style.whiteSpace
        };
      });
      expect(dimensions.scrollWidth, `${route} title at ${width}px`).toBeLessThanOrEqual(dimensions.clientWidth);
      expect(dimensions.overflow, `${route} title at ${width}px`).toBe("visible");
      expect(dimensions.whiteSpace, `${route} title at ${width}px`).toBe("normal");
      expect(await page.locator(".site-header").evaluate((element) => element.scrollWidth <= element.clientWidth),
        `${route} header at ${width}px`).toBe(true);
    }

    await page.goto(site("minimal", "/blog/"));
    const topicList = page.locator(".tag-filter__list");
    await expect(topicList).toBeVisible();
    expect(await topicList.evaluate((element) => element.scrollWidth <= element.clientWidth),
      `Blog topic filters at ${width}px`).toBe(true);
    expect(await page.locator(".archive-ledger").evaluate((element) => element.scrollWidth <= element.clientWidth),
      `Blog ledger at ${width}px`).toBe(true);

    await page.goto(site("minimal", "/docs/Customization/"));
    for (const selector of [".note-content pre", ".note-content table"] as const) {
      const element = page.locator(selector).first();
      await expect(element).toBeVisible();
      if (selector.endsWith("table")) {
        await element.locator("td").first().evaluate((cell) => {
          cell.textContent = "A-deterministically-wide-table-value-".repeat(24);
          cell.setAttribute("style", "white-space: nowrap");
        });
        expect(await element.evaluate((node) => node.scrollWidth > node.clientWidth),
          `wide table scrolls internally at ${width}px`).toBe(true);
      }
      const geometry = await element.evaluate((node) => {
        const box = node.getBoundingClientRect();
        return {
          left: box.left,
          right: box.right,
          viewport: document.documentElement.clientWidth,
          ownOverflow: node.scrollWidth > node.clientWidth
        };
      });
      expect(geometry.left, `${selector} left at ${width}px`).toBeGreaterThanOrEqual(0);
      expect(geometry.right, `${selector} right at ${width}px`).toBeLessThanOrEqual(geometry.viewport + 1);
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth), `page width at ${width}px`)
      .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));
  }
});

test("desktop themes use the wider canvas without horizontal overflow", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop layout contract");
  await page.setViewportSize({ width: 1920, height: 1080 });

  await page.goto(site("minimal"));
  expect(await page.locator("html").evaluate((element) => Number.parseFloat(getComputedStyle(element).fontSize)))
    .toBeCloseTo(17, 1);
  expect((await page.locator(".minimal-recent__grid").boundingBox())!.width).toBeGreaterThanOrEqual(900);
  const minimalHomeProse = (await page.locator(".note-content > p").first().boundingBox())!;
  const minimalHomeMain = (await page.locator(".minimal-reading-column").boundingBox())!;
  expect(minimalHomeProse.width).toBeCloseTo(minimalHomeMain.width, 0);

  await page.goto(site("minimal", "/docs/Customization/"));
  expect((await page.locator(".note-content > [data-code-block-copy]").first().boundingBox())!.width)
    .toBeLessThanOrEqual(780);
  const minimalDocsShell = (await page.locator(".minimal-shell--docs").boundingBox())!;
  const minimalHeaderInner = (await page.locator(".site-header__inner").boundingBox())!;
  const minimalLogo = (await page.locator(".site-mark").boundingBox())!;
  const minimalSidebar = (await page.locator(".minimal-docs-sidebar").boundingBox())!;
  const minimalMain = (await page.locator(".minimal-reading-column").boundingBox())!;
  const minimalContext = (await page.locator(".minimal-context").boundingBox())!;
  expect(minimalDocsShell.x).toBeCloseTo(minimalHeaderInner.x, 0);
  expect(minimalDocsShell.width).toBeCloseTo(minimalHeaderInner.width, 0);
  expect(minimalSidebar.x).toBeCloseTo(minimalLogo.x, 0);
  expect(minimalSidebar.x + minimalSidebar.width).toBeLessThanOrEqual(minimalMain.x);
  expect(minimalMain.x + minimalMain.width).toBeLessThanOrEqual(minimalContext.x);
  expect(minimalContext.x + minimalContext.width)
    .toBeLessThanOrEqual(minimalDocsShell.x + minimalDocsShell.width + 1);

  await page.goto(site("docs", "/docs/Getting%20Started/"));
  const sidebar = (await page.locator(".docs-sidebar").boundingBox())!;
  const main = (await page.locator(".docs-main").boundingBox())!;
  const context = (await page.locator(".docs-context").boundingBox())!;
  const docsTitle = (await page.locator(".note-content > h1").first().boundingBox())!;
  const docsProse = (await page.locator(".note-content > p").first().boundingBox())!;
  const docsCode = (await page.locator(".note-content > [data-code-block-copy]").first().boundingBox())!;
  const docsActions = (await page.locator("[data-page-actions]").boundingBox())!;
  const docsShell = (await page.locator(".docs-shell").boundingBox())!;
  const headerInner = (await page.locator(".site-header__inner").boundingBox())!;
  const logo = (await page.locator(".site-mark").boundingBox())!;
  expect(main.width).toBeGreaterThanOrEqual(720);
  expect(docsProse.width).toBeLessThanOrEqual(640);
  expect(docsTitle.x).toBeCloseTo(docsProse.x, 0);
  expect(docsTitle.width).toBeCloseTo(docsProse.width, 0);
  expect(docsCode.x).toBeCloseTo(docsProse.x, 0);
  expect(docsCode.width).toBeCloseTo(docsProse.width, 0);
  expect(docsActions.x + docsActions.width).toBeCloseTo(docsProse.x + docsProse.width, 0);
  expect(docsShell.x).toBeCloseTo(headerInner.x, 0);
  expect(docsShell.width).toBeCloseTo(headerInner.width, 0);
  expect(sidebar.x).toBeCloseTo(logo.x, 0);
  expect(sidebar.x + sidebar.width).toBeLessThanOrEqual(main.x);
  expect(main.x + main.width).toBeLessThanOrEqual(context.x);
  expect(context.x + context.width).toBeLessThanOrEqual(docsShell.x + docsShell.width + 1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth))
    .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));
});

test("Minimal aligns prose and authored Home actions to the reading edge", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop reading-column contract");
  await page.setViewportSize({ width: 1190, height: 900 });
  await page.goto(site("minimal"));

  const title = (await page.locator(".note-content > h1").first().boundingBox())!;
  const paragraph = (await page.locator(".note-content > p").first().boundingBox())!;
  const callout = (await page.locator(".note-content > .callout").first().boundingBox())!;
  const recent = (await page.locator(".minimal-recent").boundingBox())!;
  const actions = (await page.locator("[data-page-actions]").boundingBox())!;
  expect(title.x).toBeCloseTo(paragraph.x, 0);
  expect(title.width).toBeCloseTo(paragraph.width, 0);
  expect(callout.x).toBeCloseTo(paragraph.x, 0);
  expect(callout.width).toBeCloseTo(paragraph.width, 0);
  expect(title.x).toBeCloseTo(recent.x, 0);
  expect(actions.x + actions.width).toBeCloseTo(paragraph.x + paragraph.width, 0);
  expect(actions.y).toBeCloseTo(title.y, 0);
  expect(recent.y).toBeGreaterThan(actions.y + actions.height);

  await page.goto(site("minimal", "/blog/One%20vault%2C%20three%20readings/"));
  const articleParagraph = (await page.locator(".note-content > p").first().boundingBox())!;
  expect(articleParagraph.x).toBeCloseTo(paragraph.x, 0);
  expect(articleParagraph.width).toBeCloseTo(paragraph.width, 0);

  await page.goto(site("minimal", "/docs/Customization/"));
  const documentTitle = (await page.locator(".note-content > h1").first().boundingBox())!;
  const prose = (await page.locator(".note-content > p").first().boundingBox())!;
  const code = (await page.locator(".note-content > [data-code-block-copy]").first().boundingBox())!;
  const table = (await page.locator(".note-content > table").first().boundingBox())!;
  const entry = (await page.locator(".minimal-entry").boundingBox())!;
  const noteActions = (await page.locator("[data-page-actions]").boundingBox())!;
  expect(documentTitle.x).toBeCloseTo(prose.x, 0);
  expect(documentTitle.width).toBeCloseTo(prose.width, 0);
  expect(code.x).toBeCloseTo(prose.x, 0);
  expect(code.width).toBeCloseTo(prose.width, 0);
  expect(table.x).toBeCloseTo(prose.x, 0);
  expect(table.x + table.width).toBeCloseTo(prose.x + prose.width, 0);
  expect(table.x + table.width).toBeLessThanOrEqual(entry.x + entry.width + 1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth))
    .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));
  expect(noteActions.x + noteActions.width).toBeCloseTo(prose.x + prose.width, 0);
});

test("Minimal aligns desktop rails, content tops, and page actions across page types", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop layout geometry");
  await page.setViewportSize({ width: 1440, height: 1000 });
  const contentOffsets: number[] = [];
  const contextPositions: number[] = [];

  for (const route of [
    "/",
    "/blog/One%20vault%2C%20three%20readings/",
    "/docs/Customization/"
  ]) {
    await page.goto(site("minimal", route));
    const shell = page.locator(".minimal-shell");
    const header = (await page.locator(".site-header").boundingBox())!;
    const entry = (await page.locator(".minimal-entry").boundingBox())!;
    const prose = (await page.locator(".note-content > p").first().boundingBox())!;
    const context = (await page.locator(".minimal-context").boundingBox())!;
    const readingColumn = (await page.locator(".minimal-reading-column").boundingBox())!;
    const actions = (await page.locator("[data-page-actions]").boundingBox())!;
    const columnGap = await shell.evaluate((element) => Number.parseFloat(getComputedStyle(element).columnGap));
    contentOffsets.push(entry.y - (header.y + header.height));
    contextPositions.push(context.x);
    expect.soft(context.x - (prose.x + prose.width), `${route} reading-to-context gap`)
      .toBeCloseTo(columnGap, 0);
    expect.soft(actions.x + actions.width, `${route} action at middle-column end`)
      .toBeCloseTo(readingColumn.x + readingColumn.width, 0);
    expect.soft(actions.y, `${route} action at middle-column top`).toBeCloseTo(readingColumn.y, 0);
  }
  expect.soft(contentOffsets[1]!, "article top rhythm").toBeCloseTo(contentOffsets[0]!, 0);
  expect.soft(contentOffsets[2]!, "documentation top rhythm").toBeCloseTo(contentOffsets[0]!, 0);

  await page.goto(site("minimal", "/blog/"));
  contextPositions.push((await page.locator(".archive-context").boundingBox())!.x);
  expect((await page.locator(".archive-ledger").boundingBox())!.width)
    .toBeGreaterThan(780);
  for (const position of contextPositions.slice(1)) {
    expect.soft(position, "stable right-rail position").toBeCloseTo(contextPositions[0]!, 0);
  }
});

test("Minimal page actions reserve the leading header line in LTR, RTL, and narrow layouts", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "one geometry contract is sufficient");
  const routes = [
    { route: "/", leading: ".note-content > h1" },
    { route: "/blog/One%20vault%2C%20three%20readings/", leading: ".note-header > :first-child" },
    { route: "/docs/Customization/", leading: ".note-header > :first-child" }
  ] as const;
  const geometry = async (leading: string) => page.locator(leading).evaluate((element) => {
    const content = element.getBoundingClientRect();
    const range = document.createRange();
    range.selectNodeContents(element);
    const actionElement = document.querySelector<HTMLElement>("[data-page-actions]")!;
    const action = actionElement.getBoundingClientRect();
    const actionStyle = getComputedStyle(actionElement);
    return {
      actionPosition: actionStyle.position,
      actionFloat: actionStyle.cssFloat,
      contentWidth: content.width,
      textWrap: getComputedStyle(element).textWrap,
      overlaps: Array.from(range.getClientRects()).some((line) =>
        line.width > 0 && line.left < action.right && line.right > action.left
        && line.top < action.bottom && line.bottom > action.top
      )
    };
  });

  for (const width of [1440, 1200]) {
    await page.setViewportSize({ width, height: 1000 });
    for (const direction of ["ltr", "rtl"] as const) {
      for (const { route, leading } of routes) {
        await page.goto(site("minimal", route));
        await page.locator("html").evaluate((element, dir) => { element.setAttribute("dir", dir); }, direction);
        if (route !== "/") {
          await page.locator(leading).evaluate((element) => {
            element.textContent = "A deliberately long leading line proves that localized headings wrap before page actions";
          });
        }
        const result = await geometry(leading);
        expect(result.overlaps, `${route} ${width}px ${direction} leading text avoids page actions`).toBe(false);
        if (route === "/") {
          expect(result.actionPosition, `${width}px Home action stays in flow`).toBe("relative");
          expect(result.actionFloat, `${width}px Home action reserves its measured width`).toBe("inline-end");
          expect(result.textWrap, `${width}px Home title uses available line width`).toBe("wrap");
          expect(result.contentWidth, `${width}px Home title keeps the full reading width`)
            .toBeCloseTo((await page.locator(".minimal-reading-column").boundingBox())!.width, 0);
        }
      }
    }
  }

  await page.setViewportSize({ width: 520, height: 900 });
  for (const { route, leading } of routes) {
    await page.goto(site("minimal", route));
    await expect(page.locator("[data-page-actions]")).toHaveCSS("position", "static");
    expect((await geometry(leading)).overlaps, `${route} mobile actions remain in flow`).toBe(false);
  }
});

test("author CSS classes cannot override theme reading alignment", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop reading-column contract");
  await page.setViewportSize({ width: 1440, height: 1000 });

  for (const { theme, route, articleSelector, collisionClasses } of [
    {
      theme: "minimal" as const,
      route: "/blog/One%20vault%2C%20three%20readings/",
      articleSelector: ".minimal-entry",
      collisionClasses: ["docs-article", "docs-main", "theme-docs"]
    },
    {
      theme: "docs" as const,
      route: "/docs/Customization/",
      articleSelector: ".docs-article",
      collisionClasses: ["minimal-entry", "minimal-reading-column", "theme-minimal"]
    }
  ]) {
    await page.goto(site(theme, route));
    const prose = (await page.locator(".note-content > p").first().boundingBox())!;
    await page.locator(articleSelector).evaluate(
      (element, classes) => element.classList.add(...classes),
      collisionClasses
    );
    const collidedProse = (await page.locator(".note-content > p").first().boundingBox())!;
    expect(collidedProse.x, `${theme} author classes cannot change theme alignment`).toBeCloseTo(prose.x, 0);
    expect(collidedProse.width, `${theme} author classes cannot change reading width`).toBeCloseTo(prose.width, 0);
  }
});

test("documentation code wrappers and sequence controls follow each theme reading column", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop reading-column geometry");
  await page.setViewportSize({ width: 1440, height: 1000 });

  for (const theme of themes) {
    await page.goto(site(theme, "/docs/Customization/"));
    const prose = (await page.locator(".note-content > p").first().boundingBox())!;
    const codeOuter = page.locator(".note-content > :is(.code-block-copy, pre)").first();
    await codeOuter.evaluate((code) => {
      const highlighter = document.createElement("div");
      highlighter.className = "highlighter-rouge";
      const highlight = document.createElement("div");
      highlight.className = "highlight";
      code.replaceWith(highlighter);
      highlighter.append(highlight);
      highlight.append(code);
    });
    const highlighter = (await page.locator(".note-content > .highlighter-rouge").first().boundingBox())!;
    const nestedCode = (await page.locator(".highlighter-rouge > .highlight > :is(.code-block-copy, pre)")
      .first().boundingBox())!;
    expect(highlighter.x, `${theme} fenced wrapper left`).toBeCloseTo(prose.x, 0);
    expect(highlighter.width, `${theme} fenced wrapper width`).toBeCloseTo(prose.width, 0);
    expect(nestedCode.x, `${theme} nested code left`).toBeCloseTo(highlighter.x, 0);
    expect(nestedCode.width, `${theme} nested code width`).toBeCloseTo(highlighter.width, 0);

    const table = page.locator(".note-content > table").first();
    const tableBox = (await table.boundingBox())!;
    expect(tableBox.x, `${theme} table left`).toBeCloseTo(prose.x, 0);
    expect(tableBox.x + tableBox.width, `${theme} table right`).toBeCloseTo(prose.x + prose.width, 0);
    await table.locator("td").first().evaluate((cell) => {
      cell.textContent = "A-deterministically-wide-table-value-".repeat(24);
      cell.setAttribute("style", "white-space: nowrap");
    });
    expect(await table.evaluate((element) => element.scrollWidth > element.clientWidth),
      `${theme} wide table scrolls internally`).toBe(true);
    expect(await page.evaluate(() => document.documentElement.scrollWidth), `${theme} table page width`)
      .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));

    const pairedNavigation = page.getByRole("navigation", { name: "Documentation sequence" });
    const pairedBox = (await pairedNavigation.boundingBox())!;
    const pairedLinks = pairedNavigation.locator(":scope > a");
    await expect(pairedLinks).toHaveCount(2);
    const pairedLinkBoxes = await pairedLinks.evaluateAll((links) => links.map((link) => {
      const box = link.getBoundingClientRect();
      return { x: box.x, width: box.width, right: box.right };
    }));
    const [previousBox, pairedNextBox] = pairedLinkBoxes;
    if (!previousBox || !pairedNextBox) throw new Error(`Expected two ${theme} sequence links`);
    expect(pairedBox.x, `${theme} paired navigation left`).toBeCloseTo(prose.x, 0);
    expect(pairedBox.x + pairedBox.width, `${theme} paired navigation right`)
      .toBeCloseTo(prose.x + prose.width, 0);
    expect(previousBox.width, `${theme} equal sequence columns`).toBeCloseTo(pairedNextBox.width, 0);

    await page.goto(site(theme, "/docs/"));
    const body = (await page.locator(".note-content > p").first().boundingBox())!;
    const singleNavigation = page.getByRole("navigation", { name: "Documentation sequence" });
    const singleBox = (await singleNavigation.boundingBox())!;
    const next = singleNavigation.locator(":scope > a[rel='next']");
    await expect(singleNavigation.locator(":scope > a")).toHaveCount(1);
    const nextBox = (await next.boundingBox())!;
    expect(singleBox.x, `${theme} single navigation left`).toBeCloseTo(body.x, 0);
    expect(singleBox.x + singleBox.width, `${theme} single navigation right`)
      .toBeCloseTo(body.x + body.width, 0);
    const columnGap = await singleNavigation.evaluate((navigation) =>
      Number.parseFloat(getComputedStyle(navigation).columnGap) || 0
    );
    expect(nextBox.x, `${theme} single next uses second slot`)
      .toBeCloseTo(singleBox.x + ((singleBox.width + columnGap) / 2), 0);
    expect(Math.abs((nextBox.x + nextBox.width) - (body.x + body.width)), `${theme} single next right`)
      .toBeLessThanOrEqual(1);

    await page.goto(site(theme, "/docs/Syntax/"));
    const footnotes = (await page.locator(".note-content > .footnotes").boundingBox())!;
    const sourceActions = (await page.locator(".source-actions").boundingBox())!;
    expect(footnotes.x, `${theme} footnotes left`).toBeCloseTo(sourceActions.x, 0);
    expect(footnotes.x + footnotes.width, `${theme} footnotes right`)
      .toBeCloseTo(sourceActions.x + sourceActions.width, 0);
  }
});

test("localized docs search loads the locale index and finds CJK content", async ({ page }) => {
  await page.goto(localizedDocs("/zh-CN/"));
  await page.keyboard.press("ControlOrMeta+k");
  const dialog = page.locator('dialog[data-dialog="search"]');
  await dialog.locator("input").fill("快速");
  await expect(dialog.getByRole("link", { name: "快速开始" })).toBeVisible();
  await expect(dialog.locator("[data-search-status]")).toHaveText(/找到 \d+ 篇笔记。/);
});

test("Tweet embeds load near the viewport with DNT and keep a static fallback", async ({ page }) => {
  await page.route("https://platform.twitter.com/widgets.js", async (route) => {
    await route.fulfill({
      contentType: "text/javascript",
      body: `window.twttr = { widgets: { createTweet(id, target, options) {
        target.dataset.renderedTweet = id;
        target.dataset.dnt = String(options.dnt);
        target.dataset.theme = options.theme;
        target.textContent = "Rendered post";
        return Promise.resolve(target);
      } } };`
    });
  });
  await page.goto("/__fixture__/tweet/");

  const tweet = page.locator("[data-website-tweet]");
  const mount = tweet.locator("[data-website-tweet-mount]");
  await expect(mount).toHaveAttribute("data-rendered-tweet", "1580548874246443010");
  await expect(mount).toHaveAttribute("data-dnt", "true");
  await expect(mount).toHaveAttribute("data-theme", /^(light|dark)$/);
  await expect(tweet.locator("[data-website-tweet-fallback]")).toBeHidden();
  await expect(page.locator("script[data-website-x-widgets]")).toHaveAttribute(
    "src",
    "https://platform.twitter.com/widgets.js"
  );
});

for (const fixture of [
  { theme: "minimal", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "minimal", feature: "relations", visible: "Backlinks", hidden: "On this page" },
  { theme: "docs", feature: "outline", visible: "On this page", hidden: "Backlinks" },
  { theme: "docs", feature: "relations", visible: "Backlinks", hidden: "On this page" }
] as const) {
  test(`${fixture.theme} renders ${fixture.feature} independently`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop context assertion");
    await page.goto(`/__fixture__/features/${fixture.theme}/${fixture.feature}/`);
    const panel = page.locator("[data-context-panel]");
    await expect(panel).toBeVisible();
    await expect(panel.getByRole("heading", { name: fixture.visible })).toBeVisible();
    await expect(panel.getByRole("heading", { name: fixture.hidden })).toHaveCount(0);
  });
}

test("relation context puts collapsed direct links after backlinks", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "desktop-chromium", "desktop relation assertion");
  await page.goto("/__fixture__/features/minimal/relations/");
  const panel = page.locator("[data-context-panel]");
  const titles = await panel.locator(":scope > .relation-section").evaluateAll((sections) =>
    sections.map((section) => section.querySelector(".relation-section__title")?.textContent?.trim())
  );
  expect(titles.indexOf("Backlinks")).toBeLessThan(titles.indexOf("Direct links"));
  const directLinks = panel.locator("details.relation-disclosure");
  await expect(directLinks).not.toHaveAttribute("open", "");
  await expect(directLinks.getByRole("link", { name: "Linked note" })).toBeHidden();
  await directLinks.locator("summary").click();
  await expect(directLinks.getByRole("link", { name: "Linked note" })).toBeVisible();
});

test("themes remove context UI when outline and relations are disabled", async ({ page }) => {
  for (const theme of themes) {
    await page.goto(`/__fixture__/features/${theme}/none/`);
    await expect(page.locator("[data-context-panel], [data-dialog='context']")).toHaveCount(0);
    await expect(page.getByRole("button", { name: /Context|On this page/ })).toHaveCount(0);
  }
});

test("non-default context features remain available in mobile sheets", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== "mobile-chromium", "mobile context assertion");
  for (const [theme, feature, heading] of [
    ["minimal", "outline", "On this page"],
    ["minimal", "relations", "Backlinks"],
    ["docs", "outline", "On this page"],
    ["docs", "relations", "Backlinks"]
  ] as const) {
    await page.goto(`/__fixture__/features/${theme}/${feature}/`);
    await expect(page.locator("[data-context-panel]")).toBeHidden();
    await page.getByRole("button", { name: feature === "outline" ? "On this page" : "Context" }).tap();
    await expect(page.locator('dialog[data-dialog="context"] .relation-section__title')
      .filter({ hasText: heading })).toBeVisible();
  }
});

test.describe("without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  for (const theme of themes) {
    test(`${theme} retains authored content and navigation`, async ({ page }) => {
      await page.goto(site(theme));
      await expect(page.locator(theme === "minimal" ? "main > .minimal-reading-column > .minimal-entry" : "main > .docs-article"))
        .toBeVisible();
      await expect(page.getByRole("navigation").first()).toBeVisible();
      await expect(page.locator(".mobile-toolbar")).toBeHidden();
    });
  }

  test("priority navigation exposes every custom link without JavaScript", async ({ page }, testInfo) => {
    test.skip(testInfo.project.name !== "desktop-chromium", "desktop no-JavaScript navigation assertion");
    await page.goto("/__fixture__/features/minimal/navigation/");
    const navigation = page.getByRole("navigation", { name: "Primary navigation" });
    await expect(navigation.locator("[data-priority-navigation-list] > li > a")).toHaveText([
      "Home", "Blog", "Docs", "About", "Portfolio", "Projects", "Team", "Contact"
    ]);
    await expect(navigation.locator("[data-priority-navigation-more]")).toBeHidden();
    await expect(navigation.getByRole("link", { name: "Projects" })).toHaveAttribute("aria-current", "page");
  });

  test("docs serves its complete index without JavaScript", async ({ page }) => {
    await page.goto(site("docs", "/docs/Getting%20Started/"));
    const navigation = page.getByRole("navigation", { name: "Documentation", exact: true });
    await expect(navigation.getByRole("link", { name: "Architecture" })).toBeVisible();
    await expect(page.getByRole("link", { name: "View full documentation index" })).toHaveCount(0);
  });

  test("Comments retain the GitHub Discussions fallback", async ({ page }) => {
    await page.goto("/__fixture__/comments/");
    const comments = page.getByRole("region", { name: "Comments" });
    await expect(comments.locator("script[data-website-comments-client]")).toHaveCount(0);
    await expect(comments.getByRole("link", { name: "Open discussions on GitHub" })).toBeVisible();
  });

  test("Tweet embeds retain the X fallback", async ({ page }) => {
    await page.goto("/__fixture__/tweet/");
    await expect(page.locator("script[data-website-x-widgets]")).toHaveCount(0);
    await expect(page.getByRole("link", { name: "View post on X" }))
      .toHaveAttribute("href", "https://x.com/obsdmd/status/1580548874246443010");
  });

  test("documentation graphs and mobile context have server-rendered fallbacks", async ({ page }, testInfo) => {
    await page.goto(site("minimal", "/docs/Syntax/"));
    await expect(page.locator(".local-graph__fallback")).toBeVisible();
    await expect(page.locator("pre[lang='mermaid']")).toBeVisible();
    if (testInfo.project.name === "mobile-chromium") {
      await expect(page.getByRole("complementary", { name: "Page context" })).toBeVisible();
      await expect(page.getByRole("heading", { name: "Backlinks" })).toBeVisible();
    }
  });
});
