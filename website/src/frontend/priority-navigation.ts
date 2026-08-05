const priorityNavigationController = Symbol.for("jekyll-obsidian.priority-navigation-controller");

type ControlledDocument = Document & { [priorityNavigationController]?: () => void };

export function initialisePriorityNavigation(): void {
  const controlledDocument = document as ControlledDocument;
  controlledDocument[priorityNavigationController]?.();

  const navigation = document.querySelector<HTMLElement>("[data-priority-navigation]");
  const list = navigation?.querySelector<HTMLUListElement>("[data-priority-navigation-list]");
  const more = navigation?.querySelector<HTMLDetailsElement>("[data-priority-navigation-more]");
  const overflow = navigation?.querySelector<HTMLUListElement>("[data-priority-navigation-overflow]");
  if (!navigation || !list || !more || !overflow || typeof ResizeObserver === "undefined") return;

  const items = [...list.querySelectorAll<HTMLElement>(":scope > [data-priority-navigation-item]")];
  let animationFrame = 0;

  const restoreItems = () => {
    list.append(...items);
    more.hidden = true;
    more.open = false;
    delete more.dataset.hasCurrent;
  };

  const fitItems = () => {
    restoreItems();
    if (window.matchMedia("(max-width: 880px)").matches || items.length < 2) return;

    const available = navigation.clientWidth;
    if (list.scrollWidth <= available) return;

    more.hidden = false;
    while (list.children.length > 1 && list.scrollWidth + more.offsetWidth + 6 > available) {
      const item = list.lastElementChild;
      if (!item) break;
      overflow.prepend(item);
    }
    if (overflow.querySelector('[aria-current="page"]')) more.dataset.hasCurrent = "true";
  };

  const scheduleFit = () => {
    window.cancelAnimationFrame(animationFrame);
    animationFrame = window.requestAnimationFrame(fitItems);
  };

  const observer = new ResizeObserver(scheduleFit);
  observer.observe(navigation);
  document.fonts?.ready.then(scheduleFit).catch(() => undefined);
  scheduleFit();

  const closeWhenClickingAway = (event: MouseEvent) => {
    const target = event.target;
    if (more.open && target instanceof Node && !more.contains(target)) more.open = false;
  };
  document.addEventListener("click", closeWhenClickingAway);

  const cleanup = () => {
    observer.disconnect();
    window.cancelAnimationFrame(animationFrame);
    document.removeEventListener("click", closeWhenClickingAway);
    restoreItems();
    delete navigation.dataset.priorityNavigationReady;
    if (controlledDocument[priorityNavigationController] === cleanup) delete controlledDocument[priorityNavigationController];
  };

  navigation.dataset.priorityNavigationReady = "true";
  controlledDocument[priorityNavigationController] = cleanup;
}
