import mermaid from "mermaid";
import { COLOR_SCHEME_EVENT } from "./color-scheme";
import { decorateSourceCopy } from "./code-block-copy";
import {
  activeMediaViewerOpener,
  closeMediaViewer,
  createMediaExpandIcon,
  openMediaViewer
} from "./media-viewer";

let watchesColorScheme = false;
const mermaidInteractionController = Symbol.for("jekyll-obsidian.mermaid-interaction-controller");

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
  button.append(createMediaExpandIcon());
  figure.append(button);
}

function openMermaidDiagram(figure: HTMLElement, opener: HTMLElement): void {
  const source = figure.querySelector<SVGSVGElement>(":scope > svg");
  const root = figure.closest<HTMLElement>(".note-content");
  if (!source) return;
  openMediaViewer({
    source,
    opener,
    kind: "mermaid",
    title: figure.dataset.diagramLabel || "Diagram",
    closeLabel: root?.dataset.closeDiagramLabel || "Close diagram",
    lang: root?.lang || document.documentElement.lang,
    dir: root?.dir || document.documentElement.dir
  });
}

function initialiseMermaidInteraction(): void {
  const controlledDocument = document as ControlledDocument;
  if (controlledDocument[mermaidInteractionController]) return;
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
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
      const opener = activeMediaViewerOpener();
      const focusedFigure = opener?.closest<HTMLElement>("[data-mermaid-rendered]");
      const focusedFigureIndex = focusedFigure ? figures.indexOf(focusedFigure) : -1;
      if (focusedFigureIndex >= 0) closeMediaViewer();
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
