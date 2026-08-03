import { beforeEach, describe, expect, it, vi } from "vitest";
import { activateSearch } from "../../src/frontend/search";

describe("website search", () => {
  beforeEach(() => {
    document.head.replaceChildren();
    document.body.replaceChildren();
    document.head.insertAdjacentHTML(
      "beforeend",
      '<meta name="website:search" content="/project/assets/website/search.v1.json"><meta name="website:search-worker" content="/project/assets/website/search-worker.js">'
    );
  });

  it("finds CJK notes through the stable unigram/bigram index", async () => {
    class SearchWorker extends EventTarget {
      postMessage(message: { type: string; id?: number }): void {
        queueMicrotask(() => {
          const data = message.type === "init"
            ? { type: "ready" }
            : {
                type: "results",
                id: message.id,
                results: [{ title: "知识花园", url: "/project/zh/", tags: ["中文"] }]
              };
          this.dispatchEvent(new MessageEvent("message", { data }));
        });
      }
    }
    vi.stubGlobal("Worker", SearchWorker);
    document.body.insertAdjacentHTML(
      "beforeend",
      `<dialog><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>`
    );
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    await activateSearch(dialog);
    const input = dialog.querySelector<HTMLInputElement>("input")!;

    input.value = "花园";
    input.dispatchEvent(new InputEvent("input", { bubbles: true }));

    await vi.waitFor(() => expect(dialog.querySelector("[data-search-status]")?.textContent).toMatch(/1 note/));
    expect(dialog.querySelector<HTMLAnchorElement>("a")?.href).toContain("/project/zh/");
    expect(dialog.querySelector("a")?.textContent).toContain("知识花园");
  });

  it("does not restore stale results after the query is cleared", async () => {
    class SearchWorker extends EventTarget {
      static instance: SearchWorker;
      messages: Array<{ type: string; id?: number }> = [];

      constructor() {
        super();
        SearchWorker.instance = this;
      }

      postMessage(message: { type: string; id?: number }): void {
        this.messages.push(message);
        if (message.type === "init") {
          queueMicrotask(() => this.dispatchEvent(new MessageEvent("message", { data: { type: "ready" } })));
        }
      }
    }
    vi.stubGlobal("Worker", SearchWorker);
    document.body.insertAdjacentHTML(
      "beforeend",
      `<dialog><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>`
    );
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    await activateSearch(dialog);
    const input = dialog.querySelector<HTMLInputElement>("input")!;

    input.value = "old";
    input.dispatchEvent(new InputEvent("input", { bubbles: true }));
    const staleId = SearchWorker.instance.messages.at(-1)?.id;
    input.value = "";
    input.dispatchEvent(new InputEvent("input", { bubbles: true }));
    SearchWorker.instance.dispatchEvent(new MessageEvent("message", {
      data: {
        type: "results",
        id: staleId,
        results: [{ title: "Stale", url: "/stale/", tags: [] }]
      }
    }));

    expect(dialog.querySelectorAll("[data-search-results] a")).toHaveLength(0);
    expect(dialog.querySelector("[data-search-status]")?.textContent).toBe("Type a title, tag, or phrase.");
  });

  it("uses localized status templates from the page catalog", async () => {
    class SearchWorker extends EventTarget {
      postMessage(message: { type: string; id?: number }): void {
        queueMicrotask(() => this.dispatchEvent(new MessageEvent("message", {
          data: message.type === "init"
            ? { type: "ready" }
            : { type: "results", id: message.id, results: [] }
        })));
      }
    }
    vi.stubGlobal("Worker", SearchWorker);
    document.body.insertAdjacentHTML(
      "beforeend",
      `<dialog data-search-loading="正在载入…" data-search-prompt="请输入关键词。" data-search-no-results="未找到“{query}”。"><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>`
    );
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    await activateSearch(dialog);
    const input = dialog.querySelector<HTMLInputElement>("input")!;
    expect(dialog.querySelector("[data-search-status]")?.textContent).toBe("请输入关键词。");

    input.value = "花园";
    input.dispatchEvent(new InputEvent("input", { bubbles: true }));
    await vi.waitFor(() => expect(dialog.querySelector("[data-search-status]")?.textContent).toBe("未找到“花园”。"));
  });
});
