import { requireSiteUrl } from "./urls";
import type { SearchWorkerRequest, SearchWorkerResponse, SearchWorkerResult } from "./search-protocol";

interface SearchSession {
  worker: Worker;
  ready: Promise<void>;
  nextQueryId: number;
}

const sessions = new WeakMap<HTMLDialogElement, SearchSession>();

function formatMessage(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{([a-z]+)\}/g, (match, key: string) =>
    Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : match
  );
}

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
  const navigation = dialog.querySelector<HTMLElement>("[data-search-navigation]");
  const navigationItems = navigation
    ? [...navigation.querySelectorAll<HTMLElement>("[data-navigation-id]")]
    : [];
  if (!input || !results || !status) {
    throw new Error("Search dialog is missing its input, results, or status element");
  }
  if (dialog.dataset.searchReady === "true") {
    input.focus();
    return;
  }

  status.textContent = dialog.dataset.searchLoading || "Loading notebook index…";
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
      ? formatMessage(dialog.dataset.searchNoResults || "No notes found for “{query}”.", { query: input.value.trim() })
      : formatMessage(
          message.results.length === 1
            ? dialog.dataset.searchResultOne || "{count} note found."
            : dialog.dataset.searchResultMany || "{count} notes found.",
          { count: message.results.length }
        );
  });

  const query = () => {
    latestQueryId = ++session.nextQueryId;
    const value = input.value.trim();
    const foldedValue = value.normalize("NFKC").toLocaleLowerCase();
    let visibleNavigationItems = 0;
    navigationItems.forEach((item) => {
      const label = item.textContent?.normalize("NFKC").toLocaleLowerCase() || "";
      item.hidden = Boolean(foldedValue) && !label.includes(foldedValue);
      if (!item.hidden) visibleNavigationItems += 1;
    });
    if (navigation) navigation.hidden = visibleNavigationItems === 0;
    results.replaceChildren();
    if (!value) {
      status.textContent = dialog.dataset.searchPrompt || "Type a title, tag, or phrase.";
      return;
    }
    session.worker.postMessage({ type: "query", id: latestQueryId, query: value } satisfies SearchWorkerRequest);
  };

  input.addEventListener("input", query);
  dialog.addEventListener("keydown", (event) => {
    const links = Array.from(
      dialog.querySelectorAll<HTMLAnchorElement>("[data-search-navigation] a[href], [data-search-results] a[href]")
    ).filter((link) => !link.closest<HTMLElement>("[hidden]"));
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
