// @vitest-environment happy-dom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { initialiseDocsNavigation, sameContentSecurityPolicy } from "../../src/frontend/docs-navigation";

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
    initialiseDocsNavigation();
    document.head.replaceChildren();
    document.body.className = "";
    document.documentElement.lang = originalLanguage;
    document.documentElement.dir = originalDirection;
    window.history.replaceState(null, "", originalUrl);
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it("refreshes localized button labels when a same-origin document link changes language", async () => {
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
      <main id="main-content" data-docs-main>中文内容</main>
      <button data-back-to-top aria-label="回到顶部" title="回到顶部" hidden></button>
      </body></html>`;
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(source, {
      headers: { "Content-Type": "text/html" }
    })));
    vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    initialiseDocsNavigation();
    document.querySelector<HTMLAnchorElement>("a")!.click();

    await vi.waitFor(() => {
      expect(document.documentElement.lang).toBe("zh-CN");
      expect(document.querySelector("[data-docs-main]")?.textContent).toBe("中文内容");
      expect(document.querySelectorAll("[data-back-to-top]")).toHaveLength(1);
      const button = document.querySelector("[data-back-to-top]")!;
      expect(button.getAttribute("aria-label")).toBe("回到顶部");
      expect(button.getAttribute("title")).toBe("回到顶部");
    });
  });
});
