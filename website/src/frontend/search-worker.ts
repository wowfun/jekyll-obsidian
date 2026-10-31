import MiniSearch from "minisearch";
import { fetchJson, parseSearchPayload } from "./data";
import { boundedWebsiteTokenizer, websiteTokenizer } from "./tokenize";
import type { SearchDocument } from "./types";
import type { SearchWorkerRequest, SearchWorkerResponse, SearchWorkerResult } from "./search-protocol";

type IndexedDocument = SearchDocument & { aliasesText: string; tagsText: string };

const scope = self as unknown as {
  onmessage: ((event: MessageEvent<SearchWorkerRequest>) => void) | null;
  postMessage(message: SearchWorkerResponse): void;
};
let index: MiniSearch<IndexedDocument> | null = null;
let limited = false;
let pending: Extract<SearchWorkerRequest, { type: 'query' }> | undefined;
let queryTimer: ReturnType<typeof setTimeout> | undefined;

function post(message: SearchWorkerResponse): void {
  scope.postMessage(message);
}

scope.onmessage = (event) => {
  const message = event.data;
  if (message.type === "init") {
    void fetchJson(message.url, undefined, 8_388_608)
      .then(parseSearchPayload)
      .then((payload) => {
        limited = payload.truncated === true;
        let indexing = true, indexedTerms = 0;
        index = new MiniSearch<IndexedDocument>({
          idField: "id",
          fields: ["title", "aliasesText", "tagsText", "text"],
          storeFields: ["title", "url", "tags", "text"],
          tokenize: text => {
            if (!indexing) return websiteTokenizer(text);
            const allowance = Math.min(10_000, 200_000 - indexedTerms);
            const terms = boundedWebsiteTokenizer(text, allowance + 1);
            if (terms.length > allowance) { limited = true; terms.length = allowance; }
            indexedTerms += terms.length;
            return terms;
          },
          processTerm: (term) => term.normalize("NFKC").toLocaleLowerCase("und"),
          searchOptions: {
            boost: { title: 4, aliasesText: 2.5, tagsText: 1.8, text: 1 },
            prefix: true,
            fuzzy: 0.15,
            maxFuzzy: 1,
            combineWith: "AND"
          }
        });
        for (const document of payload.documents) index.add({
          ...document, aliasesText: document.aliases.join(' '), tagsText: document.tags.join(' ')
        });
        indexing = false;
        post({ type: "ready" });
      })
      .catch(() => post({ type: "error", message: "Search index could not be loaded" }));
    return;
  }

  if (!index) {
    post({ type: "error", message: "Search index is not ready" });
    return;
  }
  pending = message;
  clearTimeout(queryTimer);
  queryTimer = setTimeout(() => {
    const query = pending!;
    pending = undefined;
    // MiniSearch has no top-k executor. Both the corpus and query are bounded;
    // one deferred slot coalesces messages rather than accumulating searches.
    const matches = index!.search(query.query.slice(0, 256));
    const results: SearchWorkerResult[] = matches.slice(0, 12).map(result => {
      const text = String(result.text || '').replace(/\s+/g, ' ');
      const folded = text.toLocaleLowerCase('und');
      const positions = result.terms.map(term => folded.indexOf(term)).filter(index => index >= 0);
      const start = positions.length ? Math.min(...positions) : 0;
      const offset = Math.max(0, start - 50);
      return {
        title: String(result.title), url: String(result.url),
        tags: Array.isArray(result.tags) ? result.tags.map(String) : [],
        excerpt: (offset ? '…' : '') + text.slice(offset, offset + 180) + (text.length > offset + 180 ? '…' : '')
      };
    });
    post({ type: 'results', id: query.id, results, total: matches.length, limited });
  }, 30);
};
