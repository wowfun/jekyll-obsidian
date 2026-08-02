import { mathjax } from "mathjax-full/js/mathjax.js";
import { TeX } from "mathjax-full/js/input/tex.js";
import { SVG } from "mathjax-full/js/output/svg.js";
import { liteAdaptor } from "mathjax-full/js/adaptors/liteAdaptor.js";
import { RegisterHTMLHandler } from "mathjax-full/js/handlers/html.js";
import { AllPackages } from "mathjax-full/js/input/tex/AllPackages.js";

function isDisplayMath(element: HTMLElement): boolean {
  return (
    element.classList.contains("math-display") ||
    element.dataset.math === "display" ||
    element.dataset.mathStyle === "display"
  );
}

export function renderMath(): void {
  const elements = Array.from(
    document.querySelectorAll<HTMLElement>(
      "[data-math]:not([data-math-rendered]), [data-math-style]:not([data-math-rendered]), .math-inline:not([data-math-rendered]), .math-display:not([data-math-rendered])"
    )
  );
  if (elements.length === 0) return;

  const adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);
  const documentModel = mathjax.document("", {
    InputJax: new TeX({ packages: AllPackages }),
    OutputJax: new SVG({ fontCache: "local" })
  });

  for (const element of elements) {
    const source = element.textContent ?? "";
    if (!source.trim()) continue;
    try {
      const node = documentModel.convert(source, { display: isDisplayMath(element) });
      const markup = adaptor.outerHTML(node);
      const parsed = new DOMParser().parseFromString(markup, "text/html");
      const rendered = parsed.body.firstElementChild;
      if (!rendered) throw new Error("MathJax did not produce output");
      element.replaceChildren(document.importNode(rendered, true));
      element.dataset.mathRendered = "true";
      element.setAttribute("aria-label", source);
    } catch {
      element.dataset.mathError = "true";
    }
  }
}
