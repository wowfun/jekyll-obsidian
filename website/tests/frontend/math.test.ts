// @vitest-environment happy-dom

import { beforeEach, describe, expect, it } from "vitest";
import { renderMath } from "../../src/frontend/math";

describe("MathJax source copy", () => {
  beforeEach(() => {
    document.documentElement.lang = "en";
    document.documentElement.dir = "ltr";
    document.body.innerHTML = `
      <div class="note-content" data-copy-formula-label="Copy formula source">
        <span data-math-style="inline">e^{i\\pi}+1=0</span>
        <span data-math-style="display">\\operatorname{arg\\,max}_{x &lt; y} f(x)</span>
      </div>`;
  });

  it("preserves exact inline and display TeX before replacing rendered contents", async () => {
    const expected = [String.raw`e^{i\pi}+1=0`, String.raw`\operatorname{arg\,max}_{x < y} f(x)`];

    await renderMath();

    const formulas = Array.from(document.querySelectorAll<HTMLElement>("[data-math-rendered]"));
    expect(formulas).toHaveLength(2);
    expect(formulas.map((element) => element
      .querySelector<HTMLTemplateElement>("template[data-website-copy-source]")?.content.textContent))
      .toEqual(expected);
    expect(formulas.map((element) => element
      .querySelector("button[data-copy-source]")?.getAttribute("aria-label")))
      .toEqual(["Copy formula source", "Copy formula source"]);
    expect(formulas[0]?.querySelectorAll("button[data-copy-source]")).toHaveLength(1);
    expect(formulas[1]?.querySelectorAll("button[data-copy-source]")).toHaveLength(1);
  });
});
