export function initialiseLanguageSwitcher(): void {
  for (const details of document.querySelectorAll<HTMLDetailsElement>("[data-language-switcher]")) {
    const summary = details.querySelector<HTMLElement>("summary");
    const panel = details.querySelector<HTMLElement>(".language-switcher__panel");
    let openedByHover = false;
    const close = () => { details.open = false; openedByHover = false; };
    const fitPanel = () => {
      if (!panel || !details.open) return;
      const bounds = details.getBoundingClientRect();
      const available = getComputedStyle(details).direction === "rtl"
        ? document.documentElement.clientWidth - bounds.left : bounds.right;
      panel.style.setProperty("--language-panel-available", `${Math.max(0, available - 16)}px`);
    };
    details.addEventListener("toggle", fitPanel);
    window.addEventListener("resize", fitPanel);

    details.addEventListener("pointerenter", (event) => {
      if (event.pointerType !== "mouse" || !window.matchMedia("(any-hover: hover)").matches || details.open) return;
      openedByHover = true;
      details.open = true;
    });
    details.addEventListener("pointerleave", (event) => {
      if (event.pointerType === "mouse" && openedByHover && !panel?.contains(document.activeElement)) close();
    });
    details.addEventListener("focusout", (event) => {
      if (openedByHover && !details.matches(":hover") && !(event.relatedTarget instanceof Node && details.contains(event.relatedTarget))) close();
    });

    details.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element)) return;
      // A pointer click should not undo the menu that its hover just opened.
      if (openedByHover && event.detail > 0 && target.closest("summary") === summary) event.preventDefault();
      if (!document.querySelector("[data-paged-archive]")) return;
      const link = target.closest<HTMLAnchorElement>("a[href]");
      if (link) { const url = new URL(link.href); url.search = window.location.search; link.href = url.href; }
    });
    details.addEventListener("keydown", (event) => {
      if (event.key !== "Escape" || !details.open) return;
      event.preventDefault();
      close();
      summary?.focus();
    });

    document.addEventListener("click", (event) => {
      if (!details.open || !(event.target instanceof Node) || details.contains(event.target)) return;
      close();
    });
  }
}
