import mermaid from "mermaid";
import { COLOR_SCHEME_EVENT } from "./color-scheme";
import { decorateSourceCopy } from "./code-block-copy";
import { openWebsiteDialog } from "./dialogs";

let watchesColorScheme = false;
const mermaidInteractionController = Symbol.for("jekyll-obsidian.mermaid-interaction-controller");
const MERMAID_ZOOM_MIN = 0.5;
const MERMAID_ZOOM_MAX = 3;
const MERMAID_ZOOM_STEP = 0.25;
const mermaidDialogOpeners = new WeakMap<HTMLDialogElement, HTMLElement>();
const initialisedMermaidDialogs = new WeakSet<HTMLDialogElement>();

type ControlledDocument = Document & { [mermaidInteractionController]?: boolean };

function cssToken(name: string, fallback: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback;
}

function sourceElements(): HTMLElement[] {
  return Array.from(
    document.querySelectorAll<HTMLElement>(
      "pre:has(> code.language-mermaid), [data-mermaid]:not([data-mermaid-rendered])"
    )
  );
}

function parseMermaidSvg(markup: string): SVGSVGElement {
  const template = document.createElement("template");
  template.innerHTML = markup;
  const roots = Array.from(template.content.childNodes).filter((node) =>
    node.nodeType !== Node.TEXT_NODE || Boolean(node.textContent?.trim())
  );
  const [root] = roots;
  if (roots.length !== 1 || !(root instanceof SVGSVGElement)) throw new Error("Invalid Mermaid SVG");
  return root;
}

function expandIcon(): SVGSVGElement {
  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.classList.add("source-copy__icon");
  icon.setAttribute("viewBox", "0 0 20 20");
  icon.setAttribute("aria-hidden", "true");
  icon.innerHTML = '<path d="M7 3H3v4M13 3h4v4M7 17H3v-4M13 17h4v-4"/>';
  return icon;
}

function decorateExpansion(figure: HTMLElement): void {
  if (figure.querySelector(":scope > button[data-mermaid-expand]")) return;
  const root = figure.closest<HTMLElement>(".note-content");
  const label = root?.dataset.expandDiagramLabel || "Expand diagram";
  const button = document.createElement("button");
  button.className = "source-copy__button mermaid-diagram__expand";
  button.type = "button";
  button.dataset.mermaidExpand = "";
  button.setAttribute("aria-label", label);
  button.title = label;
  button.lang = document.documentElement.lang;
  button.dir = document.documentElement.dir;
  button.append(expandIcon());
  figure.append(button);
}

function mermaidZoom(canvas: HTMLElement): number {
  const value = Number(canvas.dataset.mermaidZoom);
  return Number.isFinite(value) ? value : 1;
}

function updateMermaidPanAffordance(viewport: HTMLElement): void {
  viewport.toggleAttribute(
    "data-mermaid-pannable",
    viewport.scrollWidth > viewport.clientWidth || viewport.scrollHeight > viewport.clientHeight
  );
}

function setMermaidZoom(dialog: HTMLDialogElement, requested: number): void {
  const canvas = dialog.querySelector<HTMLElement>("[data-mermaid-dialog-canvas]");
  if (!canvas) return;
  const zoom = Math.max(MERMAID_ZOOM_MIN, Math.min(MERMAID_ZOOM_MAX, requested));
  canvas.dataset.mermaidZoom = String(zoom);
  canvas.style.inlineSize = `${zoom * 100}%`;
  const percent = String(Math.round(zoom * 100));
  const status = dialog.querySelector<HTMLOutputElement>("[data-mermaid-zoom-status]");
  if (status) status.textContent = (dialog.dataset.mermaidZoomLevel || "Zoom: {percent}%")
    .replace("{percent}", percent);
  const zoomIn = dialog.querySelector<HTMLButtonElement>("[data-mermaid-zoom-in]");
  const zoomOut = dialog.querySelector<HTMLButtonElement>("[data-mermaid-zoom-out]");
  if (zoomIn) zoomIn.disabled = zoom >= MERMAID_ZOOM_MAX;
  if (zoomOut) zoomOut.disabled = zoom <= MERMAID_ZOOM_MIN;
  const viewport = canvas.closest<HTMLElement>("[data-mermaid-dialog-viewport]");
  if (viewport) updateMermaidPanAffordance(viewport);
}

