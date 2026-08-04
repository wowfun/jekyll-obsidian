import { initialiseDialogs, openWebsiteDialog } from "./dialogs";
import { initialiseOutline } from "./outline";
import { initialiseColorScheme } from "./color-scheme";
import { readSiteUrl } from "./urls";
import { initialiseLanguageSwitcher } from "./language-switcher";
import { initialiseComments } from "./comments";

export function initialiseWebsite(): void {
  document.documentElement.classList.remove("no-js");
  document.documentElement.classList.add("js");

  initialiseColorScheme();
  initialiseDialogs();
  initialiseOutline();
  initialiseLanguageSwitcher();
  initialiseComments();

  if (document.querySelector("[data-docs-navigation]")) {
    void import("./docs-navigation")
      .then(({ initialiseDocsNavigation }) => initialiseDocsNavigation())
      .catch(() => {
        document.documentElement.dataset.docsNavigationError = "true";
      });
  }

  if (readSiteUrl("preview")) {
    void import("./preview")
      .then(({ initialisePreviews }) => initialisePreviews())
      .catch(() => {
        document.documentElement.dataset.previewError = "true";
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

  if (document.querySelector("pre code.language-mermaid, [data-website-mermaid]")) {
    void import("./mermaid")
      .then(({ renderMermaid }) => renderMermaid())
      .catch(() => {
        document.documentElement.dataset.mermaidError = "true";
      });
  }

  if (document.querySelector("[data-math], [data-math-style], .math-inline, .math-display")) {
    void import("./math")
      .then(({ renderMath }) => renderMath())
      .catch(() => {
        document.documentElement.dataset.mathError = "true";
      });
  }

  if (document.querySelector("[data-local-graph-section]")) {
    void import("./graph")
      .then(({ initialiseGraphs }) => initialiseGraphs())
      .catch(() => {
        document.documentElement.dataset.graphError = "true";
      });
  }
}
