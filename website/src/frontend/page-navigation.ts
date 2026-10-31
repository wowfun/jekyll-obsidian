import { closeWebsiteDialog } from "./dialogs";
import { BEFORE_PAGE_CHANGE_EVENT, PAGE_CHANGE_EVENT } from "./page-navigation-events";

const navigationController = Symbol.for("jekyll-obsidian.page-navigation-controller");
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
    ".site-mark, [data-priority-navigation] a[href], [data-dialog='browse'] [data-navigation-id] a[href], .docs-sidebar a[href], .minimal-docs-sidebar a[href], .docs-tree--dialog a[href]"
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

function syncHeader(source: Document): void {
  const active = source.querySelector('.site-header [aria-current="page"]')?.closest<HTMLElement>("[data-navigation-id]")?.dataset.navigationId;
  for (const item of document.querySelectorAll<HTMLElement>(".site-header [data-navigation-id]")) {
    const link = item.querySelector("a");
    if (item.dataset.navigationId === active) link?.setAttribute("aria-current", "page");
    else link?.removeAttribute("aria-current");
  }
  const more = document.querySelector<HTMLDetailsElement>("[data-priority-navigation-more]");
  if (more) {
    more.open = false;
    if (more.querySelector('[aria-current="page"]')) more.dataset.hasCurrent = "true";
    else delete more.dataset.hasCurrent;
  }
  replaceOptional("[data-page-header-actions]", source);
}

function sameAssets(source: Document): boolean {
  const selector = '[data-website-asset]';
  const paths = (doc: Document) => [...doc.head.querySelectorAll(selector)]
    .map(node => node.getAttribute("href") ?? node.getAttribute("src"));
  return JSON.stringify(paths(document)) === JSON.stringify(paths(source));
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
  const currentShell = document.querySelector<HTMLElement>(".minimal-shell, .docs-shell");
  const nextShell = source.querySelector<HTMLElement>(".minimal-shell, .docs-shell");
  const currentTheme = [...document.body.classList].find((name) => name.startsWith("theme-"));
  const docsOnly = Boolean(currentMain && nextMain &&
    document.querySelector("[data-docs-navigation]") && source.querySelector("[data-docs-navigation]"));
  if ((!docsOnly && (!currentShell || !nextShell)) || !currentTheme || !source.body.classList.contains(currentTheme) || !sameAssets(source)) {
    throw new TypeError("Destination requires a different page shell");
  }
  // A different site, locale, or header layout needs its own global controls.
  if (document.documentElement.lang !== source.documentElement.lang ||
    document.querySelector(".site-mark")?.getAttribute("href") !== source.querySelector(".site-mark")?.getAttribute("href") ||
    Boolean(document.querySelector("[data-page-header-actions]")) !== Boolean(source.querySelector("[data-page-header-actions]"))) {
    throw new TypeError("Destination requires a different site header");
  }

  document.dispatchEvent(new CustomEvent(BEFORE_PAGE_CHANGE_EVENT));

  for (const name of ["search", "browse", "context", "graph-global", "graph-local", "media", "export"] as const) {
    closeWebsiteDialog(name);
  }
  syncPageHead(source);
  syncLanguageSwitcher(source);
  syncHeader(source);
  document.documentElement.lang = source.documentElement.lang;
  document.documentElement.dir = source.documentElement.dir;

  const importedMain = importElement(docsOnly ? nextMain! : nextShell!);
  (docsOnly ? currentMain! : currentShell!).replaceWith(importedMain);
  if (docsOnly) replaceOptional("[data-page-context]", source, importedMain);
  replaceOptional(".site-footer", source);
  replaceOptional(".mobile-toolbar", source);
  replaceOptional("[data-back-to-top]", source);
  replaceOptional("[data-page-dialogs]", source);

  if (push) history.pushState(null, "", url);
  markCurrentLinks(url);
  scrollToLocation(url);
  document.dispatchEvent(new CustomEvent(PAGE_CHANGE_EVENT, { detail: { url: url.href } }));
  // Minimal replaces the reading column inside its persistent main landmark.
  (importedMain.closest<HTMLElement>("main") ?? importedMain.querySelector<HTMLElement>("main") ?? importedMain).focus({ preventScroll: true });
}

export function initialisePageNavigation(): void {
  const controlledDocument = document as ControlledDocument;
  controlledDocument[navigationController]?.();
  const navigation = document.querySelector<HTMLElement>("[data-priority-navigation], [data-docs-navigation]");
  if (!navigation) return;

  let activeRequest: AbortController | null = null;
  let requestVersion = 0;
  let renderedUrl = new URL(window.location.href);

  const navigate = async (url: URL, push: boolean) => {
    const version = ++requestVersion;
    activeRequest?.abort();
    const controller = new AbortController();
    activeRequest = controller;
    document.querySelector<HTMLElement>("main")?.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(url, {
        credentials: "same-origin",
        headers: { Accept: "text/html" },
        signal: controller.signal
      });
      if (!response.ok || response.redirected || !response.headers.get("content-type")?.includes("text/html")) {
        throw new Error(`Page returned HTTP ${response.status}`);
      }
      const source = new DOMParser().parseFromString(await response.text(), "text/html");
      if (version !== requestVersion) return;
      commitPage(source, url, push);
      renderedUrl = new URL(url.href);
    } catch (error) {
      if (version !== requestVersion || controller.signal.aborted) return;
      if (error instanceof DOMException && error.name === "AbortError") return;
      window.location.assign(url.href);
    } finally {
      if (version === requestVersion) {
        activeRequest = null;
        document.querySelector<HTMLElement>("main")?.removeAttribute("aria-busy");
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
      requestVersion += 1;
      activeRequest?.abort();
      document.querySelector("main")?.removeAttribute("aria-busy");
      if (url.href !== current.href) history.pushState(null, "", url);
      renderedUrl = new URL(url.href);
      scrollToLocation(url);
      return;
    }
    void navigate(url, true);
  };
  const handlePopState = () => {
    const url = new URL(window.location.href);
    if (url.pathname === renderedUrl.pathname) {
      requestVersion += 1;
      activeRequest?.abort();
      document.querySelector("main")?.removeAttribute("aria-busy");
      // Archive controls own query history; the page shell owns path changes.
      if (!document.querySelector("[data-paged-archive], [data-filter-page]")) scrollToLocation(url);
      return;
    }
    void navigate(url, false);
  };
  const cleanup = () => {
    requestVersion += 1;
    activeRequest?.abort();
    document.removeEventListener("click", handleClick);
    window.removeEventListener("popstate", handlePopState);
    if (controlledDocument[navigationController] === cleanup) delete controlledDocument[navigationController];
  };

  markCurrentLinks(new URL(window.location.href));
  document.addEventListener("click", handleClick);
  window.addEventListener("popstate", handlePopState);
  controlledDocument[navigationController] = cleanup;
  navigation.dataset.pageNavigationReady = "true";
}