function prepareMermaidDialog(dialog: HTMLDialogElement): void {
  if (initialisedMermaidDialogs.has(dialog)) return;
  initialisedMermaidDialogs.add(dialog);
  const viewport = dialog.querySelector<HTMLElement>("[data-mermaid-dialog-viewport]");
  let pan: {
    pointerId: number;
    clientX: number;
    clientY: number;
    scrollLeft: number;
    scrollTop: number;
  } | undefined;
  const stopPanning = (pointerId?: number): void => {
    if (!viewport || !pan || (pointerId !== undefined && pointerId !== pan.pointerId)) return;
    const activePointerId = pan.pointerId;
    pan = undefined;
    delete viewport.dataset.mermaidPanning;
    if (viewport.hasPointerCapture(activePointerId)) viewport.releasePointerCapture(activePointerId);
  };
  viewport?.addEventListener("pointerdown", (event) => {
    const target = event.target;
    if (
      event.button !== 0 ||
      event.pointerType !== "mouse" ||
      !event.isPrimary ||
      !(target instanceof Element) ||
      !target.closest("[data-mermaid-dialog-canvas]") ||
      Boolean(target.closest("a[href], button, input, select, textarea, summary, [contenteditable]")) ||
      !viewport.hasAttribute("data-mermaid-pannable")
    ) return;
    pan = {
      pointerId: event.pointerId,
      clientX: event.clientX,
      clientY: event.clientY,
      scrollLeft: viewport.scrollLeft,
      scrollTop: viewport.scrollTop
    };
    viewport.setPointerCapture(event.pointerId);
    viewport.dataset.mermaidPanning = "";
    event.preventDefault();
    viewport.focus({ preventScroll: true });
  });
  viewport?.addEventListener("pointermove", (event) => {
    if (!pan || event.pointerId !== pan.pointerId) return;
    viewport.scrollLeft = pan.scrollLeft - (event.clientX - pan.clientX);
    viewport.scrollTop = pan.scrollTop - (event.clientY - pan.clientY);
  });
  viewport?.addEventListener("pointerup", (event) => stopPanning(event.pointerId));
  viewport?.addEventListener("pointercancel", (event) => stopPanning(event.pointerId));
  viewport?.addEventListener("lostpointercapture", (event) => stopPanning(event.pointerId));
  dialog.addEventListener("close", () => {
    stopPanning();
    const opener = mermaidDialogOpeners.get(dialog);
    mermaidDialogOpeners.delete(dialog);
    dialog.querySelector("[data-mermaid-dialog-canvas]")?.replaceChildren();
    if (opener?.isConnected) opener.focus();
  });
}

function openMermaidDiagram(figure: HTMLElement, opener: HTMLElement): void {
  const source = figure.querySelector<SVGSVGElement>(":scope > svg");
  const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="mermaid"]');
  const canvas = dialog?.querySelector<HTMLElement>("[data-mermaid-dialog-canvas]");
  if (!source || !dialog || !canvas) return;
  canvas.replaceChildren(source.cloneNode(true));
  prepareMermaidDialog(dialog);
  mermaidDialogOpeners.set(dialog, opener);
  openWebsiteDialog("mermaid");
  setMermaidZoom(dialog, 1);
}

function initialiseMermaidInteraction(): void {
  const controlledDocument = document as ControlledDocument;
  if (controlledDocument[mermaidInteractionController]) return;
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const zoomControl = target.closest<HTMLElement>(
      "[data-mermaid-zoom-in], [data-mermaid-zoom-out], [data-mermaid-zoom-reset]"
    );
    if (zoomControl) {
      const dialog = zoomControl.closest<HTMLDialogElement>('dialog[data-dialog="mermaid"]');
      const canvas = dialog?.querySelector<HTMLElement>("[data-mermaid-dialog-canvas]");
      if (!dialog || !canvas) return;
      const current = mermaidZoom(canvas);
      if (zoomControl.hasAttribute("data-mermaid-zoom-in")) {
        setMermaidZoom(dialog, current + MERMAID_ZOOM_STEP);
      } else if (zoomControl.hasAttribute("data-mermaid-zoom-out")) {
        setMermaidZoom(dialog, current - MERMAID_ZOOM_STEP);
      } else {
        setMermaidZoom(dialog, 1);
      }
      return;
    }
    const expand = target.closest<HTMLElement>("[data-mermaid-expand]");
    if (expand) {
      const figure = expand.closest<HTMLElement>("[data-mermaid-rendered]");
      if (figure) openMermaidDiagram(figure, expand);
      return;
    }
    if (target.closest("[data-copy-source], a[href], button, input, select, textarea")) return;
    const figure = target.closest<HTMLElement>("[data-mermaid-rendered]");
    const expansionControl = figure?.querySelector<HTMLElement>(":scope > [data-mermaid-expand]");
    if (figure && expansionControl) openMermaidDiagram(figure, expansionControl);
  });
  controlledDocument[mermaidInteractionController] = true;
}

