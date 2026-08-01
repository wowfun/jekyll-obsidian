import { requireSiteUrl } from "./urls";
import type { SearchWorkerRequest, SearchWorkerResponse, SearchWorkerResult } from "./search-protocol";

interface SearchSession {
  worker: Worker;
  ready: Promise<void>;
  nextQueryId: number;
}

const sessions = new WeakMap<HTMLDialogElement, SearchSession>();

function resultLink(result: SearchWorkerResult): HTMLLIElement {
  const item = document.createElement("li");
  item.className = "search-result";
  const link = document.createElement("a");
  link.className = "search-result__link";
  link.href = result.url;
  const title = document.createElement("strong");
  title.textContent = result.title;
  if (result.tags.length > 0) {
    const meta = document.createElement("span");
    meta.className = "search-result__meta";
    meta.textContent = result.tags.slice(0, 3).join(" · ");
    link.append(title, meta);
  } else {
    link.append(title);
  }
  item.append(link);
  return item;
}

function createSession(): SearchSession {
  const worker = new Worker(requireSiteUrl("search-worker"), { type: "module" });
  let resolveReady: (() => void) | undefined;
  let rejectReady: ((error: Error) => void) | undefined;
  const ready = new Promise<void>((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });
  worker.addEventListener("message", (event: MessageEvent<SearchWorkerResponse>) => {
    if (event.data.type === "ready") resolveReady?.();
    if (event.data.type === "error") rejectReady?.(new Error(event.data.message));
  });
  worker.addEventListener("error", () => rejectReady?.(new Error("Search worker failed")), { once: true });
  worker.postMessage({ type: "init", url: requireSiteUrl("search") } satisfies SearchWorkerRequest);
  return { worker, ready, nextQueryId: 0 };
}

export async function activateSearch(dialog: HTMLDialogElement): Promise<void> {
  const input = dialog.querySelector<HTMLInputElement>("[data-search-input]");
  const results = dialog.querySelector<HTMLElement>("[data-search-results]");
  const status = dialog.querySelector<HTMLElement>("[data-search-status]");
  if (!input || !results || !status) {
    throw new Error("Search dialog is missing its input, results, or status element");
  }
  if (dialog.dataset.searchReady === "true") {
    input.focus();
    return;
  }

  status.textContent = "Loading notebook index…";
  const session = createSession();
  sessions.set(dialog, session);
  await session.ready;
  dialog.dataset.searchReady = "true";

  let latestQueryId = 0;
  session.worker.addEventListener("message", (event: MessageEvent<SearchWorkerResponse>) => {
    const message = event.data;
    if (message.type !== "results" || message.id !== latestQueryId) return;
    results.replaceChildren(...message.results.map(resultLink));
    status.textContent = message.results.length === 0
      ? `No notes found for “${input.value.trim()}”.`
      : `${message.results.length} ${message.results.length === 1 ? "note" : "notes"} found.`;
  });

  const query = () => {
    latestQueryId = ++session.nextQueryId;
    const value = input.value.trim();
    results.replaceChildren();
    if (!value) {
      status.textContent = "Type a title, tag, or phrase.";
      return;
    }
    session.worker.postMessage({ type: "query", id: latestQueryId, query: value } satisfies SearchWorkerRequest);
  };

  input.addEventListener("input", query);
  dialog.addEventListener("keydown", (event) => {
    const links = Array.from(results.querySelectorAll<HTMLAnchorElement>("a[href]"));
    const current = links.indexOf(document.activeElement as HTMLAnchorElement);
    if (event.key === "ArrowDown" && links.length > 0) {
      event.preventDefault();
      (links[current + 1] ?? links[0])?.focus();
    } else if (event.key === "ArrowUp" && links.length > 0) {
      event.preventDefault();
      (links[current - 1] ?? links.at(-1))?.focus();
    }
  });

  query();
  input.focus();
}
