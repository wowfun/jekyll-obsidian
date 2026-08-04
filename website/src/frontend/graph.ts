import {
  drag,
  forceCenter,
  forceCollide,
  forceLink,
  forceManyBody,
  forceSimulation,
  select,
  zoom,
  type D3DragEvent,
  type Simulation,
  type SimulationLinkDatum,
  type SimulationNodeDatum,
  type ZoomTransform
} from "d3";
import { fetchJson, parseGraphPayload } from "./data";
import { openWebsiteDialog } from "./dialogs";
import type { GraphEdge, GraphNode, GraphPayload, LocalGraphPayload } from "./types";
import { requireSiteUrl } from "./urls";

type GraphMode = "compact" | "expanded" | "global";

interface VisualNode extends GraphNode, SimulationNodeDatum {
  degree: number;
  dragStartX?: number;
  dragStartY?: number;
  dragged?: boolean;
}

interface VisualEdge extends SimulationLinkDatum<VisualNode> {
  source: string | VisualNode;
  target: string | VisualNode;
  kind: GraphEdge["kind"];
  count: number;
}

const documentController = Symbol.for("jekyll-obsidian.graph-controller");
const instances = new Map<HTMLElement, () => void>();
let graphIdentity = 0;
let globalGraphPromise: Promise<GraphPayload> | null = null;
const COMPLETE_GRAPH_MAX_NODES = 250;
const COMPLETE_GRAPH_MAX_EDGES = 1_000;

function reducedMotion(): boolean {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function graphMode(container: HTMLElement): GraphMode {
  const mode = container.dataset.graphMode;
  return mode === "compact" || mode === "expanded" || mode === "global" ? mode : "compact";
}

function positiveInteger(value: string | undefined, label: string, allowZero = false): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < (allowZero ? 0 : 1)) {
    throw new TypeError(`Invalid local graph ${label}`);
  }
  return parsed;
}

function localGraphPayload(section: HTMLElement): LocalGraphPayload {
  const template = section.querySelector<HTMLTemplateElement>("template[data-local-graph-data]");
  const view = section.querySelector<HTMLElement>("[data-graph-view]");
  const currentId = view?.dataset.currentNoteId;
  if (!template || !currentId) throw new TypeError("Local graph data is unavailable");

  const nodes: GraphNode[] = [...template.content.querySelectorAll<HTMLElement>("[data-graph-node]")].map((item) => {
    const id = item.dataset.nodeId;
    const title = item.dataset.nodeTitle;
    const url = item.dataset.nodeUrl;
    if (!id || !title || !url) throw new TypeError("Invalid local graph node");
    return { id, title, url, degree: positiveInteger(item.dataset.nodeDegree, "degree", true) };
  });
  const edges: GraphEdge[] = [...template.content.querySelectorAll<HTMLElement>("[data-graph-edge]")].map((item) => {
    const source = item.dataset.edgeSource;
    const target = item.dataset.edgeTarget;
    const kind = item.dataset.edgeKind;
    if (!source || !target || (kind !== "link" && kind !== "embed")) {
      throw new TypeError("Invalid local graph edge");
    }
    return { source, target, kind, count: positiveInteger(item.dataset.edgeCount, "edge count") };
  });
  const ids = new Set(nodes.map((node) => node.id));
  if (!ids.has(currentId) || edges.some((edge) => !ids.has(edge.source) || !ids.has(edge.target))) {
    throw new TypeError("Local graph references an unknown node");
  }
  return { current_id: currentId, nodes, edges };
}

function loadGlobalGraph(): Promise<GraphPayload> {
  globalGraphPromise ??= fetchJson(requireSiteUrl("graph"))
    .then(parseGraphPayload)
    .catch((error: unknown) => {
      globalGraphPromise = null;
      throw error;
    });
  return globalGraphPromise;
}

function nodeRadius(degree: number, mode: GraphMode): number {
  const minimum = mode === "compact" ? 5 : 7;
  const areaStep = mode === "compact" ? 28 : 56;
  return Math.sqrt(minimum * minimum + Math.log2(degree + 1) * areaStep);
}

