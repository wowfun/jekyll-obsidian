function selectedValue(
  parameters: URLSearchParams,
  name: string,
  options: HTMLElement[],
  dataKey: "topicAnchor" | "filterYear" | "filterMonth"
): string {
  const requested = parameters.get(name) ?? "";
  return options.some((option) => option.dataset[dataKey] === requested) ? requested : "";
}

function applyFilters(root: HTMLElement): void {
  const parameters = new URLSearchParams(window.location.search);
  const topicOptions = Array.from(document.querySelectorAll<HTMLElement>("[data-topic-filter-option]"));
  const yearOptions = Array.from(document.querySelectorAll<HTMLElement>("[data-year-filter-option]"));
  const monthOptions = Array.from(document.querySelectorAll<HTMLElement>("[data-month-filter-option]"));
  const topic = selectedValue(parameters, "topic", topicOptions, "topicAnchor");
  const month = selectedValue(parameters, "month", monthOptions, "filterMonth");
  const year = month ? "" : selectedValue(parameters, "year", yearOptions, "filterYear");

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

  const items = Array.from(root.querySelectorAll<HTMLElement>("[data-filter-item]"));
  for (const item of items) {
    const topics = (item.dataset.topicAnchors ?? "").split(/\s+/).filter(Boolean);
    const itemMonth = item.dataset.filterMonth ?? "";
    item.hidden = Boolean(
      (topic && !topics.includes(topic)) ||
      (year && !itemMonth.startsWith(`${year}-`)) ||
      (month && itemMonth !== month)
    );
  }

  for (const group of root.querySelectorAll<HTMLElement>("[data-filter-group]")) {
    group.hidden = !group.querySelector("[data-filter-item]:not([hidden])");
  }

  const empty = root.querySelector<HTMLElement>("[data-filter-empty]");
  if (empty) empty.hidden = items.some((item) => !item.hidden);
}

export function initialiseArchiveFilters(): () => void {
  const roots = Array.from(document.querySelectorAll<HTMLElement>("[data-filter-page]"));
  if (roots.length === 0) return () => undefined;

  const refresh = () => roots.forEach(applyFilters);
  const onClick = (event: MouseEvent) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    const link = target.closest<HTMLAnchorElement>(
      "a[data-topic-filter-option], a[data-year-filter-option], a[data-month-filter-option]"
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
    } else if (link.hasAttribute("data-year-filter-option")) {
      next.searchParams.set("year", link.dataset.filterYear ?? "");
      next.searchParams.delete("month");
    } else {
      next.searchParams.set("month", link.dataset.filterMonth ?? "");
      next.searchParams.delete("year");
    }
    window.history.pushState(null, "", `${next.pathname}${next.search}`);
    refresh();
  };

  document.addEventListener("click", onClick);
  window.addEventListener("popstate", refresh);
  window.addEventListener("pageshow", refresh);
  refresh();

  return () => {
    document.removeEventListener("click", onClick);
    window.removeEventListener("popstate", refresh);
    window.removeEventListener("pageshow", refresh);
  };
}
