import { afterEach, expect, it, vi } from "vitest";
import { initialiseRecommendations } from "../../src/frontend/recommendations";

afterEach(() => { vi.useRealTimers(); document.body.innerHTML = ""; });

it("reveals valid cards, expires them without a reload, and cleans up timers", () => {
  vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-15T00:00:00Z"));
  document.body.innerHTML = '<nav data-recommendations hidden><article data-recommendation-expires-at="2026-10-15T00:00:01Z"></article><article data-recommendation-expires-at="2026-10-14T00:00:00Z"></article></nav>';
  const cleanup = initialiseRecommendations();
  const nav = document.querySelector("nav")!;
  expect(nav.hidden).toBe(false); expect(nav.children).toHaveLength(1);
  vi.advanceTimersByTime(1001);
  expect(nav.hidden).toBe(true); expect(nav.children).toHaveLength(0);
  cleanup(); expect(vi.getTimerCount()).toBe(0);
});

it("rechecks on restored pages and rejects invalid expiry", () => {
  vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-15T00:00:00Z"));
  document.body.innerHTML = '<nav data-recommendations hidden><article data-recommendation-expires-at="2026-10-16T00:00:00Z"></article><article data-recommendation-expires-at="bad"></article></nav>';
  const cleanup = initialiseRecommendations();
  vi.setSystemTime(new Date("2026-10-17T00:00:00Z")); window.dispatchEvent(new Event("pageshow"));
  expect(document.querySelector("nav")!.hidden).toBe(true); cleanup();
});
