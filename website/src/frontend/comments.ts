import {
  COLOR_SCHEME_EVENT,
  preferredColorScheme,
  type ColorScheme
} from "./color-scheme";

const GISCUS_ORIGIN = "https://giscus.app";
const GISCUS_CLIENT = `${GISCUS_ORIGIN}/client.js`;

type CommentsDataset = {
  repository: string;
  repositoryId: string;
  category: string;
  categoryId: string;
  term: string;
  language: string;
};

function readDataset(section: HTMLElement): CommentsDataset | null {
  const values = {
    repository: section.dataset.websiteCommentsRepository || "",
    repositoryId: section.dataset.websiteCommentsRepositoryId || "",
    category: section.dataset.websiteCommentsCategory || "",
    categoryId: section.dataset.websiteCommentsCategoryId || "",
    term: section.dataset.websiteCommentsTerm || "",
    language: section.dataset.websiteCommentsLanguage || "en"
  };
  return Object.values(values).every(Boolean) ? values : null;
}

function currentScheme(doc: Document): ColorScheme {
  const scheme = doc.documentElement.dataset.colorScheme;
  return scheme === "light" || scheme === "dark" ? scheme : preferredColorScheme();
}

function giscusError(data: unknown): { found: boolean; message: string | null } {
  if (!data || typeof data !== "object" || !("giscus" in data)) {
    return { found: false, message: null };
  }
  const message = (data as { giscus?: unknown }).giscus;
  if (!message || typeof message !== "object" || !("error" in message)) {
    return { found: false, message: null };
  }
  const error = (message as { error?: unknown }).error;
  return { found: true, message: typeof error === "string" ? error : null };
}

function sendTheme(section: HTMLElement, scheme: ColorScheme): void {
  const frame = section.querySelector<HTMLIFrameElement>("iframe.giscus-frame");
  frame?.contentWindow?.postMessage(
    { giscus: { setConfig: { theme: scheme } } },
    GISCUS_ORIGIN
  );
}

function initialiseSection(section: HTMLElement, doc: Document): () => void {
  if (section.dataset.websiteCommentsInitialised === "true") return () => undefined;
  section.dataset.websiteCommentsInitialised = "true";

  const status = section.querySelector<HTMLElement>("[data-website-comments-status]");
  const container = section.querySelector<HTMLElement>("[data-website-comments-container]");
  const config = readDataset(section);
  const unavailable = section.dataset.websiteCommentsUnavailable ||
    "Comments could not be loaded. You can continue the conversation on GitHub.";
  const showUnavailable = () => {
    section.dataset.websiteCommentsState = "unavailable";
    if (status) {
      status.hidden = false;
      status.textContent = unavailable;
    }
  };
  if (!container || !config) {
    showUnavailable();
    return () => undefined;
  }

  section.dataset.websiteCommentsState = "loading";
  const observer = new MutationObserver(() => {
    if (!container.querySelector("iframe.giscus-frame")) return;
    sendTheme(section, currentScheme(doc));
    section.dataset.websiteCommentsState = "ready";
    if (status) status.hidden = true;
    observer.disconnect();
  });
  observer.observe(container, { childList: true, subtree: true });

  const script = doc.createElement("script");
  script.src = GISCUS_CLIENT;
  script.async = true;
  script.crossOrigin = "anonymous";
  script.dataset.repo = config.repository;
  script.dataset.repoId = config.repositoryId;
  script.dataset.category = config.category;
  script.dataset.categoryId = config.categoryId;
  script.dataset.mapping = "specific";
  script.dataset.term = config.term;
  script.dataset.strict = "1";
  script.dataset.reactionsEnabled = "1";
  script.dataset.emitMetadata = "0";
  script.dataset.inputPosition = "top";
  script.dataset.theme = currentScheme(doc);
  script.dataset.lang = config.language;
  script.dataset.loading = "lazy";
  script.dataset.websiteCommentsClient = "";
  script.addEventListener("error", showUnavailable, { once: true });

  const view = doc.defaultView;
  const onMessage = (event: MessageEvent) => {
    if (event.origin !== GISCUS_ORIGIN) return;
    const error = giscusError(event.data);
    if (error.found && !error.message?.includes("Discussion not found")) showUnavailable();
  };
  const onScheme = (event: Event) => {
    const scheme = (event as CustomEvent<{ scheme?: unknown }>).detail?.scheme;
    if (scheme === "light" || scheme === "dark") {
      script.dataset.theme = scheme;
      sendTheme(section, scheme);
    }
  };
  view?.addEventListener("message", onMessage);
  doc.addEventListener(COLOR_SCHEME_EVENT, onScheme);
  container.append(script);

  return () => {
    observer.disconnect();
    view?.removeEventListener("message", onMessage);
    doc.removeEventListener(COLOR_SCHEME_EVENT, onScheme);
  };
}

export function initialiseComments(doc: Document = document): () => void {
  const cleanups = Array.from(
    doc.querySelectorAll<HTMLElement>("[data-website-comments-load]")
  ).map((section) => initialiseSection(section, doc));
  return () => cleanups.forEach((cleanup) => cleanup());
}
