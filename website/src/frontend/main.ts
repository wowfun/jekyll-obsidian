import { initialiseDialogs, openWebsiteDialog } from "./dialogs";
import { initialiseOutline } from "./outline";
import { initialiseColorScheme } from "./color-scheme";
import { readSiteUrl } from "./urls";
import { initialiseLanguageSwitcher } from "./language-switcher";
import { initialiseRecommendations } from "./recommendations";
import { initialiseComments } from "./comments";
import { initialisePriorityNavigation } from "./priority-navigation";
import { initialisePageActions } from "./page-actions";
import { initialisePdfPreviews } from "./pdf-preview";
import { initialiseCodeBlockCopy } from "./code-block-copy";
import { initialiseTweets } from "./tweets";
import { initialiseAnalytics } from "./analytics";
import { initialiseAutoHideScrollbars } from "./scrollbars";
import { initialiseBackToTop } from "./back-to-top";
import { initialiseImageViewer, initialiseMediaViewerControls } from "./media-viewer";
import { disposeAll } from "./cleanup";

const DOCS_PAGE_CHANGE_EVENT = "website:docs-page-change";
let pageFeatureGeneration = 0;
let cleanupPageFeatures: () => void = () => {};
let graphModule: Promise<typeof import("./graph")> | null = null;

function initialisePageFeatures(): void {
  const generation = ++pageFeatureGeneration;
  try { cleanupPageFeatures(); } catch (error) { console.error(error); }
  const cleanups: (() => void)[] = [];
  cleanupPageFeatures = () => disposeAll(cleanups);
  try {
    initialiseDialogs();
    cleanups.push(initialiseOutline());
    cleanups.push(initialiseRecommendations());
    cleanups.push(initialiseComments());
    cleanups.push(initialisePageActions());
    cleanups.push(initialiseBackToTop());
    cleanups.push(initialisePdfPreviews());
    cleanups.push(initialiseCodeBlockCopy());
    cleanups.push(initialiseImageViewer());
    initialiseMediaViewerControls();
    cleanups.push(initialiseTweets());
  } catch (error) {
    try { cleanupPageFeatures(); } catch (cleanupError) { throw new AggregateError([error, cleanupError], "Page feature initialization failed"); }
    throw error;
  }

  if (document.querySelector("[data-paged-archive], [data-filter-page]")) {
    void import("./archive-filters")
      .then(({ initialiseArchiveFilters }) => {
        if (generation === pageFeatureGeneration) cleanups.push(initialiseArchiveFilters());
      })
      .catch(() => {
        if (generation !== pageFeatureGeneration) return;
        const root = document.querySelector<HTMLElement>("[data-paged-archive], [data-filter-page]");
        let status = document.querySelector<HTMLElement>("[data-archive-status]")
          ?? document.querySelector<HTMLElement>("[data-filter-empty]");
        if (!status && root) {
          status = document.createElement("p");
          status.setAttribute("role", "status");
          status.dataset.archiveStatus = "";
          root.append(status);
        }
        if (status) {
          status.textContent = status.dataset.moduleUnavailable || root?.dataset.moduleUnavailable || "Archive controls could not be loaded. Reload the page to try again.";
          status.hidden = false;
        }
      });
  }

  if (document.querySelector("[data-favorites-ui]")) {
    void import("./favorite-controls")
      .then(({ initialiseFavorites }) => {
        if (generation === pageFeatureGeneration) cleanups.push(initialiseFavorites());
      })
      .catch(() => {
        if (generation !== pageFeatureGeneration) return;
        const status = document.querySelector<HTMLElement>("[data-favorite-status]");
        const ui = document.querySelector<HTMLElement>("[data-favorites-ui]");
        if (status) status.textContent = ui?.dataset.moduleUnavailable || "Favorites could not be loaded. Reload the page to try again.";
      });
  }

  if (readSiteUrl("preview")) {
    void import("./preview")
      .then(({ initialisePreviews }) => {
        if (generation === pageFeatureGeneration) initialisePreviews();
      })
      .catch(() => {
        document.documentElement.dataset.previewError = "true";
      });
  }

  if (document.querySelector("pre code.language-mermaid, [data-website-mermaid]")) {
    void import("./mermaid")
      .then(({ renderMermaid }) => {
        if (generation === pageFeatureGeneration) void renderMermaid();
      })
      .catch(() => {
        document.documentElement.dataset.mermaidError = "true";
      });
  }

  if (document.querySelector("[data-math], [data-math-style], .math-inline, .math-display")) {
    void import("./math")
      .then(({ renderMath }) => {
        if (generation === pageFeatureGeneration) void renderMath();
      })
      .catch(() => {
        document.documentElement.dataset.mathError = "true";
      });
  }

  if (document.querySelector("[data-local-graph-section]")) graphModule ??= import("./graph");
  if (graphModule) {
    void graphModule
      .then(({ initialiseGraphs }) => {
        if (generation === pageFeatureGeneration) initialiseGraphs();
      })
      .catch(() => {
        document.documentElement.dataset.graphError = "true";
      });
  }
}

export function initialiseWebsite(): void {
  document.documentElement.classList.remove("no-js");
  document.documentElement.classList.add("js");

  initialiseColorScheme();
  initialiseLanguageSwitcher();
  initialisePriorityNavigation();
  initialiseAnalytics();
  initialiseAutoHideScrollbars();
  initialisePageFeatures();
  document.addEventListener(DOCS_PAGE_CHANGE_EVENT, initialisePageFeatures);

  if (document.querySelector("[data-docs-navigation]")) {
    void import("./docs-navigation")
      .then(({ initialiseDocsNavigation }) => initialiseDocsNavigation())
      .catch(() => {
        document.documentElement.dataset.docsNavigationError = "true";
      });
  }

  if (readSiteUrl("search")) {
    let searchPromise: Promise<typeof import("./search")> | null = null;
    const openSearch = async () => {
      const dialog = openWebsiteDialog("search");
      if (!dialog) return;
      searchPromise ??= import("./search");
      const status = dialog.querySelector<HTMLElement>("[data-search-status]");
      try {
        const search = await searchPromise;
        await search.activateSearch(dialog);
      } catch {
        if (status) status.textContent = dialog.dataset.searchUnavailable || "Search could not be loaded. Reload the page and try again.";
      }
    };

    document.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element) || !target.closest("[data-search-open]")) return;
      event.preventDefault();
      void openSearch();
    });

    document.addEventListener("keydown", (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLocaleLowerCase("und") === "k") {
        event.preventDefault();
        void openSearch();
      }
    });
  }

}
