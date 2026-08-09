// @vitest-environment happy-dom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { initialiseAutoHideScrollbars } from "../../src/frontend/scrollbars";

describe("auto-hiding scrollbars", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    document.documentElement.setAttribute("data-auto-hide-root-scrollbar", "");
    document.body.innerHTML = '<aside data-auto-hide-scrollbar></aside>';
  });

  afterEach(() => {
    vi.useRealTimers();
    document.documentElement.removeAttribute("data-auto-hide-root-scrollbar");
    document.documentElement.removeAttribute("data-scrollbar-active");
    document.body.replaceChildren();
  });

  it("reveals each managed scrollbar during activity and hides it after idle", () => {
    const chronology = document.querySelector<HTMLElement>("[data-auto-hide-scrollbar]")!;
    const cleanup = initialiseAutoHideScrollbars();

    expect(document.documentElement.dataset.scrollbarActive).toBe("true");
    expect(chronology.dataset.scrollbarActive).toBe("true");
    vi.advanceTimersByTime(1_500);
    expect(document.documentElement.dataset.scrollbarActive).toBeUndefined();
    expect(chronology.dataset.scrollbarActive).toBeUndefined();

    window.dispatchEvent(new Event("scroll"));
    expect(document.documentElement.dataset.scrollbarActive).toBe("true");
    chronology.dispatchEvent(new Event("pointermove"));
    expect(chronology.dataset.scrollbarActive).toBe("true");
    vi.advanceTimersByTime(1_500);
    expect(chronology.dataset.scrollbarActive).toBeUndefined();
    chronology.dispatchEvent(new FocusEvent("focusin", { bubbles: true }));
    expect(chronology.dataset.scrollbarActive).toBe("true");
    vi.advanceTimersByTime(1_500);
    expect(chronology.dataset.scrollbarActive).toBeUndefined();
    chronology.dispatchEvent(new Event("scroll"));
    expect(chronology.dataset.scrollbarActive).toBe("true");
    vi.advanceTimersByTime(1_500);
    expect(document.documentElement.dataset.scrollbarActive).toBeUndefined();
    expect(chronology.dataset.scrollbarActive).toBeUndefined();

    cleanup();
  });

  it("replaces prior listeners and clears visible state on cleanup", () => {
    const chronology = document.querySelector<HTMLElement>("[data-auto-hide-scrollbar]")!;
    initialiseAutoHideScrollbars();
    const cleanup = initialiseAutoHideScrollbars();
    vi.advanceTimersByTime(1_500);

    cleanup();
    window.dispatchEvent(new Event("scroll"));
    chronology.dispatchEvent(new Event("scroll"));
    expect(document.documentElement.dataset.scrollbarActive).toBeUndefined();
    expect(chronology.dataset.scrollbarActive).toBeUndefined();
  });
});
