const META_PREFIX = "website:";

export type SiteDataName = "catalog" | "search" | "search-worker" | "graph" | "preview";

export function readSiteUrl(name: SiteDataName): string | null {
  const element = document.querySelector<HTMLMetaElement>(
    `meta[name="${META_PREFIX}${name}"]`
  );
  const value = element?.content.trim();
  return value ? value : null;
}

export function requireSiteUrl(name: SiteDataName): string {
  const url = readSiteUrl(name);
  if (!url) {
    throw new Error(`Missing meta[name="website:${name}"] URL`);
  }
  return url;
}
