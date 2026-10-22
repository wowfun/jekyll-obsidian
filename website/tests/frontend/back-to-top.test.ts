import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { initialiseBackToTop } from "../../src/frontend/back-to-top";

describe("back to top", () => {
  let cleanup = () => {};
  let scroll = 0;
  let height = 800;
  let reducedMotion = false;
  let pending: Map<number, FrameRequestCallback>;
  let nextFrame = 0;

  const button = () => document.querySelector<HTMLButtonElement>("[data-back-to-top]")!;
  const flushFrame = () => {
    const callbacks = [...pending.values()];
    pending.clear();
    callbacks.forEach((callback) => callback(0));
  };
  const activity = (type: string) => {
    window.dispatchEvent(new Event(type));
    flushFrame();
  };

  beforeEach(() => {
    scroll = 0;
    height = 800;
    reducedMotion = false;
    pending = new Map();
    document.body.innerHTML = '<main id="main-content" tabindex="-1"></main><button data-back-to-top hidden>Top</button>';
    vi.spyOn(window, "scrollY", "get").mockImplementation(() => scroll);
    vi.spyOn(window, "innerHeight", "get").mockImplementation(() => height);
    vi.spyOn(window, "requestAnimationFrame").mockImplementation((callback) => {
      pending.set(++nextFrame, callback);
      return nextFrame;
    });
    vi.spyOn(window, "cancelAnimationFrame").mockImplementation((id) => { pending.delete(id); });
    vi.spyOn(window, "scrollTo").mockImplementation(() => {});
    vi.spyOn(window, "matchMedia").mockImplementation(() => ({ matches: reducedMotion }) as MediaQueryList);
  });

  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    document.body.replaceChildren();
  });

  it("is hidden through exactly one viewport and re-hides when returning to it", () => {
    cleanup = initialiseBackToTop();
    expect(button().hidden).toBe(true);
    for (const [position, hidden] of [[799, true], [800, true], [801, false], [800, true], [0, true]] as const) {
      scroll = position;
      activity("scroll");
      expect(button().hidden).toBe(hidden);
    }
  });

  it("checks initial position, resized viewports, and restored pages", () => {
    scroll = 900;
    cleanup = initialiseBackToTop();
    expect(button().hidden).toBe(false);
    height = 1_000;
    activity("resize");
    expect(button().hidden).toBe(true);
    scroll = 1_200;
    activity("pageshow");
    expect(button().hidden).toBe(false);
  });

  it("only mutates visibility when crossing the viewport threshold", () => {
    const observer = new MutationObserver(() => {});
    observer.observe(button(), { attributes: true, attributeFilter: ["hidden"] });
    try {
      cleanup = initialiseBackToTop();
      for (scroll = 0; scroll <= height; scroll += 100) activity("scroll");
      expect(observer.takeRecords()).toHaveLength(0);
      scroll = height + 1;
      activity("scroll");
      expect(observer.takeRecords()).toHaveLength(1);
      for (scroll = 900; scroll <= 1_500; scroll += 100) activity("scroll");
      activity("resize");
      activity("pageshow");
      expect(observer.takeRecords()).toHaveLength(0);
      scroll = 0;
      activity("scroll");
      expect(observer.takeRecords()).toHaveLength(1);
    } finally {
      observer.disconnect();
    }
  });

  it("coalesces scroll events and cancels queued updates and listeners on cleanup", () => {
    cleanup = initialiseBackToTop();
    scroll = 900;
    for (let i = 0; i < 5; i++) window.dispatchEvent(new Event("scroll"));
    expect(pending.size).toBe(1);
    expect(button().hidden).toBe(true);
    cleanup();
    flushFrame();
    activity("scroll");
    activity("resize");
    activity("pageshow");
    button().click();
    expect(pending.size).toBe(0);
    expect(button().hidden).toBe(true);
    expect(window.scrollTo).not.toHaveBeenCalled();
  });

  it("replaces previous controllers instead of accumulating listeners", () => {
    initialiseBackToTop();
    window.dispatchEvent(new Event("scroll"));
    cleanup = initialiseBackToTop();
    expect(pending.size).toBe(0);
    button().click();
    expect(window.scrollTo).toHaveBeenCalledTimes(1);
    window.dispatchEvent(new Event("scroll"));
    expect(pending.size).toBe(1);
  });

  it.each([false, true])("focuses main without scrolling and respects reduced motion: %s", (reduce) => {
    reducedMotion = reduce;
    cleanup = initialiseBackToTop();
    const main = document.getElementById("main-content")!;
    const focus = vi.spyOn(main, "focus");
    const url = window.location.href;
    const historyLength = window.history.length;
    button().click();
    expect(focus).toHaveBeenCalledWith({ preventScroll: true });
    expect(document.activeElement).toBe(main);
    expect(window.scrollTo).toHaveBeenCalledWith({ top: 0, left: 0, behavior: reduce ? "instant" : "smooth" });
    expect(focus.mock.invocationCallOrder[0]).toBeLessThan(vi.mocked(window.scrollTo).mock.invocationCallOrder[0]!);
    expect(window.location.href).toBe(url);
    expect(window.history.length).toBe(historyLength);
  });

  it("releases the old button when a page replaces its markup", () => {
    initialiseBackToTop();
    const previous = button();
    previous.outerHTML = '<button data-back-to-top hidden>回到顶部</button>';
    scroll = 900;
    cleanup = initialiseBackToTop();
    previous.click();
    expect(window.scrollTo).not.toHaveBeenCalled();
    expect(button().hidden).toBe(false);
    button().click();
    expect(window.scrollTo).toHaveBeenCalledTimes(1);
  });

  it("does nothing when the page has no button", () => {
    document.body.replaceChildren();
    cleanup = initialiseBackToTop();
    activity("scroll");
    expect(window.requestAnimationFrame).not.toHaveBeenCalled();
  });
});
