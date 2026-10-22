import { expect, it, vi } from "vitest";

const state = vi.hoisted(() => ({ cleanup: vi.fn(), fail: true }));
vi.mock("../../src/frontend/outline", () => ({ initialiseOutline: () => state.cleanup }));
vi.mock("../../src/frontend/recommendations", () => ({ initialiseRecommendations: () => {
  if (state.fail) throw new Error("initializer failed");
  return () => undefined;
} }));
import { initialiseWebsite } from "../../src/frontend/main";

it("cleans earlier features immediately after an initializer fails and can retry", () => {
  expect(() => initialiseWebsite()).toThrow("initializer failed");
  expect(state.cleanup).toHaveBeenCalledTimes(1);
  state.fail = false;
  expect(() => initialiseWebsite()).not.toThrow();
  expect(state.cleanup).toHaveBeenCalledTimes(1);
  document.dispatchEvent(new CustomEvent("website:docs-page-change"));
  expect(state.cleanup).toHaveBeenCalledTimes(2);
});
