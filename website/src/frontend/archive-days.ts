const MONTHS = "January|February|March|April|May|June|July|August|September|October|November|December";
const WEEKDAYS = "Sunday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday";

function dayParts(key: string): { year: string; month: number; day: number; weekday: number } | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return;
  const date = new Date(`${key}T00:00:00Z`);
  if (!Number.isFinite(date.valueOf()) || date.toISOString().slice(0, 10) !== key) return;
  return { year: key.slice(0, 4), month: date.getUTCMonth(), day: date.getUTCDate(), weekday: date.getUTCDay() };
}

export function archiveDayHeading(root: HTMLElement, key: string, count: number): { date: string; weekday: string; count: string; dated: boolean } {
  const ui = root.querySelector<HTMLElement>("[data-ledger-day-ui]")?.dataset || {};
  const parts = dayParts(key);
  const format = parts?.year === (root.dataset.ledgerCurrentYear || String(new Date().getUTCFullYear()))
    ? ui.date || "{month} {day}" : ui.dateYear || "{month} {day}, {year}";
  return {
    date: parts ? format.replaceAll("{month}", (ui.months || MONTHS).split("|")[parts.month]!)
      .replaceAll("{day}", String(parts.day)).replaceAll("{year}", parts.year) : ui.undated || "Undated",
    weekday: parts ? (ui.weekdays || WEEKDAYS).split("|")[parts.weekday]! : "",
    count: (count === 1 ? ui.entry || "{count} entry" : ui.entries || "{count} entries").replaceAll("{count}", String(count)),
    dated: Boolean(parts)
  };
}

export function createArchiveDay(root: HTMLElement, key: string, count: number, open: boolean): HTMLDetailsElement {
  const details = document.createElement("details"); details.className = "archive-day"; details.dataset.ledgerDay = key;
  details.open = open; details.dataset.ledgerDefaultOpen = String(open);
  const summary = document.createElement("summary"), heading = document.createElement("h2");
  const label = archiveDayHeading(root, key, count);
  const date = document.createElement(label.dated ? "time" : "span"); date.textContent = label.date;
  if (date instanceof HTMLTimeElement) date.dateTime = key;
  heading.append(date);
  const arrow = document.createElement("span"); arrow.className = "archive-day__arrow"; arrow.setAttribute("aria-hidden", "true");
  const meta = document.createElement("span"); meta.className = "archive-day__meta";
  if (label.weekday) { const weekday = document.createElement("span"); weekday.textContent = label.weekday; meta.append(weekday, " · "); }
  const total = document.createElement("span"); total.dataset.ledgerDayCount = ""; total.textContent = label.count; meta.append(total);
  summary.append(heading, arrow, meta); details.append(summary);
  return details;
}

/** State belongs to this archive view and survives DOM replacement, never reloads. */
export function initialiseArchiveDays(root: HTMLElement): { capture: () => void; refresh: () => void; dispose: () => void } {
  const choices = new Map<string, boolean>(), applied = new WeakMap<HTMLDetailsElement, boolean>();
  const groups = () => Array.from(root.querySelectorAll<HTMLDetailsElement>("details[data-ledger-day]"));
  for (const group of groups()) applied.set(group, group.dataset.ledgerDefaultOpen === "true");
  function capture(): void {
    for (const group of groups()) {
      const previous = applied.get(group);
      if (previous !== undefined && previous !== group.open) choices.set(group.dataset.ledgerDay!, group.open);
      applied.set(group, group.open);
    }
  }
  function refresh(): void {
    capture();
    const visible = groups().filter(group => !group.closest("[data-filter-group][hidden]"));
    const newest = visible.map(group => group.dataset.ledgerDay!).filter(key => dayParts(key)).sort().at(-1)
      || visible[0]?.dataset.ledgerDay;
    for (const group of visible) {
      const key = group.dataset.ledgerDay!, open = choices.get(key) ?? key === newest;
      applied.set(group, open); group.open = open;
      const count = group.querySelector<HTMLElement>("[data-ledger-day-count]");
      if (count) count.textContent = archiveDayHeading(root, key, group.querySelectorAll("[data-filter-item]:not([hidden])").length).count;
    }
  }
  const onToggle = (event: Event) => {
    if (event.target instanceof HTMLDetailsElement && event.target.hasAttribute("data-ledger-day")) capture();
  };
  root.addEventListener("toggle", onToggle, true);
  refresh();
  return { capture, refresh, dispose() { root.removeEventListener("toggle", onToggle, true); choices.clear(); } };
}