export async function renderMermaid(): Promise<void> {
  initialiseMermaidInteraction();
  if (!watchesColorScheme) {
    watchesColorScheme = true;
    document.addEventListener(COLOR_SCHEME_EVENT, () => {
      const figures = Array.from(
        document.querySelectorAll<HTMLElement>("[data-mermaid-rendered]")
      );
      const dialog = document.querySelector<HTMLDialogElement>('dialog[data-dialog="mermaid"]');
      const opener = dialog ? mermaidDialogOpeners.get(dialog) : undefined;
      const focusedFigure = opener?.closest<HTMLElement>("[data-mermaid-rendered]");
      const focusedFigureIndex = focusedFigure ? figures.indexOf(focusedFigure) : -1;
      if (dialog?.open) dialog.close();
      for (const figure of figures) {
        const source = figure.querySelector<HTMLTemplateElement>("template[data-website-copy-source]")?.content.textContent;
        if (!source) continue;
        const pre = document.createElement("pre");
        pre.dataset.websiteMermaid = "true";
        pre.dataset.diagramLabel = figure.dataset.diagramLabel || "Diagram";
        const code = document.createElement("code");
        code.className = "language-mermaid";
        code.textContent = source;
        pre.append(code);
        figure.replaceWith(pre);
      }
      void renderMermaid().then(() => {
        if (focusedFigureIndex < 0) return;
        document.querySelectorAll<HTMLElement>("[data-mermaid-rendered]")
          [focusedFigureIndex]
          ?.querySelector<HTMLElement>(":scope > [data-mermaid-expand]")
          ?.focus();
      });
    });
  }
  const sources = sourceElements();
  if (sources.length === 0) return;
  await document.fonts?.ready;
  const bodyStyle = getComputedStyle(document.body);

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    fontFamily: bodyStyle.fontFamily || "system-ui, sans-serif",
    themeVariables: {
      fontSize: bodyStyle.fontSize || "16px",
      background: cssToken("--surface", "#ffffff"),
      primaryColor: cssToken("--violet-soft", "#ece9ff"),
      primaryTextColor: cssToken("--ink", "#202333"),
      primaryBorderColor: cssToken("--violet", "#6e5bd4"),
      lineColor: cssToken("--graphite", "#5e6678"),
      secondaryColor: cssToken("--teal-soft", "#dcefee"),
      tertiaryColor: cssToken("--frost", "#f7f8fc"),
      noteBkgColor: cssToken("--surface", "#ffffff"),
      noteTextColor: cssToken("--ink", "#202333")
    }
  });

  await Promise.all(
    sources.map(async (source, index) => {
      const code = source.matches("pre")
        ? source.querySelector("code")?.textContent ?? ""
        : source.textContent ?? "";
      if (!code.trim()) return;
      try {
        const id = `website-mermaid-${index}`;
        const rendered = await mermaid.render(id, code);
        const renderedSvg = parseMermaidSvg(rendered.svg);

        const figure = document.createElement("figure");
        figure.className = "mermaid-diagram";
        figure.dataset.mermaidRendered = "";
        const diagramLabel = source.dataset.diagramLabel || "Diagram";
        figure.dataset.diagramLabel = diagramLabel;
        const svg = document.importNode(renderedSvg, true);
        svg.setAttribute("role", "img");
        svg.setAttribute("aria-label", diagramLabel);
        figure.append(svg);
        source.replaceWith(figure);
        decorateSourceCopy(figure, code, "diagram");
        decorateExpansion(figure);
        const sourceTemplate = figure.querySelector<HTMLTemplateElement>("template[data-website-copy-source]");
        if (sourceTemplate) sourceTemplate.dataset.mermaidSource = "";
        rendered.bindFunctions?.(figure);
      } catch {
        source.dataset.mermaidError = "true";
        source.setAttribute("aria-label", "Diagram source; rendering failed");
      }
    })
  );
}
