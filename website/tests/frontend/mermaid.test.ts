import { beforeEach, describe, expect, it, vi } from "vitest";
import { COLOR_SCHEME_EVENT } from "../../src/frontend/color-scheme";

const mermaidOutput = vi.hoisted(() => ({
  svg: '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
}));
const mermaid = vi.hoisted(() => ({
  initialize: vi.fn(),
  render: vi.fn(async (_id?: string, _code?: string) => ({ svg: mermaidOutput.svg }))
}));

vi.mock("mermaid", () => ({ default: mermaid }));

import { renderMermaid } from "../../src/frontend/mermaid";
import { initialiseDialogs } from "../../src/frontend/dialogs";
import { initialiseMediaViewerControls } from "../../src/frontend/media-viewer";

describe("localized Mermaid diagrams", () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <div id="website-media-1-clip"></div>
      <div class="note-content" data-copy-diagram-label="复制图表源码" data-expand-diagram-label="放大图表" data-close-diagram-label="关闭图表">
        <pre data-website-mermaid data-diagram-label="图表"><code class="language-mermaid">graph TD; A--&gt;B</code></pre>
      </div>
      <dialog data-dialog="media" data-media-zoom-level="缩放：{percent}%">
        <h2 data-media-dialog-title></h2>
        <button data-dialog-close>关闭</button>
        <button data-media-zoom-out>缩小</button>
        <button data-media-zoom-reset>复位</button>
        <button data-media-zoom-in>放大</button>
        <output data-media-zoom-status aria-live="polite"></output>
        <div data-media-dialog-viewport role="group"><div data-media-dialog-canvas></div></div>
      </dialog>`;
    HTMLDialogElement.prototype.showModal = function showModal() { this.open = true; };
    HTMLDialogElement.prototype.close = function close() {
      this.open = false;
      this.dispatchEvent(new Event("close"));
    };
    mermaidOutput.svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
    mermaid.initialize.mockClear();
    mermaid.render.mockClear();
    mermaid.render.mockImplementation(async () => ({ svg: mermaidOutput.svg }));
    initialiseMediaViewerControls();
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

  it("opens an accessible clone of the current diagram without rendering Mermaid again", async () => {
    mermaidOutput.svg = '<svg xmlns="http://www.w3.org/2000/svg" id="diagram"><g id="clip"></g><g class="node" clip-path="url(#clip)"></g></svg>';
    initialiseDialogs();
    await renderMermaid();

    const figure = document.querySelector<HTMLElement>(".mermaid-diagram")!;
    const sourceSvg = figure.querySelector<SVGSVGElement>(":scope > svg")!;
    const expand = figure.querySelector<HTMLButtonElement>("button[data-mermaid-expand]")!;
    expect(expand.getAttribute("aria-label")).toBe("放大图表");

    expand.click();

    const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]')!;
    const enlarged = dialog.querySelector<SVGSVGElement>("[data-media-dialog-canvas] > svg")!;
    const sourceClip = sourceSvg.querySelector<SVGElement>("[id]")!;
    const enlargedClip = enlarged.querySelector<SVGElement>("[id]")!;
    expect(dialog.open).toBe(true);
    expect(enlarged).not.toBe(sourceSvg);
    expect(enlarged.id).not.toBe(sourceSvg.id);
    expect(enlargedClip.id).not.toBe(sourceClip.id);
    expect(enlarged.querySelector("g.node")?.getAttribute("clip-path"))
      .toBe(`url(#${enlargedClip.id})`);
    const ids = Array.from(document.querySelectorAll<SVGElement>("svg[id], svg [id]"), (element) => element.id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(mermaid.render).toHaveBeenCalledOnce();
  });

  it("bounds zoom controls and reports the current magnification", async () => {
    initialiseDialogs();
    await renderMermaid();
    document.querySelector<HTMLButtonElement>("button[data-mermaid-expand]")!.click();

    const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]')!;
    const canvas = dialog.querySelector<HTMLElement>("[data-media-dialog-canvas]")!;
    const status = dialog.querySelector<HTMLOutputElement>("[data-media-zoom-status]")!;
    const zoomIn = dialog.querySelector<HTMLButtonElement>("[data-media-zoom-in]")!;
    const zoomOut = dialog.querySelector<HTMLButtonElement>("[data-media-zoom-out]")!;
    const reset = dialog.querySelector<HTMLButtonElement>("[data-media-zoom-reset]")!;

    for (let index = 0; index < 20; index += 1) zoomIn.click();
    expect(canvas.dataset.mediaZoom).toBe("3");
    expect(status.textContent).toBe("缩放：300%");
    expect(zoomIn.disabled).toBe(true);

    for (let index = 0; index < 20; index += 1) zoomOut.click();
    expect(canvas.dataset.mediaZoom).toBe("0.5");
    expect(status.textContent).toBe("缩放：50%");
    expect(zoomOut.disabled).toBe(true);

    reset.click();
    expect(canvas.dataset.mediaZoom).toBe("1");
    expect(status.textContent).toBe("缩放：100%");
    expect(zoomIn.disabled).toBe(false);
    expect(zoomOut.disabled).toBe(false);
  });

  it("opens from the diagram, ignores source-copy clicks, and restores focus to expansion", async () => {
    initialiseDialogs();
    await renderMermaid();

    const figure = document.querySelector<HTMLElement>(".mermaid-diagram")!;
    const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]')!;
    const expand = figure.querySelector<HTMLButtonElement>("button[data-mermaid-expand]")!;
    figure.querySelector<HTMLButtonElement>("button[data-copy-source]")!.click();
    expect(dialog.open).toBe(false);

    figure.querySelector<SVGSVGElement>(":scope > svg")!.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    expect(dialog.open).toBe(true);
    dialog.close();
    expect(document.activeElement).toBe(expand);

    expand.click();
    expect(dialog.open).toBe(true);
    dialog.close();
    expect(document.activeElement).toBe(expand);
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

  it("closes an enlarged diagram during color redraw and focuses its replacement", async () => {
    document.querySelector(".note-content")?.insertAdjacentHTML(
      "beforeend",
      '<pre data-website-mermaid data-diagram-label="第二张图"><code class="language-mermaid">graph TD; B--&gt;C</code></pre>'
    );
    mermaid.render.mockImplementation(async (id?: string) => ({
      svg: `<svg xmlns="http://www.w3.org/2000/svg" id="${id}"><defs><clipPath id="${id}-clip" /></defs><g clip-path="url(#${id}-clip)" /></svg>`
    }));
    initialiseDialogs();
    await renderMermaid();

    const originalExpand = document.querySelectorAll<HTMLButtonElement>("[data-mermaid-expand]")[1]!;
    originalExpand.click();
    const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="media"]')!;
    expect(dialog.open).toBe(true);
    expect(dialog.querySelectorAll("[data-media-dialog-canvas] > svg")).toHaveLength(1);

    document.dispatchEvent(new CustomEvent(COLOR_SCHEME_EVENT, { detail: { scheme: "dark" } }));

    expect(dialog.open).toBe(false);
    expect(dialog.querySelectorAll("[data-media-dialog-canvas] > svg")).toHaveLength(0);
    await vi.waitFor(() => expect(mermaid.render).toHaveBeenCalledTimes(4));
    const replacementExpand = document.querySelectorAll<HTMLButtonElement>("[data-mermaid-expand]")[1]!;
    expect(replacementExpand).not.toBe(originalExpand);
    expect(document.activeElement).toBe(replacementExpand);
    expect(dialog.open).toBe(false);
    expect(dialog.querySelectorAll("[data-media-dialog-canvas] > svg")).toHaveLength(0);

    const ids = Array.from(
      document.querySelectorAll<SVGElement>("svg[id], svg [id]"),
      (element) => element.id
    );
    expect(new Set(ids).size).toBe(ids.length);
  });
});
