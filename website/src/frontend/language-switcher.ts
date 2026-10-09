export function initialiseLanguageSwitcher(): void {
  for (const details of document.querySelectorAll<HTMLDetailsElement>("[data-language-switcher]")) {
    const summary = details.querySelector<HTMLElement>("summary");

    details.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element) || !document.querySelector("[data-paged-archive]")) return;
      const link = target.closest<HTMLAnchorElement>("a[href]");
      if (link) { const url = new URL(link.href); url.search = window.location.search; link.href = url.href; }
    });
    details.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || !details.open) return;
      event.preventDefault();
      details.open = false;
      summary?.focus();
    });

    document.addEventListener("click", (event) => {
      if (!details.open || !(event.target instanceof Node) || details.contains(event.target)) return;
      details.open = false;
    });
  }
}
