import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const assetsRoot = path.join(projectRoot, ".jekyll-obsidian-cache", "assets");
const siteRoots = Object.fromEntries(
  ["minimal", "docs", "docs-i18n"].map((theme) => [
    theme,
    path.join(projectRoot, `_site-browser-${theme}`)
  ])
);
const manifest = JSON.parse(await readFile(path.join(assetsRoot, "manifest.json"), "utf8"));

function contextSections(feature, location) {
  const outline = feature === "outline"
    ? `<section class="relation-section" aria-labelledby="feature-outline-${location}"><h2 class="relation-section__title" id="feature-outline-${location}">On this page</h2><ol class="outline-list"><li><a href="#feature-heading">Feature heading</a></li></ol></section>`
    : "";
  const relations = feature === "relations"
    ? `<section class="relation-section" aria-labelledby="feature-backlinks-${location}"><h2 class="relation-section__title" id="feature-backlinks-${location}">Backlinks</h2><ul class="relation-list"><li><a href="/notes/source/">Source note</a></li></ul></section><section class="relation-section" aria-labelledby="feature-links-${location}"><details class="relation-disclosure"><summary><h2 class="relation-section__title" id="feature-links-${location}">Direct links</h2></summary><ul class="relation-list"><li><a href="/notes/linked/">Linked note</a></li></ul></details></section><section class="relation-section" aria-labelledby="feature-embedded-${location}"><h2 class="relation-section__title" id="feature-embedded-${location}">Embedded by</h2><p class="relation-empty">Not embedded elsewhere.</p></section>`
    : "";
  return `${outline}${relations}`;
}

function featureFixture(theme, feature) {
  const entry = manifest.entries[theme];
  const hasContext = feature === "outline" || feature === "relations";
  const hasNavigation = feature === "navigation";
  const navigationItems = hasNavigation
    ? [
        ["home", "Home", "/"],
        ["blog", "Blog", "/blog/"],
        ["docs", "Docs", "/docs/"],
        ["page:about.md", "About", "/about/"],
        ["portfolio", "Portfolio", "/portfolio/"],
        ["page:projects.md", "Projects", "/projects/"],
        ["folder:team", "Team", "/team/"],
        ["page:contact.md", "Contact", "/contact/"]
      ]
    : [["home", "Home", "/"]];
  const navigationLinks = navigationItems.map(([id, label, url]) =>
    `<li data-priority-navigation-item data-navigation-id="${id}"><a href="${url}"${id === "page:projects.md" ? ' aria-current="page"' : ""}>${label}</a></li>`
  ).join("");
  const feedDiscovery = hasNavigation
    ? '<link rel="alternate" type="application/atom+xml" title="Obsidian feed" href="/feed.xml">'
    : "";
  const panelClass = theme === "docs" ? "docs-context" : "minimal-context";
  const article = `<article class="${theme === "docs" ? "docs-article" : "minimal-entry"}"><header class="note-header"><h1 class="note-title">Independent context</h1></header><div class="note-content"><p>Outline and note relations are independent presentation features.</p><h2 id="feature-heading">Feature heading</h2><p>Authored content remains available in every combination.</p></div></article>`;
  const panel = hasContext
    ? `<aside class="${panelClass}" data-context-panel aria-label="Page context">${contextSections(feature, "rail")}</aside>`
    : "";
  const shell = theme === "docs"
      ? `<div class="docs-shell"><aside class="docs-sidebar"><nav aria-label="Documentation"><a href="/docs/">Documentation</a></nav></aside><main class="docs-main" id="main">${article}</main>${panel}</div>`
      : `<main class="minimal-shell" id="main"><div class="minimal-reading-column">${article}</div>${panel}</main>`;
  const contextUi = hasContext
    ? `<nav class="mobile-toolbar" aria-label="Mobile actions"><button type="button" data-dialog-open="context">${feature === "outline" ? "On this page" : "Context"}</button></nav><template data-dialog-template="context">${contextSections(feature, "dialog")}</template><dialog class="website-dialog" data-dialog="context" aria-labelledby="feature-context-title"><div class="website-dialog__sheet"><header class="website-dialog__header"><h2 class="website-dialog__title" id="feature-context-title">${feature === "outline" ? "On this page" : "Context"}</h2><button class="website-dialog__close" type="button" data-dialog-close aria-label="Close page context">×</button></header><div class="website-dialog__body" data-dialog-content></div></div></dialog>`
    : "";
  const browseContents = `<nav aria-label="Primary navigation"><ul class="relation-list">${navigationItems.map(([id, label, url]) => `<li data-navigation-id="${id}"><a href="${url}"${id === "page:projects.md" ? ' aria-current="page"' : ""}>${label}</a></li>`).join("")}</ul></nav>${theme === "docs" ? `<nav class="docs-tree" aria-label="Documentation"><ul class="docs-tree__list"><li class="docs-tree__item"><a href="/docs/">Getting started</a></li></ul></nav>` : ""}`;
  const navigationUi = hasNavigation
    ? `<nav class="mobile-toolbar" aria-label="Mobile actions"><button type="button" data-dialog-open="browse">Browse</button></nav><template data-dialog-template="browse">${browseContents}</template><dialog class="website-dialog" data-dialog="browse" aria-labelledby="feature-browse-title"><div class="website-dialog__sheet"><header class="website-dialog__header"><h2 class="website-dialog__title" id="feature-browse-title">Browse</h2><button class="website-dialog__close" type="button" data-dialog-close aria-label="Close browse menu">×</button></header><div class="website-dialog__body" data-dialog-content></div></div></dialog>`
    : "";

  return `<!doctype html><html class="no-js" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Feature overrides</title>${feedDiscovery}<link rel="stylesheet" href="/assets/website/${entry.css}"><script type="module" src="/assets/website/${entry.js}"></script></head><body class="theme-${theme}"><header class="site-header"><div class="site-header__inner"><a class="site-mark" href="/">Obsidian</a><nav class="site-navigation" aria-label="Primary navigation" data-priority-navigation><ul class="site-navigation__list" data-priority-navigation-list>${navigationLinks}</ul><details class="site-navigation__more" data-priority-navigation-more hidden><summary>More</summary><ul class="site-navigation__overflow" data-priority-navigation-overflow></ul></details></nav></div></header>${shell}${contextUi}${navigationUi}</body></html>`;
}

