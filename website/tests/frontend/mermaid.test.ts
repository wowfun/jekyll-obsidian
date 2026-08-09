import { beforeEach, describe, expect, it, vi } from "vitest";
import { COLOR_SCHEME_EVENT } from "../../src/frontend/color-scheme";

const mermaidOutput = vi.hoisted(() => ({
  svg: '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
}));
const mermaid = vi.hoisted(() => ({
  initialize: vi.fn(),
  render: vi.fn(async () => ({ svg: mermaidOutput.svg }))
}));

vi.mock("mermaid", () => ({ default: mermaid }));

import { renderMermaid } from "../../src/frontend/mermaid";

describe("localized Mermaid diagrams", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <div class="note-content" data-copy-diagram-label="复制图表源码">
        <pre data-website-mermaid data-diagram-label="图表"><code class="language-mermaid">graph TD; A--&gt;B</code></pre>
      </div>`;
    mermaidOutput.svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
    mermaid.initialize.mockClear();
    mermaid.render.mockClear();
  });

  it("accepts Mermaid SVG HTML containing a foreignObject line break", async () => {
    mermaidOutput.svg = `
      <svg xmlns="http://www.w3.org/2000/svg">
        <foreignObject>
          <div xmlns="http://www.w3.org/1999/xhtml"><p>First<br>Second</p></div>
        </foreignObject>
      </svg>`;

    await renderMermaid();

    expect(document.querySelector("pre[data-mermaid-error]")).toBeNull();
    expect(document.querySelectorAll(".mermaid-diagram > svg foreignObject br")).toHaveLength(1);
  });

  it("waits for document fonts before Mermaid measures diagram labels", async () => {
    const originalFonts = document.fonts;
    let resolveFonts: () => void = () => {};
    const ready = new Promise<void>((resolve) => {
      resolveFonts = resolve;
    });
    Object.defineProperty(document, "fonts", {
      configurable: true,
      value: { ready }
    });

    try {
      const rendering = renderMermaid();
      await Promise.resolve();

      expect(mermaid.initialize).not.toHaveBeenCalled();
      expect(mermaid.render).not.toHaveBeenCalled();

      resolveFonts();
      await rendering;
      expect(mermaid.render).toHaveBeenCalledOnce();
    } finally {
      Object.defineProperty(document, "fonts", {
        configurable: true,
        value: originalFonts
      });
    }
  });

  it("uses the inherited body font size for Mermaid label measurement", async () => {
    document.body.style.fontSize = "17px";

    try {
      await renderMermaid();

      expect(mermaid.initialize).toHaveBeenCalledWith(expect.objectContaining({
        themeVariables: expect.objectContaining({ fontSize: "17px" })
      }));
    } finally {
      document.body.style.removeProperty("font-size");
    }
  });

  it.each([
    ["multiple roots", '<svg xmlns="http://www.w3.org/2000/svg"></svg><svg xmlns="http://www.w3.org/2000/svg"></svg>'],
    ["a non-SVG root", '<div><svg xmlns="http://www.w3.org/2000/svg"></svg></div>']
  ])("rejects Mermaid output with %s", async (_label, markup) => {
    mermaidOutput.svg = markup;

    await renderMermaid();

    expect(document.querySelector("pre[data-mermaid-error]")).not.toBeNull();
    expect(document.querySelector(".mermaid-diagram")).toBeNull();
  });

  it("preserves the localized accessible label across color-scheme redraws", async () => {
    await renderMermaid();
    expect(document.querySelector(".mermaid-diagram > svg")?.getAttribute("aria-label")).toBe("图表");
    expect(document.querySelector(".mermaid-diagram button[data-copy-source]")?.getAttribute("aria-label"))
      .toBe("复制图表源码");
    expect(document.querySelector<HTMLTemplateElement>(".mermaid-diagram template[data-website-copy-source]")
      ?.content.textContent).toBe("graph TD; A-->B");

    document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme: "dark" } }));

    await vi.waitFor(() => expect(mermaid.render).toHaveBeenCalledTimes(2));
    expect(document.querySelector(".mermaid-diagram > svg")?.getAttribute("aria-label")).toBe("图表");
    expect(document.querySelectorAll(".mermaid-diagram button[data-copy-source]")).toHaveLength(1);
    expect(document.querySelector<HTMLTemplateElement>(".mermaid-diagram template[data-website-copy-source]")
      ?.content.textContent).toBe("graph TD; A-->B");
  });
});