function nodeId(node: string | VisualNode): string {
  return typeof node === "string" ? node : node.id;
}

function pointerCoordinates(sourceEvent: Event): [number, number] | null {
  if (sourceEvent instanceof MouseEvent || sourceEvent instanceof PointerEvent) {
    return [sourceEvent.clientX, sourceEvent.clientY];
  }
  if (sourceEvent instanceof TouchEvent && sourceEvent.touches[0]) {
    return [sourceEvent.touches[0].clientX, sourceEvent.touches[0].clientY];
  }
  return null;
}

function renderGraph(container: HTMLElement, payload: GraphPayload | LocalGraphPayload, currentId: string): void {
  instances.get(container)?.();
  container.dataset.graphDisposed = "false";
  container.dataset.graphError = "false";
  container.dataset.graphBoundedFallback = "false";
  const status = container.querySelector<HTMLElement>("[data-graph-status]");
  if (status) status.textContent = container.dataset.graphLoading || "Loading graph…";

  const mode = graphMode(container);
  const neighbours = new Map(payload.nodes.map((node) => [node.id, new Set<string>()]));
  for (const edge of payload.edges) {
    neighbours.get(edge.source)?.add(edge.target);
    neighbours.get(edge.target)?.add(edge.source);
  }
  const nodes: VisualNode[] = payload.nodes.map((node) => ({
    ...node,
    degree: node.degree ?? neighbours.get(node.id)?.size ?? 0
  }));
  const edges: VisualEdge[] = payload.edges.map((edge) => ({ ...edge }));
  const width = Math.max(container.clientWidth, mode === "compact" ? 220 : 640);
  const height = Math.max(container.clientHeight, mode === "compact" ? 210 : 480);
  const current = nodes.find((node) => node.id === currentId);
  const centreX = width / 2;
  const centreY = height / 2;

  nodes.forEach((node, index) => {
    if (node === current) {
      node.x = centreX;
      node.y = centreY;
      node.fx = centreX;
      node.fy = centreY;
      return;
    }
    const offset = current ? index - (nodes.indexOf(current) < index ? 1 : 0) : index;
    const count = Math.max(nodes.length - (current ? 1 : 0), 1);
    const angle = (offset / count) * Math.PI * 2 - Math.PI / 2;
    const radius = Math.max(58, Math.min(width, height) * (mode === "compact" ? 0.31 : 0.36));
    node.x = centreX + Math.cos(angle) * radius;
    node.y = centreY + Math.sin(angle) * radius;
  });

  container.querySelector("[data-graph-canvas]")?.remove();
  const canvas = document.createElement("div");
  canvas.className = "graph-canvas";
  canvas.dataset.graphCanvas = "";
  container.prepend(canvas);

  const identity = ++graphIdentity;
  const titleId = `website-graph-title-${identity}`;
  const descriptionId = `website-graph-description-${identity}`;
  const svg = select(canvas)
    .append("svg")
    .attr("viewBox", `0 0 ${width} ${height}`)
    .attr("role", "group")
    .attr("aria-labelledby", `${titleId} ${descriptionId}`);
  svg.append("title").attr("id", titleId).text(container.dataset.graphTitle || "Note relation graph");
  svg.append("desc").attr("id", descriptionId).text(
    container.dataset.graphDescription || "Linked notes are connected by solid lines; embedded notes use dashed lines."
  );

  const viewport = svg.append("g").attr("class", "graph-viewport");
  const links = viewport.append("g")
    .attr("class", "graph-links")
    .selectAll<SVGLineElement, VisualEdge>("line")
    .data(edges)
    .join("line")
    .attr("class", (edge) => `graph-edge graph-edge--${edge.kind}`)
    .attr("stroke-width", (edge) => Math.min(1 + Math.log2(edge.count), 4));

  const isLocal = mode !== "global";
  const nodeGroups = viewport.append("g")
    .attr("class", "graph-nodes")
    .selectAll<SVGGElement, VisualNode>("g")
    .data(nodes)
    .join("g")
    .attr("class", (node) => `graph-node${node.id === currentId ? " graph-node--current" : ""}`)
    .attr("data-node-id", (node) => node.id)
    .attr("data-node-url", (node) => node.url)
    .attr("role", (node) => isLocal && node.id === currentId ? "img" : "link")
    .attr("tabindex", 0)
    .attr("aria-current", (node) => node.id === currentId ? "page" : null)
    .attr("aria-label", (node) => (container.dataset.graphNodeLabel || "{title}, {count} relations")
      .replace("{title}", node.title)
      .replace("{count}", String(node.degree)))
    .on("click", (event: MouseEvent, node) => {
      if (event.defaultPrevented || node.dragged || (isLocal && node.id === currentId)) return;
      window.location.assign(node.url);
    })
    .on("keydown", (event: KeyboardEvent, node) => {
      if ((event.key === "Enter" || event.key === " ") && !(isLocal && node.id === currentId)) {
        event.preventDefault();
        window.location.assign(node.url);
      }
    });

  nodeGroups.append("circle").attr("r", (node) => nodeRadius(node.degree, mode));
  const nodeLabels = nodeGroups.append("text").text((node) => node.title);

  const adjacency = new Map<string, Set<string>>();
  for (const node of nodes) adjacency.set(node.id, new Set([node.id]));
  for (const edge of edges) {
    adjacency.get(nodeId(edge.source))?.add(nodeId(edge.target));
    adjacency.get(nodeId(edge.target))?.add(nodeId(edge.source));
  }
  const highlight = (active?: VisualNode) => {
    const related = active ? adjacency.get(active.id) : undefined;
    nodeGroups.classed("graph-node--dimmed", (node) => Boolean(related && !related.has(node.id)));
    links.classed("graph-edge--dimmed", (edge) => Boolean(
      related && nodeId(edge.source) !== active?.id && nodeId(edge.target) !== active?.id
    ));
  };
  nodeGroups.on("pointerenter.highlight", (_event, node) => highlight(node));
  nodeGroups.on("pointerleave.highlight", () => highlight());
  nodeGroups.on("focus.highlight", (_event, node) => highlight(node));
  nodeGroups.on("blur.highlight", () => highlight());

  const simulation: Simulation<VisualNode, VisualEdge> = forceSimulation(nodes)
    .force("link", forceLink<VisualNode, VisualEdge>(edges)
      .id((node) => node.id)
      .distance((edge) => edge.kind === "embed" ? (mode === "compact" ? 56 : 82) : (mode === "compact" ? 72 : 110))
      .strength(0.34))
    .force("charge", forceManyBody().strength(mode === "compact" ? -115 : -220))
    .force("collision", forceCollide<VisualNode>().radius((node) => nodeRadius(node.degree, mode) + (mode === "compact" ? 12 : 20)))
    .force("center", forceCenter(centreX, centreY));

  const position = () => {
    links
      .attr("x1", (edge) => (edge.source as VisualNode).x ?? 0)
      .attr("y1", (edge) => (edge.source as VisualNode).y ?? 0)
      .attr("x2", (edge) => (edge.target as VisualNode).x ?? 0)
      .attr("y2", (edge) => (edge.target as VisualNode).y ?? 0);
    nodeGroups.attr("transform", (node) => `translate(${node.x ?? centreX},${node.y ?? centreY})`);
    nodeLabels.each(function placeLabel(node) {
      const label = select(this);
      const x = node.x ?? centreX;
      const horizontal = (x - centreX) / width;
      const gap = mode === "compact" ? 4 : 6;
      const distance = nodeRadius(node.degree, mode) + gap;
      if (node.id === currentId) {
        label.attr("text-anchor", "start").attr("x", distance).attr("y", "0.32em");
        return;
      }
      if (Math.abs(horizontal) < 0.1) {
        label
          .attr("text-anchor", "middle")
          .attr("x", 0)
          .attr("y", (node.y ?? centreY) < centreY ? -distance : distance + 6);
        return;
      }
      let direction = horizontal < 0 ? -1 : 1;
      const labelWidth = typeof this.getComputedTextLength === "function"
        ? this.getComputedTextLength()
        : node.title.length * (mode === "compact" ? 5.5 : 6);
      const outwardEdge = x + direction * (distance + labelWidth);
      if (outwardEdge < 4 || outwardEdge > width - 4) direction *= -1;
      label
        .attr("text-anchor", direction < 0 ? "end" : "start")
        .attr("x", direction * distance)
        .attr("y", "0.32em");
    });
  };
  position();

  const dragBehaviour = drag<SVGGElement, VisualNode>()
    .filter((event: MouseEvent, node) => !event.ctrlKey && !event.button && node.id !== currentId)
    .clickDistance(4)
    .on("start", (event: D3DragEvent<SVGGElement, VisualNode, VisualNode>, node) => {
      event.sourceEvent?.stopPropagation();
      const coordinates = event.sourceEvent ? pointerCoordinates(event.sourceEvent) : null;
      node.dragStartX = coordinates?.[0] ?? event.x;
      node.dragStartY = coordinates?.[1] ?? event.y;
      node.dragged = false;
      if (!event.active && !reducedMotion()) simulation.alphaTarget(0.2).restart();
      node.fx = node.x;
      node.fy = node.y;
    })
    .on("drag", (event: D3DragEvent<SVGGElement, VisualNode, VisualNode>, node) => {
      const coordinates = event.sourceEvent ? pointerCoordinates(event.sourceEvent) : null;
      const x = coordinates?.[0] ?? event.x;
      const y = coordinates?.[1] ?? event.y;
      if (Math.hypot(x - (node.dragStartX ?? x), y - (node.dragStartY ?? y)) > 4) node.dragged = true;
      node.fx = event.x;
      node.fy = event.y;
      if (reducedMotion()) {
        node.x = event.x;
        node.y = event.y;
        position();
      }
    })
    .on("end", (event: D3DragEvent<SVGGElement, VisualNode, VisualNode>, node) => {
      if (!event.active) simulation.alphaTarget(0);
      setTimeout(() => { node.dragged = false; }, 0);
    });
  nodeGroups.call(dragBehaviour);

  const zoomBehaviour = zoom<SVGSVGElement, unknown>()
    .extent([[0, 0], [width, height]])
    .scaleExtent([0.45, 3])
    .filter((event: Event) => {
      if (event.type === "wheel" || event.type.startsWith("touch")) return true;
      if (event instanceof MouseEvent) {
        return event.button === 0 && !(event.target instanceof Element && event.target.closest(".graph-node"));
      }
      return true;
    })
    .on("zoom", (event: { transform: ZoomTransform }) => {
      viewport.attr("transform", event.transform.toString());
      container.dataset.graphScale = String(event.transform.k);
    });
  svg.call(zoomBehaviour);
  container.dataset.graphScale = "1";

  const svgElement = svg.node();
  const preventOuterScroll = (event: WheelEvent) => event.preventDefault();
  svgElement?.addEventListener("wheel", preventOuterScroll, { passive: false });

  if (reducedMotion()) {
    simulation.stop();
    position();
  } else {
    simulation.on("tick", position);
  }

  if (status) status.textContent = (container.dataset.graphSummary || "{notes} notes and {relations} relations.")
    .replace("{notes}", String(nodes.length))
    .replace("{relations}", String(edges.length));
  container.dataset.graphReady = "true";

  const dispose = () => {
    simulation.stop();
    svgElement?.removeEventListener("wheel", preventOuterScroll);
    container.dataset.graphDisposed = "true";
    instances.delete(container);
  };
  instances.set(container, dispose);
}