function commentsFixture() {
  const comments = `<section class="website-comments" aria-labelledby="website-comments-title" data-website-comments-load data-website-comments-repository="example/community" data-website-comments-repository-id="R_kgDOExample" data-website-comments-category="Blog comments" data-website-comments-category-id="DIC_kwDOExample" data-website-comments-term="website:post:blog/post" data-website-comments-language="en" data-website-comments-unavailable="Comments could not be loaded. You can continue the conversation on GitHub."><header class="website-comments__header"><h2 id="website-comments-title">Comments</h2></header><p class="website-comments__status" data-website-comments-status aria-live="polite">Loading comments…</p><div class="giscus website-comments__embed" data-website-comments-container></div><p class="website-comments__fallback">Comments are stored in GitHub Discussions. <a href="https://github.com/example/community/discussions">Open discussions on GitHub</a>.</p></section>`;
  return featureFixture("minimal", "none").replace("</article>", `${comments}</article>`);
}

function analyticsFixture(provider) {
  const analytics = provider === "cloudflare"
    ? '<meta name="website:analytics" data-provider="cloudflare" content="site-token-123">'
    : '<meta name="website:analytics" data-provider="google" content="G-ABC123XYZ9">';
  return featureFixture("docs", "navigation").replace(
    "<title>Feature overrides</title>",
    `${analytics}<title>Feature overrides</title>`
  );
}

function tweetFixture() {
  const tweet = `<figure class="website-tweet" data-website-tweet="1580548874246443010"><div class="website-tweet__mount" data-website-tweet-mount></div><a class="website-tweet__fallback" data-website-tweet-fallback href="https://x.com/obsdmd/status/1580548874246443010">View post on X</a></figure>`;
  return featureFixture("minimal", "none").replace("</article>", `${tweet}</article>`);
}

function postCardFixture() {
  const entry = manifest.entries.minimal;
  return `<!doctype html><html class="no-js" lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Post card</title><link rel="stylesheet" href="/assets/website/${entry.css}"></head><body class="theme-minimal"><main class="minimal-shell minimal-shell--system"><article class="minimal-entry"><div class="note-content"><section class="minimal-recent"><div class="minimal-recent__grid"><article class="minimal-post-card minimal-post-card--with-image"><div class="minimal-post-card__media"><img alt="" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='320' height='180'/%3E"></div><div class="minimal-post-card__body"><h3><a href="/__fixture__/post-target/">A complete card target</a></h3><p class="minimal-post-card__excerpt">The excerpt shares the article destination.</p><footer><span>Posted by <a href="/__fixture__/author-target/">Ada</a></span></footer></div></article></div></section></div></article></main></body></html>`;
}

