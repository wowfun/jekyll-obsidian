import { archiveState, type ArchiveCard, type ArchiveManifest } from "./archive-query";
import { archiveUrl } from "./archive-client";

const DAY_MS = 86400000;
export function calendarDay(value: string): number | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return;
  const time = Date.parse(value + "T00:00:00Z");
  if (!Number.isFinite(time) || new Date(time).toISOString().slice(0, 10) !== value) return;
  return time / DAY_MS;
}
export function dateRangeError(start: string, end: string, maxDays: number): "required" | "invalid" | "order" | "limit" | null {
  if (!start || !end) return "required";
  const first = calendarDay(start), last = calendarDay(end);
  if (first === undefined || last === undefined) return "invalid";
  if (first > last) return "order";
  return last - first + 1 > maxDays ? "limit" : null;
}
export function defaultExportDates(data: ArchiveManifest, search: string, ordinals: number[]): [string, string] {
  const selected = new URLSearchParams(search).get("day");
  if (selected && calendarDay(selected) !== undefined) return [selected, selected];
  const first = ordinals[0];
  const end = first === undefined ? undefined : Object.keys(data.days).find(day => first >= data.days[day]![0] && first < data.days[day]![1]);
  if (!end) return ["", ""];
  const start = new Date((calendarDay(end)! - data.export_max_days + 1) * DAY_MS).toISOString().slice(0, 10);
  return [start, end];
}
export function exportState(data: ArchiveManifest, filters: URLSearchParams, start: string, end: string) {
  if (dateRangeError(start, end, data.export_max_days)) throw new Error("Invalid export date range");
  const parameters = new URLSearchParams(filters);
  for (const key of ["day", "month", "year", "page"]) parameters.delete(key);
  const state = archiveState(data, parameters.toString());
  const ranges = Object.entries(data.days).filter(([day]) => day >= start && day <= end).map(([, range]) => range);
  state.query.range = ranges.length ? [Math.min(...ranges.map(range => range[0])), Math.max(...ranges.map(range => range[1]))] : [0, 0];
  return state;
}
function escape(value: string): string { return value.replace(/[\r\n]+/g, " ").replace(/[\\`*_[\]{}<>#!|~]/g, "\\$&"); }
export interface ExportLabels { dates: string; source: string; topic: string; all: string; entries: string; date: string; original: string; article: string }
export interface ExportSnapshot { site: string; locale: string; start: string; end: string; filters: URLSearchParams; cards: ArchiveCard[] }
export function exportMarkdownParts(snapshot: ExportSnapshot, data: ArchiveManifest, bodies: Map<string, string>, labels: ExportLabels): string[] {
  const facetName = (name: string) => name === "source" ? labels.source : name === "topic" ? labels.topic : name;
  const facetValues = (name: string, ids: string[]) => ids.map(id => escape(data.labels[data.prefixes[name]! + id] || id)).join(", ");
  const link = (value: string) => `<${archiveUrl(value, true).href.replace(/</g, "%3C").replace(/>/g, "%3E")}>`;
  const heading = ["# " + escape(snapshot.site), `${labels.dates}: ${snapshot.start} — ${snapshot.end}`,
    ...Object.keys(data.prefixes).map(name => `${facetName(name)}: ${facetValues(name, snapshot.filters.getAll(name)) || labels.all}`),
    `${labels.entries}: ${snapshot.cards.length}`].join("\n\n");
  const parts = [heading];
  for (const card of snapshot.cards) {
    const body = bodies.get(card.id); if (body === undefined) throw new Error("Incomplete export");
    const metadata = [`${labels.date}: ${card.display_date || ""}`,
      ...Object.entries(card.facets).map(([name, ids]) => `${facetName(name)}: ${facetValues(name, ids)}`),
      ...(card.source_url ? [`${labels.original}: ${link(card.source_url)}`] : []), `${labels.article}: ${link(card.url)}`].join("  \n");
    parts.push("\n\n---\n\n", metadata, "\n\n", body.replace(/\r\n?/g, "\n").trimEnd());
  }
  parts.push("\n"); return parts;
}
export function exportFilename(snapshot: ExportSnapshot): string {
  const site = snapshot.site.toLowerCase().replace(/[^\p{L}\p{N}_-]+/gu, "-").replace(/^-+|-+$/g, "") || "archive";
  const locale = snapshot.locale.replace(/[^a-zA-Z0-9-]/g, "") || "en";
  return `${site}-${locale}-${snapshot.start}_${snapshot.end}.md`;
}
