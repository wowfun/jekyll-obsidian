export interface SearchWorkerResult {
  title: string;
  url: string;
  tags: string[];
  excerpt?: string;
}

export type SearchWorkerRequest =
  | { type: "init"; url: string }
  | { type: "query"; id: number; query: string };

export type SearchWorkerResponse =
  | { type: "ready" }
  | { type: "results"; id: number; results: SearchWorkerResult[]; total: number; limited: boolean }
  | { type: "error"; message: string };
