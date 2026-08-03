import MiniSearch from "minisearch";
import { fetchJson, parseSearchPayload } from "./data";
import { websiteTokenizer } from "./tokenize";
import type { SearchDocument } from "./types";
import type { SearchWorkerRequest, SearchWorkerResponse, SearchWorkerResult } from "./search-protocol";

type IndexedDocument = SearchDocument & { aliasesText: string; tagsText: string };

const scope = self as unknown as {
  onmessage: ((event: MessageEvent<SearchWorkerRequest>) => void) | null;
  postMessage(message: SearchWorkerResponse): void;
};
let index: MiniSearch<IndexedDocument> | null = null;

function post(message: SearchWorkerResponse): void {
  scope.postMessage(message);
}

scope.onmessage = (event) => {
  const message = event.data;
  if (message.type === "init") {
    void fetchJson(message.url)
      .then(parseSearchPayload)
      .then((payload) => {
        index = new MiniSearch<IndexedDocument>({
          idField: "id",
          fields: ["title", "aliasesText", "tagsText", "text"],
          storeFields: ["title", "url", "tags"],
          tokenize: websiteTokenizer,
          processTerm: (term) => term.normalize("NFKC").toLocaleLowerCase("und"),
          searchOptions: {
            boost: { title: 4, aliasesText: 2.5, tagsText: 1.8, text: 1 },
            prefix: true,
            fuzzy: 0.15,
            combineWith: "AND"
          }
        });
        index.addAll(payload.documents.map((document) => ({
          ...document,
          aliasesText: document.aliases.join(" "),
          tagsText: document.tags.join(" ")
        })));
        post({ type: "ready" });
      })
      .catch(() => post({ type: "error", message: "Search index could not be loaded" }));
    return;
  }

  if (!index) {
    post({ type: "error", message: "Search index is not ready" });
    return;
  }
  const results: SearchWorkerResult[] = index.search(message.query).slice(0, 12).map((result) => ({
    title: String(result.title),
    url: String(result.url),
    tags: Array.isArray(result.tags) ? result.tags.map(String) : []
  }));
  post({ type: "results", id: message.id, results });
};
