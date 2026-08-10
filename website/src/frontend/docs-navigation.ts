import { closeWebsiteDialog } from "./dialogs";

export const DOCS_PAGE_CHANGE_EVENT = "website:docs-page-change";

const navigationController = Symbol.for("jekyll-obsidian.docs-navigation-controller");
const PAGE_HEAD_SELECTOR = "[data-page-head]";
const PAGE_CSP_SELECTOR = "meta[data-page-csp]";

type ControlledDocument = Document & { [navigationController]?: () => void };

function samePage(left: URL, right: URL): boolean {
  return left.origin === right.origin && left.pathname === right.pathname && left.search === right.search;
}

function markCurrentLinks(url: URL): void {
  for (const navigation of document.querySelectorAll<HTMLElement>(
    "[data-docs-navigation]"
  )) {
    for (const link of navigation.querySelectorAll<HTMLAnchorElement>("a[href]")) {
      const target = new URL(link.href, url);
      if (samePage(target, url)) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }
  }
  const docsNavigation = document.querySelector<HTMLElement>("[data-docs-navigation]");
  if (docsNavigation) docsNavigation.dataset.docsNavigationReady = "true";
}

function scrollToLocation(url: URL): void {
  if (!url.hash) {
    window.scrollTo({ top: 0, left: 0, behavior: "instant" });
    return;
  }

  let fragment: string;
  try {
    fragment = decodeURIComponent(url.hash.slice(1));
  } catch {
    return;
  }
  document.getElementById(fragment)?.scrollIntoView({ block: "start", behavior: "instant" });
}

function eligibleLink(event: MouseEvent): HTMLAnchorElement | null {
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
    return null;
  }
  const target = event.target;
  if (!(target instanceof Element)) return null;
  const link = target.closest<HTMLAnchorElement>(
    ".docs-sidebar a[href], .minimal-docs-sidebar a[href], .docs-tree--dialog a[href]"
  );
  if (!link || link.target || link.hasAttribute("download")) return null;
  const url = new URL(link.href, window.location.href);
  if (url.origin !== window.location.origin || !/^https?:$/.test(url.protocol)) return null;
  const current = new URL(window.location.href);
  if (samePage(url, current) && url.hash) return null;
  return link;
}

function importElement<T extends Element>(source: T): T {
  return document.importNode(source, true) as T;
}

function replaceOptional(selector: string, source: Document, after?: Element): Element | null {
  const current = document.querySelector(selector);
  const next = source.querySelector(selector);
  if (current && next) {
    const imported = importElement(next);
    current.replaceWith(imported);
    return imported;
  }
  if (current) current.remove();
  if (next && after) {
    const imported = importElement(next);
    after.after(imported);
    return imported;
  }
  return null;
}

function syncPageHead(source: Document): void {
  const current = [...document.head.querySelectorAll(PAGE_HEAD_SELECTOR)];
  const next = [...source.head.querySelectorAll(PAGE_HEAD_SELECTOR)]
    .map((element) => importElement(element));
  const anchor = document.head.querySelector('meta[name="color-scheme"]');
  current.forEach((element) => element.remove());
  if (anchor?.parentNode) anchor.after(...next);
  else document.head.append(...next);
}

function syncLanguageSwitcher(source: Document): void {
  const current = document.querySelector<HTMLElement>("[data-language-switcher]");
  const next = source.querySelector<HTMLElement>("[data-language-switcher]");
  if (!current || !next) return;
  const currentSummary = current.querySelector("summary");
  const nextSummary = next.querySelector("summary");
  const currentPanel = current.querySelector(".language-switcher__panel");
  const nextPanel = next.querySelector(".language-switcher__panel");
  if (currentSummary && nextSummary) {
    currentSummary.setAttribute("aria-label", nextSummary.getAttribute("aria-label") || "Language");
  }
  if (currentPanel && nextPanel) currentPanel.replaceChildren(...[...nextPanel.childNodes].map((node) => document.importNode(node, true)));
}

