import type { ArchiveCard, ArchiveCollection } from "./archive-query";

export function facetPrefix(prefixes: Record<string, string>, name: string): string {
  return Object.hasOwn(prefixes, name) ? prefixes[name]! : name + "/";
}
export function facetLabel(card: ArchiveCard, name: string, id: string, taxonomy?: Pick<ArchiveCollection, "labels" | "prefixes">): string {
  const key = taxonomy ? facetPrefix(taxonomy.prefixes, name) + id : "";
  const current = taxonomy && Object.hasOwn(taxonomy.labels, key) ? taxonomy.labels[key] : undefined;
  return current || card.favorite_labels?.[name + "/" + id] || id;
}
export function favoriteLabels(card: ArchiveCard, taxonomy?: Pick<ArchiveCollection, "labels" | "prefixes">): Record<string, string> {
  return Object.fromEntries(Object.entries(card.facets).flatMap(([name, ids]) => ids.map(id => [name + "/" + id, facetLabel(card, name, id, taxonomy)])));
}
