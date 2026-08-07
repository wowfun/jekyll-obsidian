import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { initialiseAnalytics } from "../../src/frontend/analytics";
import { initialiseWebsite } from "../../src/frontend/main";

function installAnalytics(provider: string, identifier: string): void {
  const meta = document.createElement("meta");
  meta.name = "website:analytics";
  meta.dataset.provider = provider;
  meta.content = identifier;
  document.head.append(meta);
}

describe("website analytics", () => {
  beforeEach(() => {
    document.head.querySelectorAll("meta[name='website:analytics'], script[data-website-analytics]")
      .forEach((node) => node.remove());
    document.body.replaceChildren();
    delete window.dataLayer;
    delete window.gtag;
    vi.stubGlobal("localStorage", {
      getItem: () => null,
      setItem: () => undefined
    });

    const append = document.head.append.bind(document.head);
    vi.spyOn(document.head, "append").mockImplementation((...nodes: (Node | string)[]) => {
      const scripts = nodes.filter((node): node is HTMLScriptElement => node instanceof HTMLScriptElement);
      const types = scripts.map((script) => script.type);
      scripts.forEach((script) => { script.type = "application/json"; });
      append(...nodes);
      scripts.forEach((script, index) => { script.type = types[index]!; });
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("stays off without complete compiler-authored metadata", () => {
    expect(() => initialiseAnalytics()).not.toThrow();

    document.head.insertAdjacentHTML(
      "beforeend",
      '<meta name="website:analytics" data-provider="unknown" content="example">'
    );
    expect(() => initialiseAnalytics()).not.toThrow();
    expect(document.querySelector("script[data-website-analytics]")).toBeNull();
  });

  it("loads one Cloudflare beacon from validated metadata", () => {
    installAnalytics("cloudflare", "0123456789abcdef0123456789abcdef");

    initialiseAnalytics();
    initialiseAnalytics();

    const scripts = document.querySelectorAll<HTMLScriptElement>(
      'script[data-website-analytics="cloudflare"]'
    );
    expect(scripts).toHaveLength(1);
    expect(scripts[0]!.src).toBe("https://static.cloudflareinsights.com/beacon.min.js");
    expect(scripts[0]!.defer).toBe(true);
    expect(JSON.parse(scripts[0]!.dataset.cfBeacon!)).toEqual({
      token: "0123456789abcdef0123456789abcdef"
    });
  });

  it("configures Google once and loads one asynchronous client", () => {
    installAnalytics("google", "G-ABCDEF1234");

    initialiseAnalytics();
    initialiseAnalytics();

    const scripts = document.querySelectorAll<HTMLScriptElement>(
      'script[data-website-analytics="google"]'
    );
    expect(scripts).toHaveLength(1);
    expect(scripts[0]!.src).toBe(
      "https://www.googletagmanager.com/gtag/js?id=G-ABCDEF1234"
    );
    expect(scripts[0]!.async).toBe(true);

    const commands = window.dataLayer!.map((entry) =>
      Array.from(entry as ArrayLike<unknown>)
    );
    expect(commands).toHaveLength(2);
    expect(commands[0]![0]).toBe("js");
    expect(commands[0]![1]).toBeInstanceOf(Date);
    expect(commands[1]).toEqual(["config", "G-ABCDEF1234"]);
  });

  it("does not reinject analytics across website starts or Docs page changes", () => {
    installAnalytics("google", "G-ABCDEF1234");

    initialiseWebsite();
    initialiseWebsite();
    const script = document.querySelector<HTMLScriptElement>(
      'script[data-website-analytics="google"]'
    );
    expect(script).not.toBeNull();
    expect(() => script!.dispatchEvent(new Event("error"))).not.toThrow();

    document.dispatchEvent(new CustomEvent("website:docs-page-change"));
    initialiseWebsite();

    expect(document.querySelectorAll("script[data-website-analytics]")).toHaveLength(1);
    expect(window.dataLayer).toHaveLength(2);
  });
});
