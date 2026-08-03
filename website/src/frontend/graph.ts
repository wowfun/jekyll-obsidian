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
  type SimulationLinkDatum,
  type SimulationNodeDatum,
  type ZoomTransform
} from "d3";
import { fetchJson, parseGraphPayload } from "./data";
import type { GraphEdge, GraphNode } from "./types";
import { requireSiteUrl } from "./urls";

interface VisualNode extends GraphNode, SimulationNodeDatum {
  degree: number;
}

interface VisualEdge extends SimulationLinkDatum<VisualNode> {
  source: string | VisualNode;
  target: string | VisualNode;
  kind: GraphEdge["kind"];
  count: number;
}

function reducedMotion(): boolean {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export async function renderGraph(container: HTMLElement): Promise<void> {
  const status = container.querySelector<HTMLElement>("[data-graph-status]");
  if (status) status.textContent = container.dataset.graphLoading || "Loading graph…";

  try {
    const url = container.dataset.graphUrl || requireSiteUrl("graph");
    const payload = parseGraphPayload(await fetchJson(url));
    const degree = new Map<string, number>();
    for (const edge of payload.edges) {
      degree.set(edge.source, (degree.get(edge.source) ?? 0) + edge.count);
      degree.set(edge.target, (degree.get(edge.target) ?? 0) + edge.count);
    }

    const nodes: VisualNode[] = payload.nodes.map((node) => ({
      ...node,
      degree: degree.get(node.id) ?? 0
    }));
    const edges: VisualEdge[] = payload.edges.map((edge) => ({ ...edge }));
    const width = Math.max(container.clientWidth, 320);
    const height = Math.max(Math.min(width * 0.68, 720), 460);

    container.querySelector("[data-graph-canvas]")?.remove();
    const canvas = document.createElement("div");
    canvas.className = "graph-canvas";
    canvas.dataset.graphCanvas = "";
    container.prepend(canvas);

    const svg = select(canvas)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("role", "img")
      .attr("aria-labelledby", "website-graph-title website-graph-description");
    svg.append("title").attr("id", "website-graph-title").text(container.dataset.graphTitle || "Note relation graph");
    svg
      .append("desc")
      .attr("id", "website-graph-description")
      .text(container.dataset.graphDescription || "Linked notes are connected by solid lines; embedded notes use dashed lines.");

    const viewport = svg.append("g").attr("class", "graph-viewport");
    const linkLayer = viewport.append("g").attr("class", "graph-links");
    const nodeLayer = viewport.append("g").attr("class", "graph-nodes");

    const links = linkLayer
      .selectAll<SVGLineElement, VisualEdge>("line")
      .data(edges)
      .join("line")
      .attr("class", (edge) => `graph-edge graph-edge--${edge.kind}`)
      .attr("stroke-width", (edge) => Math.min(1 + Math.log2(edge.count), 4));

    const nodeGroups = nodeLayer
      .selectAll<SVGGElement, VisualNode>("g")
      .data(nodes)
      .join("g")
      .attr("class", "graph-node")
      .attr("role", "link")
      .attr("tabindex", 0)
      .attr("aria-label", (node) => (container.dataset.graphNodeLabel || "{title}, {count} relations")
        .replace("{title}", node.title)
        .replace("{count}", String(node.degree)))
      .on("click", (_event, node) => window.location.assign(node.url))
      .on("keydown", (event: KeyboardEvent, node) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          window.location.assign(node.url);
        }
      });

    nodeGroups
      .append("circle")
      .attr("r", (node) => Math.min(7 + Math.sqrt(node.degree) * 2, 18));
    nodeGroups
      .append("text")
      .attr("x", (node) => Math.min(13 + Math.sqrt(node.degree) * 2, 24))
      .attr("y", "0.32em")
      .text((node) => node.title);

    const simulation = forceSimulation(nodes)
      .force(
        "link",
        forceLink<VisualNode, VisualEdge>(edges)
          .id((node) => node.id)
          .distance((edge) => (edge.kind === "embed" ? 76 : 100))
          .strength(0.34)
      )
      .force("charge", forceManyBody().strength(-210))
      .force("collision", forceCollide<VisualNode>().radius((node) => 24 + Math.sqrt(node.degree) * 2))
      .force("center", forceCenter(width / 2, height / 2));

    const position = () => {
      links
        .attr("x1", (edge) => (edge.source as VisualNode).x ?? 0)
        .attr("y1", (edge) => (edge.source as VisualNode).y ?? 0)
        .attr("x2", (edge) => (edge.target as VisualNode).x ?? 0)
        .attr("y2", (edge) => (edge.target as VisualNode).y ?? 0);
      nodeGroups.attr(
        "transform",
        (node) => `translate(${node.x ?? width / 2},${node.y ?? height / 2})`
      );
    };

    const dragBehaviour = drag<SVGGElement, VisualNode>()
      .on("start", (event: D3DragEvent<SVGGElement, VisualNode, VisualNode>, node) => {
        if (!event.active) simulation.alphaTarget(0.22).restart();
        node.fx = node.x;
        node.fy = node.y;
      })
      .on("drag", (event: D3DragEvent<SVGGElement, VisualNode, VisualNode>, node) => {
        node.fx = event.x;
        node.fy = event.y;
      })
      .on("end", (event: D3DragEvent<SVGGElement, VisualNode, VisualNode>, node) => {
        if (!event.active) simulation.alphaTarget(0);
        node.fx = null;
        node.fy = null;
      });
    nodeGroups.call(dragBehaviour);

    svg.call(
      zoom<SVGSVGElement, unknown>()
        .scaleExtent([0.45, 3])
        .on("zoom", (event: { transform: ZoomTransform }) => {
          viewport.attr("transform", event.transform.toString());
        })
    );

    if (reducedMotion()) {
      simulation.stop();
      const radius = Math.max(80, Math.min(width, height) * 0.36);
      nodes.forEach((node, index) => {
        const angle = (index / Math.max(nodes.length, 1)) * Math.PI * 2 - Math.PI / 2;
        node.x = width / 2 + Math.cos(angle) * radius;
        node.y = height / 2 + Math.sin(angle) * radius;
      });
      position();
    } else {
      simulation.on("tick", position);
    }
    if (status) status.textContent = (container.dataset.graphSummary || "{notes} notes and {relations} relations.")
      .replace("{notes}", String(nodes.length))
      .replace("{relations}", String(edges.length));
    container.dataset.graphReady = "true";
  } catch {
    container.dataset.graphError = "true";
    if (status) status.textContent = container.dataset.graphUnavailable || "The interactive graph could not be loaded. Use the note directory below.";
  }
}