const json = {
  "/data/catalog.v1.json": {
    schema_version: 1,
    notes: [
      {
        id: "concepts/attention.md",
        title: "Attention as a garden",
        url: "/notes/attention/",
        aliases: ["Attention"],
        tags: ["thinking", "practice"],
        description: "A working model for deliberate attention.",
        preview: "Attention becomes legible when observations and relations stay close together.",
        updated: "2026-07-31",
        content_type: "post",
        published_at: "2026-07-31"
      },
      {
        id: "notes/中文搜索.md",
        title: "中文搜索",
        url: "/notes/zh/",
        aliases: ["知识花园"],
        tags: ["中文"],
        description: null,
        preview: "中文内容使用稳定的单字和双字索引。",
        updated: "2026-07-31",
        content_type: "doc",
        published_at: null
      }
    ]
  },
  "/data/search.v1.json": {
    schema_version: 1,
    documents: [
      {
        id: "concepts/attention.md",
        title: "Attention as a garden",
        url: "/notes/attention/",
        aliases: ["Attention"],
        tags: ["thinking", "practice"],
        text: "Observations relation rail context links and daily practice."
      },
      {
        id: "notes/中文搜索.md",
        title: "中文搜索",
        url: "/notes/zh/",
        aliases: ["知识花园"],
        tags: ["中文"],
        text: "中文内容使用稳定的单字和双字索引。"
      }
    ]
  },
  "/data/graph.v1.json": {
    schema_version: 1,
    nodes: [
      { id: "concepts/attention.md", title: "Attention as a garden", url: "/notes/attention/" },
      { id: "notes/中文搜索.md", title: "中文搜索", url: "/notes/zh/" }
    ],
    edges: [
      {
        source: "concepts/attention.md",
        target: "notes/中文搜索.md",
        kind: "link",
        count: 1
      }
    ]
  }
};

const contentTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
  ".xml": "application/xml; charset=utf-8",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2"
};

async function serveFile(response, root, relative) {
  const target = path.resolve(root, relative);
  if (target !== root && !target.startsWith(`${root}${path.sep}`)) {
    response.writeHead(403).end();
    return true;
  }
  try {
    const body = await readFile(target);
    response.writeHead(200, {
      "Content-Type": contentTypes[path.extname(target)] ?? "application/octet-stream"
    });
    response.end(body);
    return true;
  } catch {
    return false;
  }
}

const server = createServer(async (request, response) => {
  const pathname = new URL(request.url ?? "/", "http://127.0.0.1").pathname;
  const siteMatch = pathname.match(/^\/__site__\/(minimal|docs-i18n|docs)(\/.*)?$/);
  if (siteMatch) {
    const root = siteRoots[siteMatch[1]];
    const sitePath = siteMatch[2] || "/";
    try {
      const decoded = decodeURIComponent(sitePath);
      const relative = decoded === "/"
        ? "index.html"
        : decoded.endsWith("/")
          ? `${decoded.slice(1)}index.html`
          : decoded.slice(1);
      if (await serveFile(response, root, relative)) return;
    } catch {
      response.writeHead(400, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("Bad request");
      return;
    }
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    response.end("Not found");
    return;
  }
  const featureMatch = pathname.match(
    /^\/__fixture__\/features\/(minimal|docs)\/(outline|relations|navigation|none)\/$/
  );
  if (featureMatch) {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(featureFixture(featureMatch[1], featureMatch[2]));
    return;
  }
  if (pathname === "/__fixture__/comments/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(commentsFixture());
    return;
  }
  const analyticsMatch = pathname.match(/^\/__fixture__\/analytics\/(cloudflare|google)\/$/);
  if (analyticsMatch) {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(analyticsFixture(analyticsMatch[1]));
    return;
  }
  if (pathname === "/__fixture__/tweet/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(tweetFixture());
    return;
  }
  if (pathname === "/__fixture__/post-card/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end(postCardFixture());
    return;
  }
  if (pathname === "/__fixture__/post-target/" || pathname === "/__fixture__/author-target/") {
    response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    response.end("<!doctype html><title>Card destination</title>");
    return;
  }
  if (pathname in json) {
    response.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
    response.end(JSON.stringify(json[pathname]));
    return;
  }
  if (pathname.startsWith("/assets/website/")) {
    const relative = decodeURIComponent(pathname.slice("/assets/website/".length));
    if (await serveFile(response, assetsRoot, relative)) return;
    response.writeHead(404).end();
    return;
  }
  response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
  response.end("Not found");
});

server.listen(4173, "127.0.0.1", () => {
  process.stdout.write("WEBSITE_BROWSER_SERVER_READY\n");
});
