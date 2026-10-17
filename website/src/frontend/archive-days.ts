interface DayUI {
  year: string; date: string; dateYear: string; months: string[]; weekdays: string[];
  entry: string; entries: string; undated: string;
}
const presentations = new WeakMap<HTMLElement, DayUI>();

function dayUI(root: HTMLElement): DayUI {
  let ui = presentations.get(root);
  if (!ui) {
    // Every archive serializes resolved locale messages, including non-i18n defaults.
    const data = root.querySelector<HTMLElement>("[data-ledger-day-ui]")!.dataset;
    ui = { year: root.dataset.ledgerCurrentYear!, date: data.date!, dateYear: data.dateYear!,
      months: data.months!.split("|"), weekdays: data.weekdays!.split("|"),
      entry: data.entry!, entries: data.entries!, undated: data.undated! };
    presentations.set(root, ui);
  }
  return ui;
}

function entryCount(ui: DayUI, count: number): string {
  return (count === 1 ? ui.entry : ui.entries).replaceAll("{count}", String(count));
}

function dayParts(key: string): { year: string; month: number; day: number; weekday: number } | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return;
  const date = new Date(`${key}T00:00:00Z`);
  if (!Number.isFinite(date.valueOf()) || date.toISOString().slice(0, 10) !== key) return;
  return { year: key.slice(0, 4), month: date.getUTCMonth(), day: date.getUTCDate(), weekday: date.getUTCDay() };
}

export function archiveDayHeading(root: HTMLElement, key: string): { date: string; weekday: string; dated: boolean } {
  const ui = dayUI(root);
  const parts = dayParts(key);
  const format = parts?.year === ui.year ? ui.date : ui.dateYear;
  return {
    date: parts ? format.replaceAll("{month}", ui.months[parts.month]!)
      .replaceAll("{day}", String(parts.day)).replaceAll("{year}", parts.year) : ui.undated,
    weekday: parts ? ui.weekdays[parts.weekday]! : "",
    dated: Boolean(parts)
  };
}

export function createArchiveDay(root: HTMLElement, key: string): HTMLDetailsElement {
  const details = document.createElement("details"); details.className = "archive-day"; details.dataset.ledgerDay = key;
  const summary = document.createElement("summary"), heading = document.createElement("h2");
  const label = archiveDayHeading(root, key);
  const date = document.createElement(label.dated ? "time" : "span"); date.textContent = label.date;
  if (date instanceof HTMLTimeElement) date.dateTime = key;
  heading.append(date);
  const arrow = document.createElement("span"); arrow.className = "archive-day__arrow"; arrow.setAttribute("aria-hidden", "true");
  const meta = document.createElement("span"); meta.className = "archive-day__meta";
  if (label.weekday) { const weekday = document.createElement("span"); weekday.textContent = label.weekday; meta.append(weekday, " · "); }
  const total = document.createElement("span"); total.dataset.ledgerDayCount = ""; meta.append(total);
  summary.append(heading, arrow, meta); details.append(summary);
  return details;
}

/** State belongs to this archive view and survives DOM replacement, never reloads. */
export function initialiseArchiveDays(root: HTMLElement): { replace: (render: () => void) => void; refresh: () => void; dispose: () => void } {
  const choices = new Map<string, boolean>(), applied = new WeakMap<HTMLDetailsElement, boolean>();
  const groups = () => Array.from(root.querySelectorAll<HTMLDetailsElement>("details[data-ledger-day]"));
  // Preserve changes to the usable SSR controls made before hydration finishes.
  for (const group of groups()) applied.set(group, group.hasAttribute("data-ledger-default-open") ? group.dataset.ledgerDefaultOpen === "true" : group.open);
  function capture(current = groups()): void {
    for (const group of current) {
      const previous = applied.get(group);
      if (previous !== undefined && previous !== group.open) choices.set(group.dataset.ledgerDay!, group.open);
      applied.set(group, group.open);
    }
  }
  function refresh(): void {
    const current = groups(); capture(current);
    const visible = current.filter(group => !group.closest("[data-filter-group][hidden]"));
    let newest: string | undefined;
    for (const group of visible) {
      const key = group.dataset.ledgerDay!;
      if (dayParts(key) && (!newest || key > newest)) newest = key;
    }
    newest ||= visible[0]?.dataset.ledgerDay;
    for (const group of visible) {
      const key = group.dataset.ledgerDay!, open = choices.get(key) ?? key === newest;
      applied.set(group, open); group.open = open;
      const count = group.querySelector<HTMLElement>("[data-ledger-day-count]");
      if (count) count.textContent = entryCount(dayUI(root), group.querySelectorAll("[data-filter-item]:not([hidden])").length);
    }
  }
  const onToggle = (event: Event) => {
    if (event.target instanceof HTMLDetailsElement && event.target.hasAttribute("data-ledger-day")) capture();
  };
  // Native disclosure toggle events do not bubble; capture is required.
  root.addEventListener("toggle", onToggle, true);
  refresh();
  return {
    replace(render) {
      // Read synchronous flips before queued toggle events lose their old elements.
      capture(); render(); refresh();
    },
    refresh,
    dispose() { root.removeEventListener("toggle", onToggle, true); choices.clear(); }
  };
}
