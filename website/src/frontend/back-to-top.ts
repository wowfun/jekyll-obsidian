const controllers = new WeakMap<Document, () => void>();

export function initialiseBackToTop(): () => void {
  const doc = document;
  // Direct repeated initialization has the same cleanup contract as page changes.
  controllers.get(doc)?.();

  const view = doc.defaultView;
  const button = doc.querySelector<HTMLButtonElement>("[data-back-to-top]");
  if (!view || !button) return () => undefined;

  let frame: number | undefined;
  const update = () => {
    frame = undefined;
    const hidden = view.scrollY <= view.innerHeight;
    if (button.hidden !== hidden) button.hidden = hidden;
  };
  const scheduleUpdate = () => {
    frame ??= view.requestAnimationFrame(update);
  };
  const backToTop = () => {
    doc.getElementById("main-content")?.focus({ preventScroll: true });
    view.scrollTo({
      top: 0,
      left: 0,
      behavior: view.matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth"
    });
  };

  view.addEventListener("scroll", scheduleUpdate, { passive: true });
  view.addEventListener("resize", scheduleUpdate);
  view.addEventListener("pageshow", scheduleUpdate);
  button.addEventListener("click", backToTop);
  update();

  const cleanup = () => {
    view.removeEventListener("scroll", scheduleUpdate);
    view.removeEventListener("resize", scheduleUpdate);
    view.removeEventListener("pageshow", scheduleUpdate);
    button.removeEventListener("click", backToTop);
    if (frame !== undefined) view.cancelAnimationFrame(frame);
    button.hidden = true;
    if (controllers.get(doc) === cleanup) controllers.delete(doc);
  };
  controllers.set(doc, cleanup);
  return cleanup;
}
