import { mathjax } from "@mathjax/src/js/mathjax.js";
import { TeX } from "@mathjax/src/js/input/tex.js";
import { SVG } from "@mathjax/src/js/output/svg.js";
import { liteAdaptor } from "@mathjax/src/js/adaptors/liteAdaptor.js";
import { RegisterHTMLHandler } from "@mathjax/src/js/handlers/html.js";
import "@mathjax/src/js/util/asyncLoad/esm.js";
import "@mathjax/src/js/input/tex/base/BaseConfiguration.js";
import "@mathjax/src/js/input/tex/action/ActionConfiguration.js";
import "@mathjax/src/js/input/tex/ams/AmsConfiguration.js";
import "@mathjax/src/js/input/tex/amscd/AmsCdConfiguration.js";
import "@mathjax/src/js/input/tex/bbox/BboxConfiguration.js";
import "@mathjax/src/js/input/tex/boldsymbol/BoldsymbolConfiguration.js";
import "@mathjax/src/js/input/tex/braket/BraketConfiguration.js";
import "@mathjax/src/js/input/tex/bussproofs/BussproofsConfiguration.js";
import "@mathjax/src/js/input/tex/cancel/CancelConfiguration.js";
import "@mathjax/src/js/input/tex/cases/CasesConfiguration.js";
import "@mathjax/src/js/input/tex/centernot/CenternotConfiguration.js";
import "@mathjax/src/js/input/tex/color/ColorConfiguration.js";
import "@mathjax/src/js/input/tex/colortbl/ColortblConfiguration.js";
import "@mathjax/src/js/input/tex/configmacros/ConfigMacrosConfiguration.js";
import "@mathjax/src/js/input/tex/empheq/EmpheqConfiguration.js";
import "@mathjax/src/js/input/tex/enclose/EncloseConfiguration.js";
import "@mathjax/src/js/input/tex/extpfeil/ExtpfeilConfiguration.js";
import "@mathjax/src/js/input/tex/gensymb/GensymbConfiguration.js";
import "@mathjax/src/js/input/tex/html/HtmlConfiguration.js";
import "@mathjax/src/js/input/tex/mathtools/MathtoolsConfiguration.js";
import "@mathjax/src/js/input/tex/mhchem/MhchemConfiguration.js";
import "@mathjax/src/js/input/tex/newcommand/NewcommandConfiguration.js";
import "@mathjax/src/js/input/tex/noerrors/NoErrorsConfiguration.js";
import "@mathjax/src/js/input/tex/noundefined/NoUndefinedConfiguration.js";
import "@mathjax/src/js/input/tex/tagformat/TagFormatConfiguration.js";
import "@mathjax/src/js/input/tex/textcomp/TextcompConfiguration.js";
import "@mathjax/src/js/input/tex/textmacros/TextMacrosConfiguration.js";
import "@mathjax/src/js/input/tex/unicode/UnicodeConfiguration.js";
import "@mathjax/src/js/input/tex/upgreek/UpgreekConfiguration.js";
import "@mathjax/src/js/input/tex/verb/VerbConfiguration.js";

const texPackages = [
  "base",
  "action",
  "ams",
  "amscd",
  "bbox",
  "boldsymbol",
  "braket",
  "bussproofs",
  "cancel",
  "cases",
  "centernot",
  "color",
  "colortbl",
  "empheq",
  "enclose",
  "extpfeil",
  "gensymb",
  "html",
  "mathtools",
  "mhchem",
  "newcommand",
  "noerrors",
  "noundefined",
  "upgreek",
  "unicode",
  "verb",
  "configmacros",
  "tagformat",
  "textcomp",
  "textmacros"
];

function isDisplayMath(element: HTMLElement): boolean {
  return (
    element.classList.contains("math-display") ||
    element.dataset.math === "display" ||
    element.dataset.mathStyle === "display"
  );
}

export async function renderMath(): Promise<void> {
  const elements = Array.from(
    document.querySelectorAll<HTMLElement>(
      "[data-math]:not([data-math-rendered]), [data-math-style]:not([data-math-rendered]), .math-inline:not([data-math-rendered]), .math-display:not([data-math-rendered])"
    )
  );
  if (elements.length === 0) return;

  const adaptor = liteAdaptor();
  RegisterHTMLHandler(adaptor);
  const documentModel = mathjax.document("", {
    InputJax: new TeX({ packages: texPackages }),
    OutputJax: new SVG({ fontCache: "local" })
  });

  for (const element of elements) {
    const source = element.textContent ?? "";
    if (!source.trim()) continue;
    try {
      const node = await documentModel.convertPromise(source, {
        display: isDisplayMath(element)
      });
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
