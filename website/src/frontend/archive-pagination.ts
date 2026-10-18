export function pageWindow(page: number, pages: number): number[] {
  const count = Math.min(5, pages), start = Math.max(1, Math.min(page - 2, pages - count + 1));
  return Array.from({ length: count }, (_, index) => start + index);
}

export function renderArchivePagination(root: HTMLElement, page: number, pages: number, count: number): void {
  const pageText = root.dataset.pageLabel || "Page {page} of {pages}", resultText = root.dataset.resultLabel || "{count} entries";
  root.querySelector<HTMLElement>("[data-archive-page-status]")!.textContent = `${resultText.replace("{count}", String(count))} · ${pageText.replace("{page}", String(page)).replace("{pages}", String(pages))}`;
  root.querySelector<HTMLButtonElement>("[data-archive-page=prev]")!.disabled = page <= 1;
  root.querySelector<HTMLButtonElement>("[data-archive-page=next]")!.disabled = page >= pages;
  const numbers = root.querySelector<HTMLElement>("[data-archive-page-numbers]")!;
  numbers.replaceChildren(); numbers.hidden = pages <= 1;
  for (const number of pageWindow(page, pages)) {
    const link = document.createElement("a"), url = new URL(location.href);
    number === 1 ? url.searchParams.delete("page") : url.searchParams.set("page", String(number));
    link.href = url.pathname + url.search;
    link.dataset.archivePage = String(number); link.textContent = String(number);
    link.setAttribute("aria-label", (root.dataset.numberLabel || "Page {page}").replace("{page}", String(number)));
    if (number === page) link.setAttribute("aria-current", "page");
    numbers.append(link);
  }
  const form = root.querySelector<HTMLFormElement>("[data-archive-page-jump]")!, input = form.querySelector<HTMLInputElement>("input")!;
  if (document.activeElement !== input || root.dataset.currentPage !== String(page)) input.value = String(page);
  root.dataset.currentPage = String(page);
  input.max = String(pages); input.disabled = count === 0;
  if (document.activeElement !== input) input.setCustomValidity("");
  form.hidden = pages <= 1;
}
