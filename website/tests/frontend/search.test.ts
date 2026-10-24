import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { activateSearch, disposeSearch } from "../../src/frontend/search";

describe("website search", () => {
  afterEach(() => { vi.useRealTimers(); });

  it("settles readiness when the initial worker message throws synchronously", async () => {
    class ThrowingWorker extends EventTarget {
      postMessage() { throw new Error("Cannot send initialization"); }
      terminate = vi.fn();
    }
    vi.stubGlobal("Worker", ThrowingWorker);
    document.body.innerHTML = '<dialog><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>';
    const dialog = document.querySelector<HTMLDialogElement>('dialog')!;
    await expect(activateSearch(dialog)).rejects.toThrow("Cannot send initialization");
    expect(dialog.querySelector('[data-search-status]')!.textContent).toContain('Edit your query');
    disposeSearch(dialog);
  });

  it.each(["loading", "ready", "failed"])("disposes a replaced %s dialog without retaining listeners", async (state) => {
    vi.useFakeTimers();
    let worker!: DisposableWorker;
    class DisposableWorker extends EventTarget {
      postMessage = vi.fn();
      terminate = vi.fn();
      constructor() { super(); worker = this; }
    }
    vi.stubGlobal("Worker", DisposableWorker);
    document.body.innerHTML = '<dialog><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>';
    const dialog = document.querySelector<HTMLDialogElement>('dialog')!;
    const pending = activateSearch(dialog);
    if (state !== "loading") {
      worker.dispatchEvent(new MessageEvent('message', { data: { type: 'ready' } }));
      await pending;
    }
    if (state === "failed") worker.dispatchEvent(new Event("error"));
    const settled = state !== "loading" ? pending : expect(pending).rejects.toMatchObject({ name: 'AbortError' });
    dialog.remove();
    disposeSearch(dialog);
    await settled;
    expect(worker.terminate).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
    dialog.querySelector('input')!.value = 'ignored';
    dialog.querySelector('input')!.dispatchEvent(new Event('input'));
    expect(worker.postMessage.mock.calls).toHaveLength(1);
    worker.dispatchEvent(new MessageEvent('message', { data: { type: 'ready' } }));
    expect(dialog.dataset.searchReady).toBeUndefined();
    disposeSearch(dialog);
    expect(worker.terminate).toHaveBeenCalledTimes(1);
  });

  it("retries a failed worker when the reader edits the query without closing search", async () => {
    const workers: RetryWorker[] = [];
    class RetryWorker extends EventTarget {
      postMessage = vi.fn();
      terminate = vi.fn();
      constructor() { super(); workers.push(this); }
      ready() { this.dispatchEvent(new MessageEvent("message", { data: { type: "ready" } })); }
    }
    vi.stubGlobal("Worker", RetryWorker);
    document.body.innerHTML = '<dialog open data-search-retry="修改搜索词后重试"><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>';
    const dialog = document.querySelector<HTMLDialogElement>('dialog')!;
    const pending = activateSearch(dialog);
    workers[0]!.ready();
    await pending;
    const input = dialog.querySelector('input')!;
    input.focus();
    workers[0]!.dispatchEvent(new Event('error'));
    expect(dialog.querySelector('[data-search-status]')!.textContent).toBe('修改搜索词后重试');
    input.value = 'retry';
    input.dispatchEvent(new Event('input'));
    expect(workers).toHaveLength(2);
    input.value = 'latest';
    input.dispatchEvent(new Event('input'));
    expect(workers).toHaveLength(2);
    workers[1]!.ready();
    await activateSearch(dialog);
    expect(workers[1]!.postMessage).toHaveBeenLastCalledWith({ type: 'query', id: 1, query: 'latest' });
    expect(document.activeElement).toBe(input);
    expect(dialog.open).toBe(true);
  });

  it.each(["timeout", "worker message", "worker event"])("recovers from %s failures without duplicate query listeners", async (failure) => {
    vi.useFakeTimers();
    const workers: FailingWorker[] = [];
    class FailingWorker extends EventTarget {
      postMessage = vi.fn();
      terminate = vi.fn();
      constructor() { super(); workers.push(this); }
      ready() { this.dispatchEvent(new MessageEvent("message", { data: { type: "ready" } })); }
    }
    vi.stubGlobal("Worker", FailingWorker);
    document.body.innerHTML = '<dialog data-search-retry="搜索不可用"><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>';
    const dialog = document.querySelector<HTMLDialogElement>('dialog')!;
    const pending = activateSearch(dialog);
    if (failure === "timeout") {
      const rejected = expect(pending).rejects.toThrow();
      await vi.advanceTimersByTimeAsync(15_000);
      await rejected;
    } else {
      workers[0]!.ready();
      await pending;
      dialog.querySelector('[data-search-results]')!.innerHTML = '<li>Old result</li>';
      workers[0]!.dispatchEvent(failure === "worker message"
        ? new MessageEvent("message", { data: { type: "error", message: "Failed" } }) : new Event("error"));
    }
    expect(workers[0]!.terminate).toHaveBeenCalledTimes(1);
    expect(dialog.dataset.searchReady).toBeUndefined();
    expect(dialog.querySelector('[data-search-status]')!.textContent).toBe('搜索不可用');
    expect(dialog.querySelector('[data-search-results]')!.children).toHaveLength(0);
    const reopened = activateSearch(dialog);
    expect(workers).toHaveLength(2);
    workers[1]!.ready();
    await reopened;
    workers[0]!.dispatchEvent(new MessageEvent("message", { data: {
      type: "results", id: 1, results: [{ title: "Retired worker", url: "/old/", tags: [] }]
    } }));
    expect(dialog.querySelector('[data-search-results]')!.children).toHaveLength(0);
    const input = dialog.querySelector('input')!;
    input.value = 'test';
    input.dispatchEvent(new Event('input'));
    expect(workers[1]!.postMessage.mock.calls.filter(([message]) => message.type === 'query')).toHaveLength(1);
    expect(workers[0]!.postMessage.mock.calls.filter(([message]) => message.type === 'query')).toHaveLength(0);
  });

  it("shares slow initialization across opens and never steals focus when it finishes", async () => {
    let worker!: EventTarget;
    const create = vi.fn();
    class SlowWorker extends EventTarget {
      constructor() { super(); worker = this; create(); }
      postMessage(): void {}
    }
    vi.stubGlobal("Worker", SlowWorker);
    document.body.innerHTML = '<button id="outside">Outside</button><dialog><input data-search-input><p data-search-status></p><ol data-search-results></ol></dialog>';
    const dialog = document.querySelector<HTMLDialogElement>("dialog")!;
    const first = activateSearch(dialog);
    const reopened = activateSearch(dialog);
    const outside = document.querySelector<HTMLButtonElement>("#outside")!;
    outside.focus();
    worker.dispatchEvent(new MessageEvent("message", { data: { type: "ready" } }));
    await Promise.all([first, reopened]);
    expect(create).toHaveBeenCalledTimes(1);
    expect(document.activeElement).toBe(outside);
    await activateSearch(dialog);
    expect(document.activeElement).toBe(outside);
  });

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
