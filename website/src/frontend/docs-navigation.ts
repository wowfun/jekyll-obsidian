export async function initialiseDocsNavigation(): Promise<void> {
  const navigation = document.querySelector<HTMLElement>("[data-docs-navigation]");
  const url = navigation?.dataset.docsNavigationUrl;
  if (!navigation || !url) return;

  const response = await fetch(url, { credentials: "same-origin" });
  if (!response.ok) throw new Error(`Documentation navigation returned HTTP ${response.status}`);
  const template = document.createElement("template");
  template.innerHTML = await response.text();
  navigation.replaceChildren(template.content);

  const current = new URL(window.location.href);
  for (const link of navigation.querySelectorAll<HTMLAnchorElement>("a[href]")) {
    const target = new URL(link.href, current);
    if (target.origin === current.origin && target.pathname === current.pathname) {
      link.setAttribute("aria-current", "page");
    }
  }
  navigation.dataset.docsNavigationReady = "true";
}
