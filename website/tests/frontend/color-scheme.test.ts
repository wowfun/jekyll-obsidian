import { afterEach, expect, it } from "vitest";
import { applyColorScheme } from "../../src/frontend/color-scheme";

afterEach(() => { document.body.replaceChildren(); delete document.documentElement.dataset.colorScheme; });

it("keeps the icon control's accessible name and hover hint in sync with its action", () => {
  document.body.innerHTML = '<button data-color-scheme-toggle data-scheme-use-light="使用浅色配色" data-scheme-use-dark="使用深色配色"><svg aria-hidden="true"></svg><span class="visually-hidden" data-color-scheme-label></span></button>';
  const button = document.querySelector<HTMLButtonElement>("button")!;
  applyColorScheme("dark");
  expect(button.getAttribute("aria-label")).toBe("使用浅色配色");
  expect(button.title).toBe("使用浅色配色");
  expect(button.getAttribute("aria-pressed")).toBe("true");
  applyColorScheme("light");
  expect(button.title).toBe("使用深色配色");
  expect(button.getAttribute("aria-pressed")).toBe("false");
});
