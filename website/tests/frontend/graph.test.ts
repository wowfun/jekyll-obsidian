// @vitest-environment happy-dom

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

function graphMarkup(): string {
  return `
    <meta name="website:graph" content="/assets/website/graph.v1.json">
    <section data-local-graph-section>
      <button data-graph-open="global">Global</button>
      <button data-graph-open="local">Local</button>
      <div data-graph-view data-graph-mode="compact" data-current-note-id="a"><p data-graph-status></p></div>
      <template data-local-graph-data>
        <i data-graph-node data-node-id="a" data-node-title="Alpha" data-node-url="/a/" data-node-degree="1"></i>
        <i data-graph-node data-node-id="b" data-node-title="Beta" data-node-url="/b/" data-node-degree="9"></i>
        <i data-graph-edge data-edge-source="a" data-edge-target="b" data-edge-kind="link" data-edge-count="1"></i>
      </template>
    </section>
    <dialog data-dialog="graph-global"><button data-dialog-close>Close</button><div data-graph-dialog-view="global" data-graph-mode="global" data-current-note-id="a" data-graph-too-large="Complete graph is too large to render interactively."><p data-graph-status></p></div></dialog>
    <dialog data-dialog="graph-local"><button data-dialog-close>Close</button><div data-graph-dialog-view="local" data-graph-mode="expanded" data-current-note-id="a"><p data-graph-status></p></div></dialog>
  `;
}

