import { requireSiteUrl } from "./urls";
import type { SearchWorkerRequest, SearchWorkerResponse, SearchWorkerResult } from "./search-protocol";

interface SearchSession {
  worker: Worker;
  ready: Promise<void>;
  nextQueryId: number;
  dispose: () => void;
}

const sessions = new WeakMap<HTMLDialogElement, SearchSession>();
const initializations = new WeakMap<HTMLDialogElement, Promise<void>>();
const retryHandlers = new WeakMap<HTMLDialogElement, () => void>();

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
  if (result.excerpt) {
    const excerpt = document.createElement('span');
    excerpt.className = 'search-result__excerpt';
    excerpt.textContent = result.excerpt;
    link.append(excerpt);
  }
  item.append(link);
  return item;
}

function createSession(onFailure: () => void, listeners: AbortController): SearchSession {
  const worker = new Worker(requireSiteUrl("search-worker"), { type: "module" });
  let resolveReady: (() => void) | undefined;
  let rejectReady: ((error: Error) => void) | undefined;
  const ready = new Promise<void>((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });
  const fail = (error: Error) => { clearTimeout(timer); rejectReady?.(error); onFailure(); };
  const timer = setTimeout(() => fail(new Error("Search worker initialization timed out")), 15_000);
  const onMessage = (event: MessageEvent<SearchWorkerResponse>) => {
    if (event.data.type === "ready") { clearTimeout(timer); resolveReady?.(); }
    if (event.data.type === "error") fail(new Error(event.data.message));
  };
  const onError = () => fail(new Error("Search worker failed"));
  worker.addEventListener("message", onMessage);
  worker.addEventListener("error", onError);
  worker.addEventListener("messageerror", onError);
  return { worker, ready, nextQueryId: 0, dispose() {
    listeners.abort();
    clearTimeout(timer);
    rejectReady?.(new DOMException("Search session disposed", "AbortError"));
    worker.removeEventListener("message", onMessage);
    worker.removeEventListener("error", onError);
    worker.removeEventListener("messageerror", onError);
    worker.terminate();
  } };
}

export function disposeSearch(dialog: HTMLDialogElement): void {
  const session = sessions.get(dialog);
  sessions.delete(dialog);
  initializations.delete(dialog);
  session?.dispose();
  const retry = retryHandlers.get(dialog);
  if (retry) dialog.querySelector("[data-search-input]")?.removeEventListener("input", retry);
  retryHandlers.delete(dialog);
  delete dialog.dataset.searchReady;
}

export function activateSearch(dialog: HTMLDialogElement): Promise<void> {
  const pending = initializations.get(dialog);
  if (pending) return pending;
  const retry = retryHandlers.get(dialog);
  if (retry) {
    dialog.querySelector("[data-search-input]")?.removeEventListener("input", retry);
    retryHandlers.delete(dialog);
  }
  const initialization = initialiseSearch(dialog).catch((error: unknown) => {
    if (initializations.get(dialog) === initialization) initializations.delete(dialog);
    throw error;
  });
  initializations.set(dialog, initialization);
  return initialization;
}

async function initialiseSearch(dialog: HTMLDialogElement): Promise<void> {
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

  status.textContent = dialog.dataset.searchLoading || "Loading notebook index…";
  const listeners = new AbortController();
  let session: SearchSession | undefined;
  const fail = () => {
    if (session && sessions.get(dialog) !== session) return;
    listeners.abort();
    session?.dispose();
    sessions.delete(dialog);
    initializations.delete(dialog);
    delete dialog.dataset.searchReady;
    results.replaceChildren();
    status.textContent = dialog.dataset.searchRetry || "Search is unavailable. Edit your query to try again.";
    const retry = () => { void activateSearch(dialog).catch(() => {}); };
    retryHandlers.set(dialog, retry);
    input.addEventListener("input", retry, { once: true });
  };
  try { session = createSession(fail, listeners); }
  catch (error) { fail(); throw error; }
  sessions.set(dialog, session);
  try {
    session.worker.postMessage({ type: "init", url: requireSiteUrl("search") } satisfies SearchWorkerRequest);
    await session.ready;
  } catch (error) {
    fail();
    // postMessage can throw before the readiness promise is awaited.
    await session.ready.catch(() => {});
    throw error;
  }
  if (sessions.get(dialog) !== session) return;
  const active = session;
  dialog.dataset.searchReady = "true";

  let latestQueryId = 0;
  let inFlight = false;
  let pendingQuery: SearchWorkerRequest | undefined;
  let queryTimer: ReturnType<typeof setTimeout> | undefined;
  const sendPending = () => {
    if (inFlight || !pendingQuery) return;
    inFlight = true;
    try { active.worker.postMessage(pendingQuery); pendingQuery = undefined; }
    catch { fail(); }
  };
  listeners.signal.addEventListener('abort', () => { clearTimeout(queryTimer); pendingQuery = undefined; }, { once: true });
  active.worker.addEventListener("message", (event: MessageEvent<SearchWorkerResponse>) => {
    const message = event.data;
    if (message.type !== "results") return;
    inFlight = false;
    if (!queryTimer) sendPending();
    if (message.id !== latestQueryId) return;
    results.replaceChildren(...message.results.map(resultLink));
    status.textContent = message.results.length === 0
      ? formatMessage(dialog.dataset.searchNoResults || "No notes found for “{query}”.", { query: input.value.trim() })
      : formatMessage(
          message.total > message.results.length
            ? dialog.dataset.searchTopResults || 'Showing {count} of {total} matches.'
            : message.results.length === 1
            ? dialog.dataset.searchResultOne || "{count} note found."
            : dialog.dataset.searchResultMany || "{count} notes found.",
          { count: message.results.length, total: message.total }
        );
    if (message.limited) status.textContent += ' ' + (dialog.dataset.searchLimited || 'Some notes or text are outside the search index.');
  }, { signal: listeners.signal });

  const query = (debounce = false) => {
    clearTimeout(queryTimer);
    queryTimer = undefined;
    pendingQuery = undefined;
    latestQueryId = ++active.nextQueryId;
    const value = input.value.trim().slice(0, 256);
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
    pendingQuery = { type: 'query', id: latestQueryId, query: value };
    if (debounce) queryTimer = setTimeout(() => { queryTimer = undefined; sendPending(); }, 120);
    else sendPending();
  };

  input.addEventListener("input", () => query(true), { signal: listeners.signal });
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
  }, { signal: listeners.signal });

  query();
}
