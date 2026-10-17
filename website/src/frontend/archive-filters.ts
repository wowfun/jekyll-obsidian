import { initialisePagedArchive } from "./paged-archive";
import { initialiseArchiveDays } from "./archive-days";

function selectedValue(
  parameters: URLSearchParams,
  name: string,
  options: HTMLElement[],
  dataKey: "topicAnchor" | "filterYear" | "filterMonth" | "filterDay"
): string {
  const requested = parameters.get(name) ?? "";
  return options.some((option) => option.dataset[dataKey] === requested) ? requested : "";
}

function applyFilters(root: HTMLElement): void {
  const parameters = new URLSearchParams(window.location.search);
  const topicOptions = Array.from(document.querySelectorAll<HTMLElement>(
    "[data-topic-filter-nav] [data-topic-filter-option]"
  ));
  const yearOptions = Array.from(document.querySelectorAll<HTMLElement>("[data-year-filter-option]"));
  const monthOptions = Array.from(document.querySelectorAll<HTMLElement>("[data-month-filter-option]"));
  const dayOptions = Array.from(document.querySelectorAll<HTMLElement>("[data-day-filter-option]"));
  const topic = selectedValue(parameters, "topic", topicOptions, "topicAnchor");
  const day = selectedValue(parameters, "day", dayOptions, "filterDay");
  const month = day ? "" : selectedValue(parameters, "month", monthOptions, "filterMonth");
  const year = day || month ? "" : selectedValue(parameters, "year", yearOptions, "filterYear");

  for (const option of topicOptions) {
    if (option.dataset.topicAnchor === topic) option.setAttribute("aria-current", "page");
    else option.removeAttribute("aria-current");
  }
  for (const option of yearOptions) {
    if (year && option.dataset.filterYear === year) option.setAttribute("aria-current", "page");
    else option.removeAttribute("aria-current");
  }
  for (const option of monthOptions) {
    if (month && option.dataset.filterMonth === month) option.setAttribute("aria-current", "page");
    else option.removeAttribute("aria-current");
  }
  for (const option of dayOptions) {
    if (day && option.dataset.filterDay === day) option.setAttribute("aria-current", "page");
    else option.removeAttribute("aria-current");
  }

  const items = Array.from(root.querySelectorAll<HTMLElement>("[data-filter-item]"));
  for (const item of items) {
    const topics = (item.dataset.topicAnchors ?? "").split(/\s+/).filter(Boolean);
    const itemMonth = item.dataset.filterMonth ?? "";
    item.hidden = Boolean(
      (topic && !topics.includes(topic)) ||
      (year && !itemMonth.startsWith(`${year}-`)) ||
      (month && itemMonth !== month) ||
      (day && item.dataset.filterDay !== day)
    );
  }

  for (const group of root.querySelectorAll<HTMLElement>("[data-filter-group]")) {
    group.hidden = !group.querySelector("[data-filter-item]:not([hidden])");
  }

  const empty = root.querySelector<HTMLElement>("[data-filter-empty]");
  if (empty) empty.hidden = items.some((item) => !item.hidden);
}

export function initialiseArchiveFilters(): () => void {
  const paged = Array.from(document.querySelectorAll<HTMLElement>("[data-paged-archive]"));
  const cleanups = paged.map(initialisePagedArchive);
  const roots = Array.from(document.querySelectorAll<HTMLElement>("[data-filter-page]:not([data-paged-archive])"));
  if (roots.length === 0) return () => cleanups.forEach((cleanup) => cleanup());

  const days = roots.map(initialiseArchiveDays);
  const refresh = () => roots.forEach((root, index) => { applyFilters(root); days[index]!.refresh(); });
  const onClick = (event: MouseEvent) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const link = target.closest<HTMLAnchorElement>(
      "a[data-topic-filter-option], a[data-year-filter-option], a[data-month-filter-option], a[data-day-filter-option]"
    );
    if (!link) return;
    const destination = new URL(link.href, window.location.href);
    if (destination.origin !== window.location.origin || destination.pathname !== window.location.pathname) return;

    event.preventDefault();
    const next = new URL(window.location.href);
    next.pathname = destination.pathname;
    if (link.hasAttribute("data-topic-filter-option")) {
      const topic = link.dataset.topicAnchor ?? "";
      topic ? next.searchParams.set("topic", topic) : next.searchParams.delete("topic");
    } else {
      const name = link.hasAttribute("data-year-filter-option") ? "year" : link.hasAttribute("data-month-filter-option") ? "month" : "day";
      const value = link.getAttribute(`data-filter-${name}`) ?? "";
      if (link.getAttribute("aria-current") === "page") next.searchParams.delete(name);
      else next.searchParams.set(name, value);
      for (const other of ["year", "month", "day"]) if (other !== name) next.searchParams.delete(other);
    }
    window.history.pushState(null, "", `${next.pathname}${next.search}`);
    refresh();
  };

  document.addEventListener("click", onClick);
  window.addEventListener("popstate", refresh);
  window.addEventListener("pageshow", refresh);
  refresh();

  return () => {
    days.forEach(day => day.dispose());
    cleanups.forEach((cleanup) => cleanup());
    document.removeEventListener("click", onClick);
    window.removeEventListener("popstate", refresh);
    window.removeEventListener("pageshow", refresh);
  };
}