describe("interactive graphs", () => {
  beforeEach(() => {
    vi.resetModules();
    document.body.innerHTML = graphMarkup();
    Object.defineProperty(HTMLElement.prototype, "clientWidth", { configurable: true, get: () => 320 });
    Object.defineProperty(HTMLElement.prototype, "clientHeight", { configurable: true, get: () => 240 });
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: () => ({ matches: true, addEventListener: vi.fn(), removeEventListener: vi.fn() })
    });
    SVGSVGElement.prototype.createSVGPoint = () => ({
      x: 0,
      y: 0,
      matrixTransform() { return this; }
    } as DOMPoint);
    HTMLDialogElement.prototype.showModal = function showModal() { this.open = true; };
    HTMLDialogElement.prototype.close = function close() {
      this.open = false;
      this.dispatchEvent(new Event("close"));
    };
  });

  afterEach(() => {
    window.dispatchEvent(new Event("pagehide"));
    vi.restoreAllMocks();
  });

  it("renders local data immediately, keeps the current note centred, and sizes area by global degree", async () => {
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();

    const view = document.querySelector<HTMLElement>("[data-graph-view]")!;
    const nodes = [...view.querySelectorAll<SVGGElement>(".graph-node")];
    expect(nodes).toHaveLength(2);
    expect(nodes[0]?.classList.contains("graph-node--current")).toBe(true);
    expect(nodes[0]?.getAttribute("transform")).toBe("translate(160,120)");
    const radii = nodes.map((node) => Number(node.querySelector("circle")?.getAttribute("r")));
    expect(radii[1]).toBeGreaterThan(radii[0]!);
    expect(Number(view.dataset.graphScale)).toBe(1);
  });

  it("opens the expanded local graph without fetching global data", async () => {
    const fetchMock = vi.spyOn(window, "fetch");
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();
    document.querySelector<HTMLElement>('[data-graph-open="local"]')!.click();
    await Promise.resolve();

    expect(document.querySelector<HTMLDialogElement>('[data-dialog="graph-local"]')!.open).toBe(true);
    expect(document.querySelectorAll('[data-graph-dialog-view="local"] .graph-node')).toHaveLength(2);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("loads the complete graph once across repeated dialog opens", async () => {
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(new Response(JSON.stringify({
      schema_version: 1,
      nodes: [
        { id: "a", title: "Alpha", url: "/a/", degree: 1 },
        { id: "b", title: "Beta", url: "/b/", degree: 1 }
      ],
      edges: [{ source: "a", target: "b", kind: "link", count: 1 }]
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();

    document.querySelector<HTMLElement>('[data-graph-open="global"]')!.click();
    await vi.waitFor(() => expect(document.querySelectorAll('[data-graph-dialog-view="global"] .graph-node')).toHaveLength(2));
    document.querySelector<HTMLDialogElement>('[data-dialog="graph-global"]')!.close();
    document.querySelector<HTMLElement>('[data-graph-open="global"]')!.click();
    await vi.waitFor(() => expect(document.querySelectorAll('[data-graph-dialog-view="global"] .graph-node')).toHaveLength(2));

    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("does not start a complete-graph simulation after its dialog closes during loading", async () => {
    let finishRequest!: (response: Response) => void;
    const fetchMock = vi.spyOn(window, "fetch").mockImplementation(() => new Promise((resolve) => {
      finishRequest = resolve;
    }));
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();

    document.querySelector<HTMLElement>('[data-graph-open="global"]')!.click();
    const dialog = document.querySelector<HTMLDialogElement>('[data-dialog="graph-global"]')!;
    const view = dialog.querySelector<HTMLElement>('[data-graph-dialog-view="global"]')!;
    dialog.close();
    finishRequest(new Response(JSON.stringify({
      schema_version: 1,
      nodes: [{ id: "a", title: "Alpha", url: "/a/", degree: 0 }],
      edges: []
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
    await Promise.resolve();
    await Promise.resolve();

    expect(view.querySelector("svg")).toBeNull();
    document.querySelector<HTMLElement>('[data-graph-open="global"]')!.click();
    await vi.waitFor(() => expect(view.querySelectorAll(".graph-node")).toHaveLength(1));
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("renders only the latest open generation when a complete-graph request is shared", async () => {
    let finishRequest!: (response: Response) => void;
    vi.spyOn(window, "fetch").mockImplementation(() => new Promise((resolve) => {
      finishRequest = resolve;
    }));
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();

    const opener = document.querySelector<HTMLElement>('[data-graph-open="global"]')!;
    const dialog = document.querySelector<HTMLDialogElement>('[data-dialog="graph-global"]')!;
    const view = dialog.querySelector<HTMLElement>('[data-graph-dialog-view="global"]')!;
    let canvasInsertions = 0;
    const observer = new MutationObserver((records) => {
      for (const record of records) {
        canvasInsertions += [...record.addedNodes].filter(
          (node) => node instanceof HTMLElement && node.matches("[data-graph-canvas]")
        ).length;
      }
    });
    observer.observe(view, { childList: true });

    opener.click();
    dialog.close();
    opener.click();
    finishRequest(new Response(JSON.stringify({
      schema_version: 1,
      nodes: [{ id: "a", title: "Alpha", url: "/a/", degree: 0 }],
      edges: []
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
    await vi.waitFor(() => expect(view.dataset.graphReady).toBe("true"));
    await Promise.resolve();
    observer.disconnect();

    expect(canvasInsertions).toBe(1);
  });

  it("uses a bounded fallback for an oversized complete graph", async () => {
    const nodes = Array.from({ length: 251 }, (_, index) => ({
      id: `node-${index}`,
      title: `Node ${index}`,
      url: `/node-${index}/`,
      degree: 0
    }));
    vi.spyOn(window, "fetch").mockResolvedValue(new Response(JSON.stringify({
      schema_version: 1,
      nodes,
      edges: []
    }), { status: 200, headers: { "Content-Type": "application/json" } }));
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();

    document.querySelector<HTMLElement>('[data-graph-open="global"]')!.click();
    const view = document.querySelector<HTMLElement>('[data-graph-dialog-view="global"]')!;
    await vi.waitFor(() => expect(view.querySelector("[data-graph-status]")?.textContent)
      .toBe("Complete graph is too large to render interactively."));

    expect(view.querySelector("[data-graph-canvas]")).toBeNull();
    expect(view.querySelectorAll(".graph-node")).toHaveLength(0);
  });

  it("keeps graph controllers live across a persisted pagehide", async () => {
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();
    const compact = document.querySelector<HTMLElement>("[data-graph-view]")!;
    const pagehide = new Event("pagehide");
    Object.defineProperty(pagehide, "persisted", { value: true });
    window.dispatchEvent(pagehide);
    const pageshow = new Event("pageshow");
    Object.defineProperty(pageshow, "persisted", { value: true });
    window.dispatchEvent(pageshow);

    expect(compact.dataset.graphDisposed).toBe("false");
    document.querySelector<HTMLElement>('[data-graph-open="local"]')!.click();
    expect(document.querySelector<HTMLDialogElement>('[data-dialog="graph-local"]')!.open).toBe(true);
  });

  it("zooms on wheel without scrolling the page and disposes dialog simulations", async () => {
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();
    document.querySelector<HTMLElement>('[data-graph-open="local"]')!.click();
    const view = document.querySelector<HTMLElement>('[data-graph-dialog-view="local"]')!;
    const svg = view.querySelector<SVGSVGElement>("svg")!;
    const wheel = new WheelEvent("wheel", { deltaY: -120, clientX: 100, clientY: 100, bubbles: true, cancelable: true });
    svg.dispatchEvent(wheel);
    expect(wheel.defaultPrevented).toBe(true);
    expect(Number(view.dataset.graphScale)).toBeGreaterThan(1);

    document.querySelector<HTMLDialogElement>('[data-dialog="graph-local"]')!.close();
    expect(view.dataset.graphDisposed).toBe("true");
  });

  it("keeps the server-rendered linked-note fallback when local data is invalid", async () => {
    document.querySelector<HTMLTemplateElement>("[data-local-graph-data]")?.content
      .querySelector("[data-graph-edge]")?.setAttribute("data-edge-target", "missing");
    document.querySelector("[data-local-graph-section]")?.insertAdjacentHTML(
      "beforeend",
      '<div data-graph-fallback><a href="/b/">Beta</a></div>'
    );
    const { initialiseGraphs } = await import("../../src/frontend/graph");
    initialiseGraphs();

    const view = document.querySelector<HTMLElement>("[data-graph-view]")!;
    expect(view.dataset.graphError).toBe("true");
    expect(document.querySelector<HTMLElement>("[data-graph-fallback]")!.hidden).toBe(false);
    expect(document.querySelector("[data-graph-fallback] a")?.getAttribute("href")).toBe("/b/");
  });
});
