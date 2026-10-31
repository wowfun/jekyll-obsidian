// @vitest-environment happy-dom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { initialisePageNavigation, sameContentSecurityPolicy } from "../../src/frontend/page-navigation";

function fetchedDocument(policy?: string): Document {
  return new DOMParser().parseFromString(
    `<!doctype html><html><head>${policy ? `<meta data-page-csp content="${policy}">` : ""}</head><body></body></html>`,
    "text/html"
  );
}

describe("documentation page CSP", () => {
  beforeEach(() => {
    document.head.replaceChildren();
  });

  it("keeps persistent navigation only when the complete policy is unchanged", () => {
    document.head.insertAdjacentHTML("beforeend", '<meta data-page-csp content="frame-src \'self\'">');

    expect(sameContentSecurityPolicy(fetchedDocument("frame-src 'self'"))).toBe(true);
    expect(sameContentSecurityPolicy(fetchedDocument("frame-src 'self' https://player.vimeo.com"))).toBe(false);
    expect(sameContentSecurityPolicy(fetchedDocument())).toBe(false);
  });
});

describe("documentation page controls", () => {
  const originalUrl = window.location.href;
  const originalLanguage = document.documentElement.lang;
  const originalDirection = document.documentElement.dir;

  afterEach(() => {
    document.body.replaceChildren();
    initialisePageNavigation();
    document.head.replaceChildren();
    document.body.className = "";
    document.documentElement.lang = originalLanguage;
    document.documentElement.dir = originalDirection;
    window.history.replaceState(null, "", originalUrl);
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  for (const changed of ['policy', 'assets', 'locale', 'status', 'actions-added', 'actions-removed', 'none']) it(`handles destination ${changed} without leaving stale content`, async () => {
    document.documentElement.lang = 'en';
    document.head.innerHTML = '<meta data-page-csp content="default-src self"><script type="application/json" data-website-asset src="/theme.js"></script><script type="application/json" src="/analytics.js"></script>';
    document.body.className = 'theme-minimal';
    document.body.innerHTML = '<nav data-priority-navigation><a href="/two/">Two</a></nav><main class="minimal-shell" tabindex="-1">One</main>';
    if (changed === 'actions-removed') document.body.insertAdjacentHTML('afterbegin', '<div data-page-header-actions></div>');
    const source = `<html lang="${changed === 'locale' ? 'zh-CN' : 'en'}"><head><meta data-page-csp content="${changed === 'policy' ? 'default-src none' : 'default-src self'}"><script type="application/json" data-website-asset src="/${changed === 'assets' ? 'new-theme' : 'theme'}.js"></script></head><body class="theme-minimal">${changed === 'actions-added' ? '<div data-page-header-actions></div>' : ''}<main class="minimal-shell" tabindex="-1">Two</main></body></html>`;
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(source, { status: changed === 'status' ? 503 : 200, headers: { 'Content-Type': 'text/html' } })));
    const assign = vi.spyOn(window.location, 'assign').mockImplementation(() => {});
    vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    initialisePageNavigation();
    document.querySelector<HTMLAnchorElement>('a')!.click();
    await vi.waitFor(() => {
      if (changed === 'none') {
        expect(document.querySelector('main')?.textContent).toBe('Two');
        expect(assign).not.toHaveBeenCalled();
      } else {
        expect(assign).toHaveBeenCalledWith(new URL('/two/', originalUrl).href);
        expect(document.querySelector('main')?.textContent).toBe('One');
      }
    });
  });

  it("ignores a superseded request even when cancellation rejects with a generic error", async () => {
    document.head.innerHTML = '<meta data-page-csp content="default-src self">';
    document.body.className = "theme-docs";
    document.body.innerHTML = '<aside class="docs-sidebar"><nav data-docs-navigation><a href="/two/">Two</a><a href="/three/">Three</a></nav></aside><main data-docs-main tabindex="-1">One</main>';
    let rejectFirst!: (reason: Error) => void;
    let resolveLast!: (response: Response) => void;
    vi.stubGlobal("fetch", vi.fn()
      .mockImplementationOnce(() => new Promise((_resolve, reject) => { rejectFirst = reject; }))
      .mockImplementationOnce(() => new Promise((resolve) => { resolveLast = resolve; })));
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
    vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    initialisePageNavigation();
    document.querySelector<HTMLAnchorElement>('a[href="/two/"]')!.click();
    document.querySelector<HTMLAnchorElement>('a[href="/three/"]')!.click();
    rejectFirst(new TypeError("Network cancelled"));
    await Promise.resolve();
    expect(assign).not.toHaveBeenCalled();
    expect(document.activeElement).not.toBe(document.querySelector("main"));
    resolveLast(new Response('<html><head><meta data-page-csp content="default-src self"></head><body class="theme-docs"><nav data-docs-navigation></nav><main data-docs-main tabindex="-1">Three</main></body></html>', { headers: { "Content-Type": "text/html" } }));
    await vi.waitFor(() => expect(document.querySelector("main")?.textContent).toBe("Three"));
    expect(document.activeElement).toBe(document.querySelector("main"));
    expect(assign).not.toHaveBeenCalled();
  });

  it("uses a full navigation when a destination changes the locale of global controls", async () => {
    document.head.innerHTML = '<meta data-page-csp content="frame-src \'self\'">';
    document.documentElement.lang = "en";
    document.body.className = "theme-docs";
    document.body.innerHTML = `
      <aside class="docs-sidebar"><nav data-docs-navigation>
        <a href="/zh-CN/docs/next/">中文文档</a>
      </nav></aside>
      <main id="main-content" data-docs-main>English document</main>
      <button data-back-to-top aria-label="Back to top" title="Back to top" hidden></button>`;
    const source = `<!doctype html><html lang="zh-CN"><head>
      <meta data-page-csp content="frame-src 'self'">
      </head><body class="theme-docs">
      <nav data-docs-navigation></nav>
      <main id="main-content" data-docs-main tabindex="-1">中文内容</main>
      <button data-back-to-top aria-label="回到顶部" title="回到顶部" hidden></button>
      </body></html>`;
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(source, {
      headers: { "Content-Type": "text/html" }
    })));
    vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    const assign = vi.spyOn(window.location, "assign").mockImplementation(() => {});
    initialisePageNavigation();
    document.querySelector<HTMLAnchorElement>("a")!.click();

    await vi.waitFor(() => {
      expect(assign).toHaveBeenCalledWith(new URL('/zh-CN/docs/next/', originalUrl).href);
      expect(document.documentElement.lang).toBe("en");
      expect(document.querySelector("[data-docs-main]")?.textContent).toBe("English document");
    });
  });
});
