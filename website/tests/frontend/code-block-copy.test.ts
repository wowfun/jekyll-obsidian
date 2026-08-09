// @vitest-environment happy-dom

import { beforeEach, describe, expect, it, vi } from "vitest";
import { decorateSourceCopy, initialiseCodeBlockCopy } from "../../src/frontend/code-block-copy";

describe("code block copy actions", () => {
  beforeEach(() => {
    document.documentElement.lang = "en";
    document.documentElement.dir = "ltr";
    document.body.innerHTML = `
      <div class="note-content"
        data-copy-code-label="Copy code"
        data-copy-diagram-label="Copy diagram source"
        data-copy-formula-label="Copy formula source"
        data-copy-code-success="Copied"
        data-copy-code-error="Copy failed">
        <pre><code class="language-ts">const answer = 42;\n</code></pre>
        <pre>raw preformatted code\n</pre>
        <pre data-website-mermaid><code class="language-mermaid">graph TD; A--&gt;B</code></pre>
      </div>`;
  });

  it("labels injected UI in the site locale on a fallback-language page", () => {
    document.documentElement.lang = "zh-CN";
    document.documentElement.dir = "rtl";
    const content = document.querySelector<HTMLElement>(".note-content")!;
    content.lang = "en";
    content.dir = "ltr";
    content.dataset.copyCodeLabel = "复制代码";
    content.dataset.copyCodeSuccess = "已复制";
    content.dataset.copyCodeError = "复制失败";
    const cleanup = initialiseCodeBlockCopy();

    const button = document.querySelector<HTMLButtonElement>("button[data-copy-code]")!;
    const status = document.querySelector<HTMLElement>("[role='status']")!;
    expect(button.lang).toBe("zh-CN");
    expect(button.dir).toBe("rtl");
    expect(status.lang).toBe("zh-CN");
    expect(status.dir).toBe("rtl");
    expect(button.closest<HTMLElement>(".note-content")?.lang).toBe("en");
    cleanup();
  });

  it("adds a sibling button to each code block but not Mermaid source", () => {
    const cleanup = initialiseCodeBlockCopy();

    const wrapper = document.querySelector<HTMLElement>("[data-code-block-copy]");
    const button = wrapper?.querySelector<HTMLButtonElement>("[data-copy-code]");
    expect(wrapper?.children[0]?.tagName).toBe("PRE");
    expect(wrapper?.children[1]).toBe(button);
    expect(wrapper?.querySelector("pre button")).toBeNull();
    expect(button?.type).toBe("button");
    expect(button?.getAttribute("aria-label")).toBe("Copy code");
    expect(button?.children).toHaveLength(1);
    expect(button?.firstElementChild?.tagName).toBe("svg");
    expect(button?.querySelector(".code-block-copy__label")).toBeNull();
    expect(button?.textContent).toBe("");
    expect(document.querySelector("pre[data-website-mermaid]")?.parentElement?.classList.contains("note-content"))
      .toBe(true);
    expect(document.querySelectorAll("button[data-copy-code]")).toHaveLength(2);

    cleanup();
    expect(document.querySelector("[data-code-block-copy]")).toBeNull();
    expect(document.querySelectorAll(".note-content > pre")).toHaveLength(3);
  });

  it("copies the rendered code exactly and announces localized success", async () => {
    const writeText = vi.fn(async () => undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText }
    });
    const cleanup = initialiseCodeBlockCopy();

    document.querySelector<HTMLButtonElement>("button[data-copy-code]")!.click();

    await vi.waitFor(() => expect(writeText).toHaveBeenCalledWith("const answer = 42;\n"));
    const button = document.querySelector<HTMLButtonElement>("button[data-copy-code]")!;
    await vi.waitFor(() => expect(button.getAttribute("aria-label")).toBe("Copied"));
    expect(button.getAttribute("aria-label")).toBe("Copied");
    expect(button.title).toBe("Copied");
    expect(button.textContent).toBe("");
    expect(button.dataset.copyState).toBe("success");
    expect(button.querySelector("[data-copy-icon='success']")).not.toBeNull();
    expect(document.querySelector("[role='status']")?.textContent).toBe("Copied");
    cleanup();
  });

  it("handles dynamically rendered diagram and formula sources through one delegated action", async () => {
    const writeText = vi.fn(async () => undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText }
    });
    const cleanup = initialiseCodeBlockCopy();
    const root = document.querySelector<HTMLElement>(".note-content")!;
    const diagram = document.createElement("figure");
    const formula = document.createElement("span");
    root.append(diagram, formula);
    decorateSourceCopy(diagram, "flowchart LR\n  A-->|x & y|B\n", "diagram");
    decorateSourceCopy(formula, String.raw`\operatorname{arg\,max}_{x < y} f(x)`, "formula");

    const actions = root.querySelectorAll<HTMLButtonElement>("button[data-copy-source]");
    expect(actions).toHaveLength(4);
    const diagramAction = actions.item(2);
    const formulaAction = actions.item(3);
    expect(diagramAction.getAttribute("aria-label")).toBe("Copy diagram source");
    expect(formulaAction.getAttribute("aria-label")).toBe("Copy formula source");
    expect(diagram.querySelector<HTMLTemplateElement>("template[data-website-copy-source]")?.content.textContent)
      .toBe("flowchart LR\n  A-->|x & y|B\n");

    diagramAction.click();
    await vi.waitFor(() => expect(writeText).toHaveBeenLastCalledWith("flowchart LR\n  A-->|x & y|B\n"));
    formulaAction.click();
    await vi.waitFor(() => expect(writeText).toHaveBeenLastCalledWith(String.raw`\operatorname{arg\,max}_{x < y} f(x)`));
    await vi.waitFor(() => expect(formulaAction.dataset.copyState).toBe("success"));
    cleanup();
  });

  it("shows an error icon when both clipboard paths fail", async () => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn(async () => { throw new Error("denied"); }) }
    });
    Object.defineProperty(document, "execCommand", {
      configurable: true,
      value: vi.fn(() => false)
    });
    const cleanup = initialiseCodeBlockCopy();
    const button = document.querySelector<HTMLButtonElement>("button[data-copy-code]")!;

    button.click();

    await vi.waitFor(() => expect(button.dataset.copyState).toBe("error"));
    expect(button.getAttribute("aria-label")).toBe("Copy failed");
    expect(button.querySelector("[data-copy-icon='error']")).not.toBeNull();
    cleanup();
  });

  it("returns visible success feedback to the copy icon after the acknowledgement window", async () => {
    vi.useFakeTimers();
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn(async () => undefined) }
    });
    const cleanup = initialiseCodeBlockCopy();
    const button = document.querySelector<HTMLButtonElement>("button[data-copy-code]")!;

    try {
      button.click();
      await vi.advanceTimersByTimeAsync(0);
      expect(button.dataset.copyState).toBe("success");
      expect(button.querySelector("[data-copy-icon='success']")).not.toBeNull();

      await vi.advanceTimersByTimeAsync(2_000);
      expect(button.dataset.copyState).toBe("idle");
      expect(button.getAttribute("aria-label")).toBe("Copy code");
      expect(button.querySelector("[data-copy-icon='idle']")).not.toBeNull();
    } finally {
      cleanup();
      vi.useRealTimers();
    }
  });

  it("uses the same selection fallback as Copy page", async () => {
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn(async () => { throw new Error("denied"); }) }
    });
    let selected = "";
    Object.defineProperty(document, "execCommand", {
      configurable: true,
      value: vi.fn(() => {
        selected = document.querySelector<HTMLTextAreaElement>("textarea")?.value || "";
        return true;
      })
    });
    document.body.insertAdjacentHTML("beforeend", '<p id="selection-source">Keep this selection</p>');
    const selectedText = document.querySelector<HTMLElement>("#selection-source")!;
    const originalRange = document.createRange();
    originalRange.selectNodeContents(selectedText);
    const selection = document.getSelection()!;
    selection.removeAllRanges();
    selection.addRange(originalRange);
    vi.spyOn(HTMLTextAreaElement.prototype, "select").mockImplementation(function selectFallbackField(
      this: HTMLTextAreaElement
    ) {
      this.focus();
      document.getSelection()?.removeAllRanges();
    });
    const cleanup = initialiseCodeBlockCopy();
    const button = document.querySelector<HTMLButtonElement>("button[data-copy-code]")!;
    button.focus();

    button.click();

    await vi.waitFor(() => expect(selected).toBe("const answer = 42;\n"));
    await vi.waitFor(() => expect(document.querySelector("[role='status']")?.textContent).toBe("Copied"));
    expect(document.activeElement).toBe(button);
    expect(document.getSelection()?.toString()).toBe("Keep this selection");
    cleanup();
  });

  it("stays interactive across a persisted page lifecycle", async () => {
    const writeText = vi.fn(async () => undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText }
    });
    const cleanup = initialiseCodeBlockCopy();
    const pagehide = new Event("pagehide");
    Object.defineProperty(pagehide, "persisted", { value: true });
    window.dispatchEvent(pagehide);
    const pageshow = new Event("pageshow");
    Object.defineProperty(pageshow, "persisted", { value: true });
    window.dispatchEvent(pageshow);

    document.querySelector<HTMLButtonElement>("button[data-copy-code]")!.click();

    await vi.waitFor(() => expect(writeText).toHaveBeenCalledWith("const answer = 42;\n"));
    cleanup();
  });
});
