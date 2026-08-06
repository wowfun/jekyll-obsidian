// @vitest-environment happy-dom

import { beforeEach, describe, expect, it } from "vitest";

import { sameContentSecurityPolicy } from "../../src/frontend/docs-navigation";

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
