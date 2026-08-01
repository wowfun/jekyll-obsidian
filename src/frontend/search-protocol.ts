export interface SearchWorkerResult {
  title: string;
  url: string;
  tags: string[];
}

export type SearchWorkerRequest =
  | { type: "init"; url: string }
  | { type: "query"; id: number; query: string };

export type SearchWorkerResponse =
  | { type: "ready" }
  | { type: "results"; id: number; results: SearchWorkerResult[] }
  | { type: "error"; message: string };
