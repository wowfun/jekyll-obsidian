import type {
  CatalogNote,
  CatalogPayload,
  GraphEdge,
  GraphNode,
  GraphPayload,
  SearchDocument,
  SearchPayload
} from "./types";

type UnknownRecord = Record<string, unknown>;

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((entry) => typeof entry === "string");
}

function isCatalogNote(value: unknown): value is CatalogNote {
  if (!isRecord(value)) return false;
  return (
    typeof value.id === "string" &&
    typeof value.title === "string" &&
    typeof value.url === "string" &&
    isStringArray(value.aliases) &&
    isStringArray(value.tags) &&
    (typeof value.description === "string" || value.description === null) &&
    typeof value.preview === "string" &&
    (typeof value.updated === "string" || value.updated === null) &&
    (value.content_type === "post" || value.content_type === "doc" || value.content_type === "page") &&
    (typeof value.published_at === "string" || value.published_at === null)
  );
}

function isSearchDocument(value: unknown): value is SearchDocument {
  if (!isRecord(value)) return false;
  return (
    typeof value.id === "string" &&
    typeof value.title === "string" &&
    typeof value.url === "string" &&
    isStringArray(value.aliases) &&
    isStringArray(value.tags) &&
    typeof value.text === "string"
  );
}

function isGraphNode(value: unknown): value is GraphNode {
  if (!isRecord(value)) return false;
  return (
    typeof value.id === "string" &&
    typeof value.title === "string" &&
    typeof value.url === "string" &&
    (value.degree === undefined || (
      typeof value.degree === "number" && Number.isSafeInteger(value.degree) && value.degree >= 0
    )) &&
    (value.tags === undefined || isStringArray(value.tags))
  );
}

function isGraphEdge(value: unknown): value is GraphEdge {
  if (!isRecord(value)) return false;
  return (
    typeof value.source === "string" &&
    typeof value.target === "string" &&
    (value.kind === "link" || value.kind === "embed") &&
    typeof value.count === "number" &&
    Number.isSafeInteger(value.count) &&
    value.count > 0
  );
}

export function parseCatalogPayload(value: unknown): CatalogPayload {
  if (
    !isRecord(value) ||
    value.schema_version !== 1 ||
    !Array.isArray(value.notes) ||
    !value.notes.every(isCatalogNote)
  ) {
    throw new TypeError("catalog.v1.json does not match schema version 1");
  }
  return value as unknown as CatalogPayload;
}

export function parseSearchPayload(value: unknown): SearchPayload {
  if (
    !isRecord(value) ||
    value.schema_version !== 1 ||
    !Array.isArray(value.documents) ||
    !value.documents.every(isSearchDocument)
  ) {
    throw new TypeError("search.v1.json does not match schema version 1");
  }
  return value as unknown as SearchPayload;
}

export function parseGraphPayload(value: unknown): GraphPayload {
  if (
    !isRecord(value) ||
    value.schema_version !== 1 ||
    !Array.isArray(value.nodes) ||
    !value.nodes.every(isGraphNode) ||
    !Array.isArray(value.edges) ||
    !value.edges.every(isGraphEdge)
  ) {
    throw new TypeError("graph.v1.json does not match schema version 1");
  }
  return value as unknown as GraphPayload;
}

export async function fetchJson(url: string, signal?: AbortSignal): Promise<unknown> {
  const response = await fetch(url, {
    credentials: "same-origin",
    headers: { Accept: "application/json" },
    ...(signal ? { signal } : {})
  });
  if (!response.ok) {
    throw new Error(`Unable to load ${url}: ${response.status}`);
  }
  return response.json() as Promise<unknown>;
}
