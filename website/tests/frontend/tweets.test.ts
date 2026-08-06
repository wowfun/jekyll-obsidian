import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { COLOR_SCHEME_EVENT } from "../../src/frontend/color-scheme";
import { initialiseTweets, resetTweetLoaderForTests } from "../../src/frontend/tweets";

class ObserverStub {
  static instances: ObserverStub[] = [];
  callback: IntersectionObserverCallback;
  observe = vi.fn();
  disconnect = vi.fn();

  constructor(callback: IntersectionObserverCallback) {
    this.callback = callback;
    ObserverStub.instances.push(this);
  }

  intersect(target: Element): void {
    this.callback([{ isIntersecting: true, target } as IntersectionObserverEntry], this as unknown as IntersectionObserver);
  }
}

function installTweet(): HTMLElement {
  document.body.innerHTML = `
    <figure data-website-tweet="1580548874246443010">
      <div data-website-tweet-mount></div>
      <a data-website-tweet-fallback href="https://x.com/obsdmd/status/1580548874246443010">View post on X</a>
    </figure>`;
  return document.querySelector<HTMLElement>("[data-website-tweet]")!;
}

type CreateTweet = (
  id: string,
  target: HTMLElement,
  options: { dnt: true; theme: "light" | "dark" }
) => Promise<HTMLElement | undefined>;

async function loadWidget(createTweet: CreateTweet, script: HTMLScriptElement): Promise<HTMLScriptElement> {
  window.twttr = { widgets: { createTweet } };
  script.dispatchEvent(new Event("load"));
  await Promise.resolve();
  return script;
}

describe("X post embeds", () => {
  let appendedScript: HTMLScriptElement | undefined;
  let cleanup: (() => void) | undefined;

  beforeEach(() => {
    appendedScript = undefined;
    cleanup = undefined;
    document.head.querySelectorAll("script[data-website-x-widgets]").forEach((node) => node.remove());
    document.body.replaceChildren();
    document.documentElement.dataset.colorScheme = "dark";
    delete window.twttr;
    ObserverStub.instances = [];
    resetTweetLoaderForTests();
    vi.stubGlobal("IntersectionObserver", ObserverStub);
    const append = document.head.append.bind(document.head);
    vi.spyOn(document.head, "append").mockImplementation((...nodes: (Node | string)[]) => {
      appendedScript = nodes[0] as HTMLScriptElement;
      appendedScript.type = "application/json";
      append(...nodes);
    });
  });

  afterEach(() => {
    cleanup?.();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("waits for the viewport and loads one DNT widget", async () => {
    const section = installTweet();
    cleanup = initialiseTweets();
    expect(appendedScript).toBeUndefined();

    ObserverStub.instances[0]!.intersect(section);
    const createTweet = vi.fn<CreateTweet>().mockResolvedValue(document.createElement("iframe"));
    const script = await loadWidget(createTweet, appendedScript!);

    await vi.waitFor(() => expect(createTweet).toHaveBeenCalledWith(
      "1580548874246443010",
      section.querySelector("[data-website-tweet-mount]"),
      { dnt: true, theme: "dark" }
    ));
    expect(script.src).toBe("https://platform.twitter.com/widgets.js");
    expect(section.querySelector<HTMLElement>("[data-website-tweet-fallback]")!.hidden).toBe(true);
  });

  it("rebuilds a ready widget after a theme change", async () => {
    const section = installTweet();
    cleanup = initialiseTweets();
    ObserverStub.instances[0]!.intersect(section);
    const createTweet = vi.fn<CreateTweet>().mockResolvedValue(document.createElement("iframe"));
    await loadWidget(createTweet, appendedScript!);
    await vi.waitFor(() => expect(section.dataset.websiteTweetState).toBe("ready"));

    document.documentElement.dataset.colorScheme = "light";
    document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme: "light" } }));
    await vi.waitFor(() => expect(createTweet).toHaveBeenLastCalledWith(
      "1580548874246443010",
      section.querySelector("[data-website-tweet-mount]"),
      { dnt: true, theme: "light" }
    ));
    await vi.waitFor(() => expect(section.dataset.websiteTweetState).toBe("ready"));
  });

  it("applies a theme change that arrives during the first render", async () => {
    const section = installTweet();
    cleanup = initialiseTweets();
    ObserverStub.instances[0]!.intersect(section);
    let finishFirst: ((value: HTMLElement) => void) | undefined;
    const first = new Promise<HTMLElement>((resolve) => { finishFirst = resolve; });
    const createTweet = vi.fn<CreateTweet>()
      .mockImplementationOnce(() => first)
      .mockResolvedValue(document.createElement("iframe"));
    await loadWidget(createTweet, appendedScript!);
    await vi.waitFor(() => expect(createTweet).toHaveBeenCalledTimes(1));

    document.documentElement.dataset.colorScheme = "light";
    document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme: "light" } }));
    finishFirst!(document.createElement("iframe"));

    await vi.waitFor(() => expect(createTweet).toHaveBeenCalledTimes(2));
    expect(createTweet).toHaveBeenLastCalledWith(
      "1580548874246443010",
      section.querySelector("[data-website-tweet-mount]"),
      { dnt: true, theme: "light" }
    );
  });

  it("keeps the fallback when X cannot render the post", async () => {
    const section = installTweet();
    cleanup = initialiseTweets();
    ObserverStub.instances[0]!.intersect(section);
    const createTweet = vi.fn<CreateTweet>().mockRejectedValue(new Error("blocked"));
    await loadWidget(createTweet, appendedScript!);

    await vi.waitFor(() => expect(section.dataset.websiteTweetState).toBe("unavailable"));
    expect(section.querySelector<HTMLElement>("[data-website-tweet-fallback]")!.hidden).toBe(false);
  });

  it("loads a fresh script after an earlier widgets request fails", async () => {
    let section = installTweet();
    cleanup = initialiseTweets();
    ObserverStub.instances.at(-1)!.intersect(section);
    const failedScript = appendedScript!;
    failedScript.dispatchEvent(new Event("error"));
    await vi.waitFor(() => expect(section.dataset.websiteTweetState).toBe("unavailable"));
    expect(failedScript.isConnected).toBe(false);

    cleanup();
    section = installTweet();
    cleanup = initialiseTweets();
    ObserverStub.instances.at(-1)!.intersect(section);
    const retryScript = appendedScript!;
    expect(retryScript).not.toBe(failedScript);

    const createTweet = vi.fn<CreateTweet>().mockResolvedValue(document.createElement("iframe"));
    await loadWidget(createTweet, retryScript);
    await vi.waitFor(() => expect(section.dataset.websiteTweetState).toBe("ready"));
    expect(createTweet).toHaveBeenCalledWith(
      "1580548874246443010",
      section.querySelector("[data-website-tweet-mount]"),
      { dnt: true, theme: "dark" }
    );
  });
});
