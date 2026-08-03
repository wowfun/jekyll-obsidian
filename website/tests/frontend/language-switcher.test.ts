import { beforeEach, describe, expect, it } from "vitest";
import { initialiseLanguageSwitcher } from "../../src/frontend/language-switcher";

describe("language switcher", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <details data-language-switcher open>
        <summary tabindex="0">简体中文</summary>
        <a href="/en/">English</a>
      </details>
      <button id="outside">Outside</button>
    `;
    initialiseLanguageSwitcher();
  });

  it("closes on Escape and returns focus to the summary", () => {
    const details = document.querySelector<HTMLDetailsElement>("details")!;
    const link = document.querySelector<HTMLAnchorElement>("a")!;
    link.focus();
    link.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));

    expect(details.open).toBe(false);
    expect(document.activeElement).toBe(document.querySelector("summary"));
  });

  it("closes after an outside click", () => {
    const details = document.querySelector<HTMLDetailsElement>("details")!;
    document.querySelector<HTMLButtonElement>("#outside")!.click();
    expect(details.open).toBe(false);
  });
});
