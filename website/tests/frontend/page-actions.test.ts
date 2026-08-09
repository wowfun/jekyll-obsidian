// @vitest-environment happy-dom

import { beforeEach, describe, expect, it, vi } from "vitest";
import { initialisePageActions } from "../../src/frontend/page-actions";

function actionsMarkup(): string {
  return `
    <div data-page-actions data-markdown-url="/manual/guide.md" data-copy-success="Copied" data-copy-error="Copy failed">
      <button type="button" data-copy-page><span data-copy-page-label>Copy page</span></button>
      <details data-page-actions-menu>
        <summary>More page actions</summary>
        <button type="button" data-copy-page><span data-copy-page-label>Copy page</span></button>
        <a href="/manual/guide.md" target="_blank">View as Markdown</a>
        <p data-copy-page-error hidden></p>
      </details>
      <span role="status" aria-live="polite" data-copy-page-status></span>
    </div>`;
}

describe("page Markdown actions", () => {
  beforeEach(() => {
    document.body.innerHTML = actionsMarkup();
    history.replaceState({}, "", "/manual/guide/");
  });

  it("fetches and copies the generated Markdown resource verbatim", async () => {
    const source = "# Guide\n\nKeep [[wikilinks]].\n";
    const fetchMock = vi.spyOn(window, "fetch").mockResolvedValue(new Response(source, {
      status: 200,
      headers: { "Content-Type": "text/markdown" }
    }));
    const writeText = vi.fn(async () => undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText }
    });
    const cleanup = initialisePageActions();

    document.querySelector<HTMLButtonElement>("[data-copy-page]")!.click();

    await vi.waitFor(() => expect(writeText).toHaveBeenCalledWith(source));
    expect(fetchMock).toHaveBeenCalledWith(new URL("/manual/guide.md", window.location.href), {
      credentials: "same-origin",
      headers: { Accept: "text/markdown" },
      signal: expect.any(AbortSignal)
    });
    expect(document.querySelector("[data-copy-page-status]")?.textContent).toBe("Copied");
    expect([...document.querySelectorAll("[data-copy-page-label]")].map((node) => node.textContent))
      .toEqual(["Copied", "Copied"]);
    cleanup();
  });

  it("restores keyboard focus and the document selection after the copy fallback", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(new Response("# Guide\n", { status: 200 }));
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn(async () => { throw new Error("denied"); }) }
    });
    Object.defineProperty(document, "execCommand", {
      configurable: true,
      value: vi.fn(() => { throw new Error("copy rejected"); })
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
    const button = document.querySelector<HTMLButtonElement>("[data-copy-page]")!;
    button.focus();
    const cleanup = initialisePageActions();

    button.click();

    await vi.waitFor(() => expect(document.querySelector("[data-copy-page-status]")?.textContent)
      .toBe("Copy failed"));
    expect(document.activeElement).toBe(button);
    expect(document.getSelection()?.toString()).toBe("Keep this selection");
    cleanup();
  });

  it("closes the native menu with Escape and returns focus to its summary", () => {
    const menu = document.querySelector<HTMLDetailsElement>("details")!;
    const summary = menu.querySelector<HTMLElement>("summary")!;
    menu.open = true;
    const cleanup = initialisePageActions();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));

    expect(menu.open).toBe(false);
    expect(document.activeElement).toBe(summary);
    cleanup();
  });

  it("reports failure while leaving View as Markdown available", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(new Response("missing", { status: 404 }));
    const cleanup = initialisePageActions();

    document.querySelector<HTMLButtonElement>("[data-copy-page]")!.click();

    await vi.waitFor(() => expect(document.querySelector("[role='status']")?.textContent).toBe("Copy failed"));
    expect(document.querySelector<HTMLDetailsElement>("details")?.open).toBe(true);
    expect(document.querySelector<HTMLElement>("[data-copy-page-error]")?.hidden).toBe(false);
    expect(document.querySelector("[data-copy-page-error]")?.textContent).toBe("Copy failed");
    expect(document.querySelector<HTMLAnchorElement>("a")?.getAttribute("href")).toBe("/manual/guide.md");
    expect(document.querySelector<HTMLAnchorElement>("a")?.target).toBe("_blank");
    cleanup();
  });

  it("does not copy a stale page after navigation cleanup", async () => {
    let resolveOld: ((response: Response) => void) | undefined;
    const oldResponse = new Promise<Response>((resolve) => { resolveOld = resolve; });
    const fetchMock = vi.spyOn(window, "fetch")
      .mockImplementationOnce(() => oldResponse)
      .mockResolvedValueOnce(new Response("NEW", { status: 200 }));
    const writes: string[] = [];
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn(async (value: string) => { writes.push(value); }) }
    });

    const cleanupOld = initialisePageActions();
    document.querySelector<HTMLButtonElement>("[data-copy-page]")!.click();
    cleanupOld();

    document.body.innerHTML = actionsMarkup().replace("guide.md", "new.md");
    const cleanupNew = initialisePageActions();
    document.querySelector<HTMLButtonElement>("[data-copy-page]")!.click();
    await vi.waitFor(() => expect(writes).toEqual(["NEW"]));

    resolveOld!(new Response("OLD", { status: 200 }));
    await Promise.resolve();
    await Promise.resolve();
    expect(writes).toEqual(["NEW"]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    cleanupNew();
  });

  it("does not fall back to a stale copy after clipboard rejection", async () => {
    let rejectOld: ((error: Error) => void) | undefined;
    const oldWrite = new Promise<void>((_resolve, reject) => { rejectOld = reject; });
    vi.spyOn(window, "fetch")
      .mockResolvedValueOnce(new Response("OLD", { status: 200 }))
      .mockResolvedValueOnce(new Response("NEW", { status: 200 }));
    const writes: string[] = [];
    const writeText = vi.fn((value: string) => {
      if (value === "OLD") return oldWrite;
      writes.push(value);
      return Promise.resolve();
    });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText }
    });
    const execCommand = vi.fn(() => {
      writes.push(document.querySelector<HTMLTextAreaElement>("textarea")?.value || "");
      return true;
    });
    Object.defineProperty(document, "execCommand", { configurable: true, value: execCommand });

    const cleanupOld = initialisePageActions();
    document.querySelector<HTMLButtonElement>("[data-copy-page]")!.click();
    await vi.waitFor(() => expect(writeText).toHaveBeenCalledWith("OLD"));
    cleanupOld();

    document.body.innerHTML = actionsMarkup().replace("guide.md", "new.md");
    const cleanupNew = initialisePageActions();
    document.querySelector<HTMLButtonElement>("[data-copy-page]")!.click();
    await vi.waitFor(() => expect(writes).toEqual(["NEW"]));

    rejectOld!(new Error("permission changed"));
    await Promise.resolve();
    await Promise.resolve();
    expect(execCommand).not.toHaveBeenCalled();
    expect(writes).toEqual(["NEW"]);
    cleanupNew();
  });
});
