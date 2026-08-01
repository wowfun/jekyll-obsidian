import { initialiseDialogs, openObsidianDialog } from "./dialogs";
import { initialiseOutline } from "./outline";
import { initialiseColorScheme } from "./color-scheme";
import { readSiteUrl } from "./urls";

export function initialiseObsidian(): void {
  document.documentElement.classList.remove("no-js");
  document.documentElement.classList.add("js");

  initialiseColorScheme();
  initialiseDialogs();
  initialiseOutline();

  if (readSiteUrl("preview")) {
    void import("./preview").then(({ initialisePreviews }) => initialisePreviews());
  }

  if (readSiteUrl("search")) {
    let searchPromise: Promise<typeof import("./search")> | null = null;
    const openSearch = async () => {
      const dialog = openObsidianDialog("search");
      if (!dialog) return;
      searchPromise ??= import("./search");
      const status = dialog.querySelector<HTMLElement>("[data-search-status]");
      try {
        const search = await searchPromise;
        await search.activateSearch(dialog);
      } catch {
        if (status) status.textContent = "Search could not be loaded. Reload the page and try again.";
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

  if (document.querySelector("pre code.language-mermaid, [data-obsidian-mermaid]")) {
    void import("./mermaid").then(({ renderMermaid }) => renderMermaid());
  }

  if (document.querySelector("[data-math], [data-math-style], .math-inline, .math-display")) {
    void import("./math").then(({ renderMath }) => renderMath());
  }

  const graph = document.querySelector<HTMLElement>("[data-graph]");
  if (graph) {
    void import("./graph").then(({ renderGraph }) => renderGraph(graph));
  }
}
