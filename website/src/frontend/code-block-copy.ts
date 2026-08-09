import { writeClipboard } from "./clipboard";

const COPY_RESET_DELAY = 2_000;
const SVG_NAMESPACE = "http://www.w3.org/2000/svg";

export type SourceCopyKind = "code" | "diagram" | "formula";
type CopyState = "idle" | "success" | "error";

type PendingCopy = {
  request?: AbortController;
  resetTimer?: number;
};

const DEFAULT_LABELS: Record<SourceCopyKind, string> = {
  code: "Copy code",
  diagram: "Copy diagram source",
  formula: "Copy formula source"
};

function isMermaidSource(pre: HTMLPreElement): boolean {
  return pre.hasAttribute("data-website-mermaid")
    || pre.getAttribute("lang")?.toLocaleLowerCase("und") === "mermaid"
    || Boolean(pre.querySelector(":scope > code.language-mermaid"));
}

function sourceCopyIcon(state: CopyState): SVGSVGElement {
  const icon = document.createElementNS(SVG_NAMESPACE, "svg");
  icon.classList.add("source-copy__icon");
  icon.dataset.copyIcon = state;
  icon.setAttribute("viewBox", "0 0 20 20");
  icon.setAttribute("aria-hidden", "true");

  if (state === "success") {
    const path = document.createElementNS(SVG_NAMESPACE, "path");
    path.setAttribute("d", "m3.5 10.5 4 4 9-9");
    icon.append(path);
    return icon;
  }

  if (state === "error") {
    const first = document.createElementNS(SVG_NAMESPACE, "path");
    const second = document.createElementNS(SVG_NAMESPACE, "path");
    first.setAttribute("d", "m5 5 10 10");
    second.setAttribute("d", "m15 5-10 10");
    icon.append(first, second);
    return icon;
  }

  const back = document.createElementNS(SVG_NAMESPACE, "path");
  back.setAttribute("d", "M7 5H4.5A1.5 1.5 0 0 0 3 6.5v9A1.5 1.5 0 0 0 4.5 17h7a1.5 1.5 0 0 0 1.5-1.5V13");
  const front = document.createElementNS(SVG_NAMESPACE, "rect");
  front.setAttribute("x", "7");
  front.setAttribute("y", "3");
  front.setAttribute("width", "10");
  front.setAttribute("height", "10");
  front.setAttribute("rx", "1.5");
  icon.append(back, front);
  return icon;
}

function labelFor(root: HTMLElement | null, kind: SourceCopyKind): string {
  if (kind === "diagram") return root?.dataset.copyDiagramLabel || DEFAULT_LABELS.diagram;
  if (kind === "formula") return root?.dataset.copyFormulaLabel || DEFAULT_LABELS.formula;
  return root?.dataset.copyCodeLabel || DEFAULT_LABELS.code;
}

function setButtonState(button: HTMLButtonElement, state: CopyState, label: string): void {
  button.dataset.copyState = state;
  button.setAttribute("aria-label", label);
  button.title = label;
  button.replaceChildren(sourceCopyIcon(state));
}

/**
 * Decorates rendered source without binding an event listener. The page-level
 * delegated listener remains stable while Mermaid and MathJax replace nodes.
 */
export function decorateSourceCopy(host: HTMLElement, source: string, kind: SourceCopyKind): void {
  const root = host.closest<HTMLElement>(".note-content");
  const label = labelFor(root, kind);
  host.dataset.sourceCopy = kind;

  let sourceTemplate = host.querySelector<HTMLTemplateElement>(":scope > template[data-website-copy-source]");
  if (!sourceTemplate) {
    sourceTemplate = document.createElement("template");
    sourceTemplate.dataset.websiteCopySource = "";
    host.append(sourceTemplate);
  }
  sourceTemplate.content.textContent = source;

  let button = host.querySelector<HTMLButtonElement>(":scope > button[data-copy-source]");
  if (!button) {
    button = document.createElement("button");
    button.className = "source-copy__button";
    button.type = "button";
    button.dataset.copySource = "";
    button.lang = document.documentElement.lang;
    button.dir = document.documentElement.dir;
    host.append(button);
  }
  button.dataset.copyKind = kind;
  button.dataset.copyLabel = label;
  if (kind === "code") button.dataset.copyCode = "";
  setButtonState(button, "idle", label);

  let status = host.querySelector<HTMLElement>(":scope > [data-copy-source-status]");
  if (!status) {
    status = document.createElement("span");
    status.className = "visually-hidden";
    status.dataset.copySourceStatus = "";
    status.setAttribute("role", "status");
    status.setAttribute("aria-live", "polite");
    status.lang = document.documentElement.lang;
    status.dir = document.documentElement.dir;
    host.append(status);
  }
  host.append(button, status, sourceTemplate);
}

