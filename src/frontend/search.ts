import MiniSearch, { type SearchResult } from "minisearch";
import { fetchJson, parseSearchPayload } from "./data";
import { cjkSegmentBoost, obsidianTokenizer } from "./tokenize";
import { requireSiteUrl } from "./urls";
import type { SearchDocument } from "./types";

type IndexedDocument = SearchDocument & { aliasesText: string; tagsText: string };

function makeIndex(documents: SearchDocument[]): MiniSearch<IndexedDocument> {
  const index = new MiniSearch<IndexedDocument>({
    idField: "id",
    fields: ["title", "aliasesText", "tagsText", "text"],
    storeFields: ["id", "title", "url", "aliases", "tags", "text"],
    tokenize: obsidianTokenizer,
    processTerm: (term) => term.normalize("NFKC").toLocaleLowerCase("und"),
    searchOptions: {
      boost: { title: 4, aliasesText: 2.5, tagsText: 1.8, text: 1 },
      prefix: true,
      fuzzy: 0.15,
      combineWith: "AND"
    }
  });
  index.addAll(
    documents.map((document) => ({
      ...document,
      aliasesText: document.aliases.join(" "),
      tagsText: document.tags.join(" ")
    }))
  );
  return index;
}

function resultLink(result: SearchResult): HTMLLIElement {
  const item = document.createElement("li");
  item.className = "search-result";

  const link = document.createElement("a");
  link.className = "search-result__link";
  link.href = String(result.url);

  const title = document.createElement("strong");
  title.textContent = String(result.title);
  const tags = Array.isArray(result.tags) ? result.tags.map(String) : [];
  if (tags.length > 0) {
    const meta = document.createElement("span");
    meta.className = "search-result__meta";
    meta.textContent = tags.slice(0, 3).join(" · ");
    link.append(title, meta);
  } else {
    link.append(title);
  }
  item.append(link);
  return item;
}

export async function activateSearch(dialog: HTMLDialogElement): Promise<void> {
  if (dialog.dataset.searchReady === "true") {
    dialog.querySelector<HTMLInputElement>("[data-search-input]")?.focus();
    return;
  }

  const input = dialog.querySelector<HTMLInputElement>("[data-search-input]");
  const results = dialog.querySelector<HTMLElement>("[data-search-results]");
  const status = dialog.querySelector<HTMLElement>("[data-search-status]");
  if (!input || !results || !status) {
    throw new Error("Search dialog is missing its input, results, or status element");
  }

  status.textContent = "Loading notebook index…";
  const payload = parseSearchPayload(await fetchJson(requireSiteUrl("search")));
  const index = makeIndex(payload.documents);
  dialog.dataset.searchReady = "true";

  const render = () => {
    const query = input.value.trim();
    results.replaceChildren();
    if (!query) {
      status.textContent = "Type a title, tag, or phrase.";
      return;
    }

    const enhanced = [query, ...cjkSegmentBoost(query)].join(" ");
    const matches = index.search(enhanced).slice(0, 12);
    status.textContent =
      matches.length === 0
        ? `No notes found for “${query}”.`
        : `${matches.length} ${matches.length === 1 ? "note" : "notes"} found.`;
    results.append(...matches.map(resultLink));
  };

  input.addEventListener("input", render);
  input.addEventListener("keydown", (event) => {
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

  render();
  input.focus();
}
