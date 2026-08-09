const scrollbarController = Symbol.for("jekyll-obsidian.scrollbar-controller");
const activeAttribute = "data-scrollbar-active";
const idleDelay = 1_200;

type ControlledDocument = Document & { [scrollbarController]?: () => void };

export function initialiseAutoHideScrollbars(doc: Document = document): () => void {
  const controlledDocument = doc as ControlledDocument;
  controlledDocument[scrollbarController]?.();

  const view = doc.defaultView;
  if (!view) return () => undefined;

  const root = doc.documentElement;
  const managedRoot = root.hasAttribute("data-auto-hide-root-scrollbar") ? root : null;
  const managedElements = Array.from(doc.querySelectorAll<HTMLElement>("[data-auto-hide-scrollbar]"));
  const timers = new Map<HTMLElement, number>();

  const reveal = (element: HTMLElement) => {
    const previous = timers.get(element);
    if (previous !== undefined) view.clearTimeout(previous);
    element.setAttribute(activeAttribute, "true");
    timers.set(element, view.setTimeout(() => {
      element.removeAttribute(activeAttribute);
      timers.delete(element);
    }, idleDelay));
  };

  const revealRoot = () => {
    if (managedRoot) reveal(managedRoot);
  };
  const revealAtRootEdge = (event: PointerEvent) => {
    if (event.clientX >= view.innerWidth - 18) revealRoot();
  };
  const elementListeners = managedElements.map((element) => {
    const onActivity = () => reveal(element);
    element.addEventListener("pointermove", onActivity, { passive: true });
    element.addEventListener("focusin", onActivity);
    element.addEventListener("scroll", onActivity, { passive: true });
    reveal(element);
    return () => {
      element.removeEventListener("pointermove", onActivity);
      element.removeEventListener("focusin", onActivity);
      element.removeEventListener("scroll", onActivity);
    };
  });

  if (managedRoot) {
    view.addEventListener("scroll", revealRoot, { passive: true });
    doc.addEventListener("pointermove", revealAtRootEdge, { passive: true });
    revealRoot();
  }

  const cleanup = () => {
    if (managedRoot) {
      view.removeEventListener("scroll", revealRoot);
      doc.removeEventListener("pointermove", revealAtRootEdge);
    }
    elementListeners.forEach((remove) => remove());
    for (const [element, timer] of timers) {
      view.clearTimeout(timer);
      element.removeAttribute(activeAttribute);
    }
    timers.clear();
    if (controlledDocument[scrollbarController] === cleanup) delete controlledDocument[scrollbarController];
  };

  controlledDocument[scrollbarController] = cleanup;
  return cleanup;
}
