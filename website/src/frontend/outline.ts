export function initialiseOutline(): () => void {
  const links = Array.from(
    document.querySelectorAll<HTMLAnchorElement>(
      "[data-outline-link][href^='#'], [data-outline] a[href^='#']"
    )
  );
  if (links.length === 0 || !("IntersectionObserver" in window)) return () => undefined;

  const headingLinks = new Map<Element, HTMLAnchorElement>();
  for (const link of links) {
    const fragment = link.hash.slice(1);
    if (!fragment) continue;
    const heading = document.getElementById(decodeURIComponent(fragment));
    if (heading) headingLinks.set(heading, link);
  }
  if (headingLinks.size === 0) return () => undefined;

  let current: HTMLAnchorElement | null = null;
  const mark = (link: HTMLAnchorElement) => {
    if (current === link) return;
    current?.removeAttribute("aria-current");
    link.setAttribute("aria-current", "location");
    current = link;
  };

  const observer = new IntersectionObserver(
    (entries) => {
      const visible = entries
        .filter((entry) => entry.isIntersecting)
        .sort((left, right) => left.boundingClientRect.top - right.boundingClientRect.top);
      const first = visible[0];
      if (first) {
        const link = headingLinks.get(first.target);
        if (link) mark(link);
      }
    },
    { rootMargin: "-12% 0px -72% 0px", threshold: [0, 1] }
  );

  for (const heading of headingLinks.keys()) observer.observe(heading);
  const firstLink = headingLinks.values().next().value as HTMLAnchorElement | undefined;
  if (firstLink) mark(firstLink);
  return () => observer.disconnect();
}
