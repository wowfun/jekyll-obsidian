import mermaid from "mermaid";
import { COLOR_SCHEME_EVENT } from "./color-scheme";

let watchesColorScheme = false;

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

export async function renderMermaid(): Promise<void> {
  if (!watchesColorScheme) {
    watchesColorScheme = true;
    document.addEventListener(COLOR_SCHEME_EVENT, () => {
      for (const figure of document.querySelectorAll<HTMLElement>("[data-mermaid-rendered]")) {
        const source = figure.querySelector<HTMLTemplateElement>("template[data-mermaid-source]")?.content.textContent;
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
      void renderMermaid();
    });
  }
  const sources = sourceElements();
  if (sources.length === 0) return;

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    fontFamily: getComputedStyle(document.body).fontFamily || "system-ui, sans-serif",
    themeVariables: {
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
        const parsed = new DOMParser().parseFromString(rendered.svg, "image/svg+xml");
        if (parsed.querySelector("parsererror")) throw new Error("Invalid Mermaid SVG");

        const figure = document.createElement("figure");
        figure.className = "mermaid-diagram";
        figure.dataset.mermaidRendered = "";
        const diagramLabel = source.dataset.diagramLabel || "Diagram";
        figure.dataset.diagramLabel = diagramLabel;
        const svg = document.importNode(parsed.documentElement, true);
        svg.setAttribute("role", "img");
        svg.setAttribute("aria-label", diagramLabel);
        const sourceTemplate = document.createElement("template");
        sourceTemplate.dataset.mermaidSource = "";
        sourceTemplate.content.textContent = code;
        figure.append(svg, sourceTemplate);
        source.replaceWith(figure);
        rendered.bindFunctions?.(figure);
      } catch {
        source.dataset.mermaidError = "true";
        source.setAttribute("aria-label", "Diagram source; rendering failed");
      }
    })
  );
}
