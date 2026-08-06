import { initialiseDialogs, openWebsiteDialog } from "./dialogs";
import { initialiseOutline } from "./outline";
import { initialiseColorScheme } from "./color-scheme";
import { readSiteUrl } from "./urls";
import { initialiseLanguageSwitcher } from "./language-switcher";
import { initialiseComments } from "./comments";
import { initialiseArchiveFilters } from "./archive-filters";
import { initialisePriorityNavigation } from "./priority-navigation";
import { initialisePageActions } from "./page-actions";
import { initialiseTweets } from "./tweets";

const DOCS_PAGE_CHANGE_EVENT = "website:docs-page-change";
let pageFeatureGeneration = 0;
let cleanupPageFeatures = () => undefined;
let graphModule: Promise<typeof import("./graph")> | null = null;

function initialisePageFeatures(): void {
  const generation = ++pageFeatureGeneration;
  cleanupPageFeatures();
  initialiseDialogs();
  const cleanupOutline = initialiseOutline();
  const cleanupComments = initialiseComments();
  const cleanupArchiveFilters = initialiseArchiveFilters();
  const cleanupPageActions = initialisePageActions();
  const cleanupTweets = initialiseTweets();
  cleanupPageFeatures = () => {
    cleanupOutline();
    cleanupComments();
    cleanupArchiveFilters();
    cleanupPageActions();
    cleanupTweets();
  };

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
