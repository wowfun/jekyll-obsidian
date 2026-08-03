import { beforeEach, describe, expect, it } from "vitest";
import {
  applyColorScheme,
  COLOR_SCHEME_STORAGE_KEY,
  preferredColorScheme
} from "../../src/frontend/color-scheme";

describe("color scheme controls", () => {
  beforeEach(() => {
    document.body.replaceChildren();
    document.documentElement.removeAttribute("data-color-scheme");
  });

  it("uses a saved preference before the operating-system preference", () => {
    let requestedKey = "";
    expect(
      preferredColorScheme(
        { getItem: (key) => ((requestedKey = key), "light") },
        { matches: true }
      )
    ).toBe("light");
    expect(requestedKey).toBe(COLOR_SCHEME_STORAGE_KEY);
    expect(COLOR_SCHEME_STORAGE_KEY).toBe("website:color-scheme");
    expect(preferredColorScheme({ getItem: () => null }, { matches: true })).toBe("dark");
    expect(preferredColorScheme({ getItem: () => { throw new Error("blocked"); } }, { matches: false })).toBe("light");
  });

  it("updates the document and accessible toggle label", () => {
    const button = document.createElement("button");
    button.dataset.colorSchemeToggle = "";
    const label = document.createElement("span");
    label.dataset.colorSchemeLabel = "";
    button.append(label);
    document.body.append(button);

    applyColorScheme("dark");

    expect(document.documentElement.dataset.colorScheme).toBe("dark");
    expect(button.getAttribute("aria-pressed")).toBe("true");
    expect(button.getAttribute("aria-label")).toBe("Use light color scheme");
    expect(label.textContent).toBe("Light");
  });

  it("uses locale catalog labels supplied by the page", () => {
    const button = document.createElement("button");
    button.dataset.colorSchemeToggle = "";
    button.dataset.schemeUseLight = "使用浅色配色";
    button.dataset.schemeLight = "浅色";
    const label = document.createElement("span");
    label.dataset.colorSchemeLabel = "";
    button.append(label);
    document.body.append(button);

    applyColorScheme("dark");

    expect(button.getAttribute("aria-label")).toBe("使用浅色配色");
    expect(label.textContent).toBe("浅色");
  });
});
