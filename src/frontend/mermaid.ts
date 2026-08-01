import mermaid from "mermaid";

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
  const sources = sourceElements();
  if (sources.length === 0) return;

  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    fontFamily: '"Recursive Variable", system-ui, sans-serif',
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
        const id = `obsidian-mermaid-${index}`;
        const rendered = await mermaid.render(id, code);
        const parsed = new DOMParser().parseFromString(rendered.svg, "image/svg+xml");
        if (parsed.querySelector("parsererror")) throw new Error("Invalid Mermaid SVG");

        const figure = document.createElement("figure");
        figure.className = "mermaid-diagram";
        figure.dataset.mermaidRendered = "";
        const svg = document.importNode(parsed.documentElement, true);
        svg.setAttribute("role", "img");
        svg.setAttribute("aria-label", source.dataset.diagramLabel || "Diagram");
        figure.append(svg);
        source.replaceWith(figure);
        rendered.bindFunctions?.(figure);
      } catch {
        source.dataset.mermaidError = "true";
        source.setAttribute("aria-label", "Diagram source; rendering failed");
      }
    })
  );
}
