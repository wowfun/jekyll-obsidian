import type { ArchiveCard, ArchiveManifest } from "./archive-query";

export function facetPrefix(prefixes: Record<string, string>, name: string): string {
  return Object.hasOwn(prefixes, name) ? prefixes[name]! : name + "/";
}
export function facetLabel(card: ArchiveCard, name: string, id: string, taxonomy?: Pick<ArchiveManifest, "labels" | "prefixes">): string {
  return taxonomy?.labels[facetPrefix(taxonomy.prefixes, name) + id] || card.favorite_labels?.[name + "/" + id] || id;
}
export function favoriteLabels(card: ArchiveCard, taxonomy?: Pick<ArchiveManifest, "labels" | "prefixes">): Record<string, string> {
  return Object.fromEntries(Object.entries(card.facets).flatMap(([name, ids]) => ids.map(id => [name + "/" + id, facetLabel(card, name, id, taxonomy)])));
}
