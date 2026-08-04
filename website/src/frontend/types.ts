export interface CatalogNote {
  id: string;
  title: string;
  url: string;
  aliases: string[];
  tags: string[];
  description: string | null;
  preview: string;
  updated: string | null;
  content_type: "post" | "doc" | "page";
  published_at: string | null;
}

export interface CatalogPayload {
  schema_version: 1;
  notes: CatalogNote[];
}

export interface SearchDocument {
  id: string;
  title: string;
  url: string;
  aliases: string[];
  tags: string[];
  text: string;
}

export interface SearchPayload {
  schema_version: 1;
  documents: SearchDocument[];
}

export interface GraphNode {
  id: string;
  title: string;
  url: string;
  tags?: string[];
  degree?: number;
}

export interface GraphEdge {
  source: string;
  target: string;
  kind: "link" | "embed";
  count: number;
}

export interface GraphPayload {
  schema_version: 1;
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export interface LocalGraphPayload {
  current_id: string;
  nodes: GraphNode[];
  edges: GraphEdge[];
}