export function sameContentSecurityPolicy(source: Document): boolean {
  const currentCsp = document.head.querySelector<HTMLMetaElement>(PAGE_CSP_SELECTOR)?.content;
  const nextCsp = source.head.querySelector<HTMLMetaElement>(PAGE_CSP_SELECTOR)?.content;
  return Boolean(currentCsp && currentCsp === nextCsp);
}

function commitPage(source: Document, url: URL, push: boolean): void {
  if (!sameContentSecurityPolicy(source)) {
    throw new TypeError("Destination requires a different Content Security Policy");
  }

  const currentMain = document.querySelector<HTMLElement>("[data-docs-main]");
  const nextMain = source.querySelector<HTMLElement>("[data-docs-main]");
  const currentTheme = [...document.body.classList].find((name) => name.startsWith("theme-"));
  if (!currentMain || !nextMain || !currentTheme || !source.body.classList.contains(currentTheme)) {
    throw new TypeError("Destination is not a documentation page in the current theme");
  }

  for (const name of ["browse", "context", "graph-global", "graph-local", "media"] as const) {
    closeWebsiteDialog(name);
  }
  syncPageHead(source);
  syncLanguageSwitcher(source);
  document.documentElement.lang = source.documentElement.lang;
  document.documentElement.dir = source.documentElement.dir;

  const importedMain = importElement(nextMain);
  currentMain.replaceWith(importedMain);
  replaceOptional("[data-page-context]", source, importedMain);
  replaceOptional(".mobile-toolbar", source);
  replaceOptional("[data-page-dialogs]", source);

  if (push) history.pushState({ websiteDocs: true }, "", url);
  markCurrentLinks(url);
  scrollToLocation(url);
  document.dispatchEvent(new CustomEvent(DOCS_PAGE_CHANGE_EVENT, { detail: { url: url.href } }));
}

export function initialiseDocsNavigation(): void {
  const controlledDocument = document as ControlledDocument;
  controlledDocument[navigationController]?.();
  const navigation = document.querySelector<HTMLElement>("[data-docs-navigation]");
  if (!navigation) return;

  let activeRequest: AbortController | null = null;
  let requestVersion = 0;
  let renderedUrl = new URL(window.location.href);

  const navigate = async (url: URL, push: boolean) => {
    const version = ++requestVersion;
    activeRequest?.abort();
    activeRequest = new AbortController();
    document.querySelector<HTMLElement>("[data-docs-main]")?.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(url, {
        credentials: "same-origin",
        headers: { Accept: "text/html" },
        signal: activeRequest.signal
      });
      if (!response.ok || !response.headers.get("content-type")?.includes("text/html")) {
        throw new Error(`Documentation page returned HTTP ${response.status}`);
      }
      const source = new DOMParser().parseFromString(await response.text(), "text/html");
      if (version !== requestVersion) return;
      commitPage(source, url, push);
      renderedUrl = new URL(url.href);
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return;
      window.location.assign(url.href);
    } finally {
      if (version === requestVersion) {
        activeRequest = null;
        document.querySelector<HTMLElement>("[data-docs-main]")?.removeAttribute("aria-busy");
      }
    }
  };

  const handleClick = (event: MouseEvent) => {
    const link = eligibleLink(event);
    if (!link) return;
    event.preventDefault();
    const url = new URL(link.href, window.location.href);
    const current = new URL(window.location.href);
    if (samePage(url, current)) {
      if (url.href !== current.href) history.pushState({ websiteDocs: true }, "", url);
      renderedUrl = new URL(url.href);
      scrollToLocation(url);
      return;
    }
    void navigate(url, true);
  };
  const handlePopState = () => {
    const url = new URL(window.location.href);
    if (samePage(url, renderedUrl)) {
      scrollToLocation(url);
      return;
    }
    void navigate(url, false);
  };
  const cleanup = () => {
    activeRequest?.abort();
    document.removeEventListener("click", handleClick);
    window.removeEventListener("popstate", handlePopState);
    if (controlledDocument[navigationController] === cleanup) delete controlledDocument[navigationController];
  };

  markCurrentLinks(new URL(window.location.href));
  document.addEventListener("click", handleClick);
  window.addEventListener("popstate", handlePopState);
  controlledDocument[navigationController] = cleanup;
}
