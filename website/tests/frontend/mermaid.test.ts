import { beforeEach, describe, expect, it, vi } from "vitest";
import { COLOR_SCHEME_EVENT } from "../../src/frontend/color-scheme";

const mermaid = vi.hoisted(() => ({
  initialize: vi.fn(),
  render: vi.fn(async () => ({
    svg: '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
  }))
}));

vi.mock("mermaid", () => ({ default: mermaid }));

import { renderMermaid } from "../../src/frontend/mermaid";

describe("localized Mermaid diagrams", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <pre data-website-mermaid data-diagram-label="图表">
        <code class="language-mermaid">graph TD; A--&gt;B</code>
      </pre>`;
    mermaid.initialize.mockClear();
    mermaid.render.mockClear();
  });

  it("preserves the localized accessible label across color-scheme redraws", async () => {
    await renderMermaid();
    expect(document.querySelector(".mermaid-diagram svg")?.getAttribute("aria-label")).toBe("图表");

    document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme: "dark" } }));

    await vi.waitFor(() => expect(mermaid.render).toHaveBeenCalledTimes(2));
    expect(document.querySelector(".mermaid-diagram svg")?.getAttribute("aria-label")).toBe("图表");
  });
});
