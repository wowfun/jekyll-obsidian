export function initialiseLanguageSwitcher(): void {
  for (const details of document.querySelectorAll<HTMLDetailsElement>("[data-language-switcher]")) {
    const summary = details.querySelector<HTMLElement>("summary");

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