export function initialiseCodeBlockCopy(): () => void {
  const wrappers: HTMLElement[] = [];
  const roots = Array.from(document.querySelectorAll<HTMLElement>(".note-content"));
  const pending = new Map<HTMLButtonElement, PendingCopy>();
  let disposed = false;

  for (const root of roots) {
    for (const pre of root.querySelectorAll<HTMLPreElement>("pre")) {
      if (isMermaidSource(pre) || pre.closest("[data-code-block-copy]")) continue;
      const wrapper = document.createElement("div");
      wrapper.className = "code-block-copy";
      wrapper.dataset.codeBlockCopy = "";
      const code = pre.querySelector<HTMLElement>(":scope > code");
      const source = code?.textContent ?? pre.textContent ?? "";
      pre.replaceWith(wrapper);
      wrapper.append(pre);
      decorateSourceCopy(wrapper, source, "code");
      wrappers.push(wrapper);
    }
  }

  const handleClick = (event: Event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const button = target.closest<HTMLButtonElement>("button[data-copy-source]");
    if (!button) return;
    const root = button.closest<HTMLElement>(".note-content");
    if (!root || !roots.includes(root)) return;
    const host = button.closest<HTMLElement>("[data-source-copy]");
    const source = host?.querySelector<HTMLTemplateElement>(":scope > template[data-website-copy-source]")
      ?.content.textContent;
    if (source === undefined) return;

    const previous = pending.get(button);
    previous?.request?.abort();
    window.clearTimeout(previous?.resetTimer);
    const request = new AbortController();
    const state: PendingCopy = { request };
    pending.set(button, state);
    const label = button.dataset.copyLabel || DEFAULT_LABELS.code;
    const success = root.dataset.copyCodeSuccess || "Copied";
    const error = root.dataset.copyCodeError || "Copy failed";
    const status = host?.querySelector<HTMLElement>(":scope > [data-copy-source-status]");
    if (status) status.textContent = "";

    void writeClipboard(source, request.signal)
      .then(() => {
        if (disposed || request.signal.aborted || pending.get(button) !== state || !root.contains(button)) return;
        setButtonState(button, "success", success);
        if (status) status.textContent = success;
      })
      .catch(() => {
        if (disposed || request.signal.aborted || pending.get(button) !== state || !root.contains(button)) return;
        setButtonState(button, "error", error);
        if (status) status.textContent = error;
      })
      .finally(() => {
        if (pending.get(button) !== state) return;
        delete state.request;
        if (disposed) return;
        state.resetTimer = window.setTimeout(() => {
          if (pending.get(button) !== state || !root.contains(button)) return;
          setButtonState(button, "idle", label);
          pending.delete(button);
        }, COPY_RESET_DELAY);
      });
  };

  roots.forEach((root) => root.addEventListener("click", handleClick));

  return () => {
    disposed = true;
    roots.forEach((root) => root.removeEventListener("click", handleClick));
    for (const state of pending.values()) {
      state.request?.abort();
      window.clearTimeout(state.resetTimer);
    }
    pending.clear();
    for (const wrapper of wrappers) {
      const pre = wrapper.querySelector<HTMLPreElement>(":scope > pre");
      if (pre) wrapper.replaceWith(pre);
      else wrapper.remove();
    }
  };
}