function showFailure(container: HTMLElement): void {
  container.dataset.graphError = "true";
  const status = container.querySelector<HTMLElement>("[data-graph-status]");
  if (status) status.textContent = container.dataset.graphUnavailable || "The interactive graph could not be loaded. Use the linked notes below.";
}

function showBoundedFallback(container: HTMLElement): void {
  instances.get(container)?.();
  container.querySelector("[data-graph-canvas]")?.remove();
  container.dataset.graphBoundedFallback = "true";
  container.dataset.graphError = "false";
  container.dataset.graphReady = "fallback";
  const status = container.querySelector<HTMLElement>("[data-graph-status]");
  if (status) {
    status.textContent = container.dataset.graphTooLarge ||
      "This complete graph is too large to render interactively. Use local graphs or search instead.";
  }
}

export function initialiseGraphs(): void {
  const controlledDocument = document as Document & { [documentController]?: () => void };
  controlledDocument[documentController]?.();

  const section = document.querySelector<HTMLElement>("[data-local-graph-section]");
  if (!section) return;
  let localPayload: LocalGraphPayload;
  let globalOpenGeneration = 0;
  try {
    localPayload = localGraphPayload(section);
    const compact = section.querySelector<HTMLElement>("[data-graph-view]");
    if (!compact) throw new TypeError("Local graph view is unavailable");
    renderGraph(compact, localPayload, localPayload.current_id);
    const fallback = section.querySelector<HTMLElement>("[data-graph-fallback]");
    if (fallback) fallback.hidden = true;
  } catch {
    const compact = section.querySelector<HTMLElement>("[data-graph-view]");
    if (compact) showFailure(compact);
    return;
  }

  const handleOpen = (event: Event) => {
    const opener = event.currentTarget;
    if (!(opener instanceof HTMLElement)) return;
    const requested = opener.dataset.graphOpen;
    if (requested !== "local" && requested !== "global") return;
    event.preventDefault();
    const openGeneration = requested === "global" ? ++globalOpenGeneration : 0;

    const owningDialog = opener.closest<HTMLDialogElement>("dialog[open]");
    owningDialog?.close();
    const name = requested === "global" ? "graph-global" : "graph-local";
    const dialog = openWebsiteDialog(name);
    if (!dialog) return;
    const view = dialog.querySelector<HTMLElement>(`[data-graph-dialog-view="${requested}"]`);
    if (!view) return;

    if (requested === "local") {
      renderGraph(view, localPayload, localPayload.current_id);
      return;
    }
    void loadGlobalGraph()
      .then((payload) => {
        if (!dialog.open || openGeneration !== globalOpenGeneration) return;
        if (payload.nodes.length > COMPLETE_GRAPH_MAX_NODES || payload.edges.length > COMPLETE_GRAPH_MAX_EDGES) {
          showBoundedFallback(view);
        } else {
          renderGraph(view, payload, localPayload.current_id);
        }
      })
      .catch(() => {
        if (dialog.open && openGeneration === globalOpenGeneration) showFailure(view);
      });
  };
  const openers = [...section.querySelectorAll<HTMLElement>("[data-graph-open]")];
  for (const opener of openers) opener.addEventListener("click", handleOpen);

  const closeHandlers = new Map<HTMLDialogElement, () => void>();
  for (const dialog of document.querySelectorAll<HTMLDialogElement>(
    'dialog[data-dialog="graph-global"], dialog[data-dialog="graph-local"]'
  )) {
    const handleClose = () => {
      if (dialog.dataset.dialog === "graph-global") globalOpenGeneration += 1;
      const view = dialog.querySelector<HTMLElement>("[data-graph-dialog-view]");
      if (view) instances.get(view)?.();
    };
    closeHandlers.set(dialog, handleClose);
    dialog.addEventListener("close", handleClose);
  }

  function cleanup() {
    globalOpenGeneration += 1;
    for (const opener of openers) opener.removeEventListener("click", handleOpen);
    for (const [dialog, handler] of closeHandlers) dialog.removeEventListener("close", handler);
    window.removeEventListener("pagehide", handlePageHide);
    for (const dispose of [...instances.values()]) dispose();
    if (controlledDocument[documentController] === cleanup) delete controlledDocument[documentController];
  }
  function handlePageHide(event: PageTransitionEvent) {
    if (!event.persisted) cleanup();
  }
  controlledDocument[documentController] = cleanup;
  window.addEventListener("pagehide", handlePageHide);
}
